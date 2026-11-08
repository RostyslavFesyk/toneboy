// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

#include "AudioDSP.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define RING_SIZE 32768u
typedef struct { double b0, b1, b2, a1, a2; } Coeff;
typedef struct { double z1, z2; } State;
struct TBDSP {
    double rate;
    _Atomic double frequency[TB_BANDS], gain[TB_BANDS], q[TB_BANDS], output;
    _Atomic bool bypass;
    _Atomic uint32_t generation;
    uint32_t appliedGeneration, rampRemaining, inputOffset;
    Coeff current[TB_BANDS], target[TB_BANDS];
    State state[TB_BANDS][2];
    double volume, dryMix, limiter;
    float ring[RING_SIZE];
    _Atomic uint32_t readIndex, writeIndex;
    _Atomic float peak;
    _Atomic uint64_t callbacks;
};
static double clamp(double x, double low, double high) { return fmax(low, fmin(x, high)); }
static Coeff coefficients(int band, double f, double db, double q, double rate) {
    double a = pow(10.0, db / 40.0);
    double w = 2.0 * M_PI * clamp(f, 20.0, rate * 0.45) / rate;
    // RBJ shelving filters; q is monotonic shelf slope S for the edge bands.
    // Reference: https://www.w3.org/TR/audio-eq-cookbook/
    if (band == 0 || band == TB_BANDS-1) {
        double c = cos(w), slope = clamp(q, 0.1, 1.0);
        double alpha = sin(w)*0.5*sqrt((a+1/a)*(1/slope-1)+2);
        double t = 2*sqrt(a)*alpha;
        double b0,b1,b2,a0,a1,a2;
        if (band == 0) {
            b0=a*((a+1)-(a-1)*c+t); b1=2*a*((a-1)-(a+1)*c);
            b2=a*((a+1)-(a-1)*c-t); a0=(a+1)+(a-1)*c+t;
            a1=-2*((a-1)+(a+1)*c); a2=(a+1)+(a-1)*c-t;
        } else {
            b0=a*((a+1)+(a-1)*c+t); b1=-2*a*((a-1)+(a+1)*c);
            b2=a*((a+1)+(a-1)*c-t); a0=(a+1)-(a-1)*c+t;
            a1=2*((a-1)-(a+1)*c); a2=(a+1)-(a-1)*c-t;
        }
        return (Coeff){b0/a0,b1/a0,b2/a0,a1/a0,a2/a0};
    }
    double alpha = sin(w) / (2.0 * clamp(q, 0.1, 12.0));
    double a0 = 1.0 + alpha / a;
    return (Coeff){(1.0 + alpha * a) / a0, -2.0 * cos(w) / a0,
        (1.0 - alpha * a) / a0, -2.0 * cos(w) / a0, (1.0 - alpha / a) / a0};
}
TBDSP *tb_create(double sampleRate) {
    if (!isfinite(sampleRate) || sampleRate < 8000) { return NULL; }
    TBDSP *d = calloc(1, sizeof(TBDSP));
    if (!d) { return NULL; }
    d->rate = sampleRate; d->volume = 1.0; d->limiter = 1.0;
    atomic_init(&d->generation, 0); atomic_init(&d->output, 0);
    atomic_init(&d->bypass, false); atomic_init(&d->readIndex, 0);
    atomic_init(&d->writeIndex, 0); atomic_init(&d->peak, 0);
    atomic_init(&d->callbacks, 0);
    const double frequencies[] = {80, 400, 2500, 10000};
    for (int i = 0; i < TB_BANDS; ++i) {
        atomic_init(&d->frequency[i], frequencies[i]);
        atomic_init(&d->gain[i], 0); atomic_init(&d->q[i], 0.8);
        d->current[i] = d->target[i] = coefficients(i, frequencies[i], 0, 0.8, sampleRate);
    }
    // The audio callback must never enter a library fallback lock.
    if (!atomic_is_lock_free(&d->frequency[0]) || !atomic_is_lock_free(&d->peak) ||
        !atomic_is_lock_free(&d->callbacks)) { free(d); return NULL; }
    return d;
}
void tb_destroy(TBDSP *d) { free(d); }
void tb_set_band(TBDSP *d, int i, double f, double db, double q) {
    if (!d || i < 0 || i >= TB_BANDS || !isfinite(f) || !isfinite(db) || !isfinite(q)) { return; }
    atomic_store_explicit(&d->frequency[i], clamp(f, 20, 20000), memory_order_relaxed);
    atomic_store_explicit(&d->gain[i], clamp(db, -18, 18), memory_order_relaxed);
    atomic_store_explicit(&d->q[i], clamp(q, 0.1, 12), memory_order_relaxed);
    atomic_fetch_add_explicit(&d->generation, 1, memory_order_release);
}
void tb_set_output(TBDSP *d, double gainDB, bool bypass) {
    if (!d || !isfinite(gainDB)) { return; }
    atomic_store_explicit(&d->output, clamp(gainDB, -24, 0), memory_order_relaxed);
    atomic_store_explicit(&d->bypass, bypass, memory_order_relaxed);
}
void tb_set_input_offset(TBDSP *d, uint32_t channels) { d->inputOffset = channels; }
static void beginBlock(TBDSP *d) {
    uint32_t generation = atomic_load_explicit(&d->generation, memory_order_acquire);
    if (generation != d->appliedGeneration) {
        for (int i = 0; i < TB_BANDS; ++i) {
            d->target[i] = coefficients(i, atomic_load_explicit(&d->frequency[i], memory_order_relaxed),
                atomic_load_explicit(&d->gain[i], memory_order_relaxed),
                atomic_load_explicit(&d->q[i], memory_order_relaxed), d->rate);
        }
        d->rampRemaining = (uint32_t)(0.02 * d->rate);
        d->appliedGeneration = generation;
    }
}
static void frame(TBDSP *d, float left, float right, float *outLeft, float *outRight) {
    if (!isfinite(left)) { left = 0; } if (!isfinite(right)) { right = 0; }
    double samples[] = {left, right};
    for (int i = 0; i < TB_BANDS; ++i) {
        Coeff *c = &d->current[i], *t = &d->target[i];
        if (d->rampRemaining) {
            double divisor = d->rampRemaining;
            c->b0 += (t->b0-c->b0)/divisor; c->b1 += (t->b1-c->b1)/divisor;
            c->b2 += (t->b2-c->b2)/divisor; c->a1 += (t->a1-c->a1)/divisor;
            c->a2 += (t->a2-c->a2)/divisor;
        }
        for (int ch = 0; ch < 2; ++ch) {
            State *s = &d->state[i][ch];
            double y = c->b0 * samples[ch] + s->z1;
            s->z1 = c->b1 * samples[ch] - c->a1 * y + s->z2;
            s->z2 = c->b2 * samples[ch] - c->a2 * y;
            if (fabs(s->z1) < 1e-25) { s->z1 = 0; }
            if (fabs(s->z2) < 1e-25) { s->z2 = 0; }
            samples[ch] = y;
        }
    }
    if (d->rampRemaining) { --d->rampRemaining; }
    double targetVolume = pow(10, atomic_load_explicit(&d->output, memory_order_relaxed) / 20.0);
    double targetDry = atomic_load_explicit(&d->bypass, memory_order_relaxed) ? 1 : 0;
    double smoothing = 1.0 / (0.005 * d->rate);
    d->volume += smoothing * (targetVolume - d->volume);
    d->dryMix += smoothing * (targetDry - d->dryMix);
    samples[0] *= d->volume;
    samples[1] *= d->volume;
    double peak = fmax(fabs(samples[0]), fabs(samples[1]));
    double ceiling = peak > 0.98 ? 0.98 / peak : 1.0;
    d->limiter = ceiling < d->limiter ? ceiling : d->limiter + (ceiling-d->limiter)/(0.08*d->rate);
    *outLeft = (float)(samples[0] * d->limiter * (1-d->dryMix) + left * d->dryMix);
    *outRight = (float)(samples[1] * d->limiter * (1-d->dryMix) + right * d->dryMix);
    // SPSC ring: the producer never overwrites a sample being read by the UI.
    uint32_t w = atomic_load_explicit(&d->writeIndex, memory_order_relaxed);
    uint32_t r = atomic_load_explicit(&d->readIndex, memory_order_acquire);
    if (w-r < RING_SIZE) {
        d->ring[w % RING_SIZE] = (left+right)*0.5f;
        atomic_store_explicit(&d->writeIndex, w+1, memory_order_release);
    }
}
void tb_process(TBDSP *d, const float *left, const float *right, float *outLeft, float *outRight, uint32_t frames) {
    beginBlock(d); float peak = 0;
    for (uint32_t i = 0; i < frames; ++i) {
        frame(d, left[i], right[i], &outLeft[i], &outRight[i]);
        peak = fmaxf(peak, fmaxf(fabsf(outLeft[i]), fabsf(outRight[i])));
    }
    atomic_store_explicit(&d->peak, peak, memory_order_relaxed);
}
uint32_t tb_read_analysis(TBDSP *d, float *samples, uint32_t capacity) {
    uint32_t r = atomic_load_explicit(&d->readIndex, memory_order_relaxed);
    uint32_t w = atomic_load_explicit(&d->writeIndex, memory_order_acquire);
    uint32_t n = w-r; if (n > capacity) { r = w-capacity; n = capacity; }
    for (uint32_t i = 0; i < n; ++i) { samples[i] = d->ring[(r+i)%RING_SIZE]; }
    atomic_store_explicit(&d->readIndex, w, memory_order_release);
    return n;
}
float tb_peak(TBDSP *d) { return atomic_load_explicit(&d->peak, memory_order_relaxed); }
uint64_t tb_callback_count(TBDSP *d) { return atomic_load_explicit(&d->callbacks, memory_order_relaxed); }
double tb_band_response(int band, double f, double center, double gainDB, double q, double rate) {
    Coeff c = coefficients(band, center, gainDB, q, rate);
    double w = 2*M_PI*f/rate;
    double nr = c.b0+c.b1*cos(w)+c.b2*cos(2*w), ni = -c.b1*sin(w)-c.b2*sin(2*w);
    double dr = 1+c.a1*cos(w)+c.a2*cos(2*w), di = -c.a1*sin(w)-c.a2*sin(2*w);
    return 10*log10(fmax(1e-20,(nr*nr+ni*ni)/(dr*dr+di*di)));
}
double tb_response(double f, double center, double gainDB, double q, double rate) {
    return tb_band_response(1, f, center, gainDB, q, rate);
}
static float readChannel(const AudioBufferList *list, uint32_t channel, uint32_t i) {
    for (uint32_t b = 0; b < list->mNumberBuffers; ++b) {
        const AudioBuffer *buffer = &list->mBuffers[b];
        if (channel < buffer->mNumberChannels) {
            uint64_t index = (uint64_t)i*buffer->mNumberChannels + channel;
            if (!buffer->mData || (index+1)*sizeof(float) > buffer->mDataByteSize) { return 0; }
            return ((const float *)buffer->mData)[index];
        }
        channel -= buffer->mNumberChannels;
    }
    return 0;
}
static void writeChannel(AudioBufferList *list, uint32_t channel, uint32_t i, float value) {
    for (uint32_t b = 0; b < list->mNumberBuffers; ++b) {
        AudioBuffer *buffer = &list->mBuffers[b];
        if (channel < buffer->mNumberChannels) {
            uint64_t index = (uint64_t)i*buffer->mNumberChannels + channel;
            if (buffer->mData && (index+1)*sizeof(float) <= buffer->mDataByteSize) {
                ((float *)buffer->mData)[index] = value;
            }
            return;
        }
        channel -= buffer->mNumberChannels;
    }
}
OSStatus tb_disable_physical_inputs(AudioObjectID device, AudioDeviceIOProcID proc, uint32_t physicalChannels) {
    if (!physicalChannels) { return noErr; }
    AudioObjectPropertyAddress address = {kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput, kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size);
    if (status != noErr) { return status; }
    AudioStreamID *streams = malloc(size);
    if (!streams) { return kAudioHardwareUnspecifiedError; }
    status = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, streams);
    UInt32 count = size/sizeof(AudioStreamID);
    if (status != noErr || count == 0) { free(streams); return kAudioHardwareUnspecifiedError; }
    UInt32 usageSize = (UInt32)(sizeof(AudioHardwareIOProcStreamUsage)+(count-1)*sizeof(UInt32));
    AudioHardwareIOProcStreamUsage *usage = calloc(1,usageSize);
    if (!usage) { free(streams); return kAudioHardwareUnspecifiedError; }
    usage->mIOProc = (void *)proc; usage->mNumberStreams = count;
    UInt32 channels = 0;
    for (UInt32 i = 0; i < count; ++i) {
        AudioStreamBasicDescription format = {0}; UInt32 formatSize = sizeof(format);
        AudioObjectPropertyAddress f = {kAudioStreamPropertyVirtualFormat,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
        status = AudioObjectGetPropertyData(streams[i],&f,0,NULL,&formatSize,&format);
        if (status != noErr) { break; }
        if (channels < physicalChannels && channels+format.mChannelsPerFrame > physicalChannels) {
            status = kAudioHardwareUnsupportedOperationError; break;
        }
        usage->mStreamIsOn[i] = channels >= physicalChannels;
        channels += format.mChannelsPerFrame;
    }
    if (status == noErr) {
        address.mSelector = kAudioDevicePropertyIOProcStreamUsage;
        status = AudioObjectSetPropertyData(device,&address,0,NULL,usageSize,usage);
    }
    free(usage); free(streams); return status;
}
OSStatus tb_audio_callback(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    TBDSP *d = context;
    if (!d || !input || !output) { return noErr; }
    atomic_fetch_add_explicit(&d->callbacks, 1, memory_order_relaxed);
    uint32_t frames = 0;
    for (uint32_t b = 0; b < output->mNumberBuffers; ++b) {
        AudioBuffer *buffer = &output->mBuffers[b];
        if (buffer->mData && buffer->mNumberChannels) {
            memset(buffer->mData, 0, buffer->mDataByteSize);
            uint32_t count = buffer->mDataByteSize / (sizeof(float)*buffer->mNumberChannels);
            if (!frames || count < frames) { frames = count; }
        }
    }
    beginBlock(d); float peak = 0;
    for (uint32_t i = 0; i < frames; ++i) {
        float left, right;
        frame(d, readChannel(input, d->inputOffset, i), readChannel(input, d->inputOffset+1, i), &left, &right);
        writeChannel(output, 0, i, left); writeChannel(output, 1, i, right);
        peak = fmaxf(peak, fmaxf(fabsf(left), fabsf(right)));
    }
    atomic_store_explicit(&d->peak, peak, memory_order_relaxed);
    return noErr;
}
