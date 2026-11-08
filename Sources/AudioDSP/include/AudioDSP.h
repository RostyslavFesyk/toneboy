// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

#ifndef AUDIO_DSP_H
#define AUDIO_DSP_H
#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stdint.h>
#define TB_BANDS 4
typedef struct TBDSP TBDSP;
TBDSP *tb_create(double sampleRate);
void tb_set_render_output(TBDSP *dsp, bool enabled);
float tb_input_peak(TBDSP *dsp);
void tb_destroy(TBDSP *dsp);
void tb_set_band(TBDSP *dsp, int band, double frequency, double gainDB, double q);
void tb_set_output(TBDSP *dsp, double gainDB, bool bypass);
void tb_set_input_offset(TBDSP *dsp, uint32_t channels);
void tb_process(TBDSP *dsp, const float *left, const float *right, float *outLeft, float *outRight, uint32_t frames);
uint32_t tb_read_analysis(TBDSP *dsp, float *samples, uint32_t capacity);
float tb_peak(TBDSP *dsp);
uint64_t tb_callback_count(TBDSP *dsp);
OSStatus tb_disable_physical_inputs(AudioObjectID device, AudioDeviceIOProcID proc, uint32_t physicalChannels);
double tb_band_response(int band, double frequency, double center, double gainDB, double q, double sampleRate);
double tb_response(double frequency, double center, double gainDB, double q, double sampleRate);
OSStatus tb_audio_callback(AudioObjectID device, const AudioTimeStamp * _Nonnull now,
    const AudioBufferList * _Nonnull input, const AudioTimeStamp * _Nonnull inputTime,
    AudioBufferList * _Nonnull output, const AudioTimeStamp * _Nonnull outputTime, void * _Nullable context);
#endif
