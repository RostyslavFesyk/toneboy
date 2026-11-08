// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import Foundation
import AVFoundation

public struct SelfTestSignal {
    let firstFrequency: Double
    let secondFrequency: Double
    public init(firstFrequency: Double = Double.random(in: 900...1300),
         secondFrequency: Double = Double.random(in: 1700...2200)) {
        self.firstFrequency = firstFrequency
        self.secondFrequency = secondFrequency
    }
    public func samples(rate: Double, duration: Double = 0.7) -> [Float] {
        (0..<Int(rate * duration)).map { index in
            let time = Double(index) / rate
            let envelope = max(0, min(1, min(time / 0.025, (duration - time) / 0.025)))
            return Float(0.003 * envelope * (sin(2 * .pi * firstFrequency * time)
                + sin(2 * .pi * secondFrequency * time)))
        }
    }
    public func matches(_ samples: [Float], rate: Double) -> Bool {
        guard samples.count >= 2048, rate > 0, samples.allSatisfy({ $0.isFinite }) else { return false }
        // Windowed coherent detection isolates the random challenge from music.
        // Require both tones to stand above nearby spectrum, not the whole mix.
        let count = Double(samples.count)
        let windowed = samples.enumerated().map { index, value in
            Double(value) * (0.5 - 0.5 * cos(2 * .pi * Double(index) / (count - 1)))
        }
        func power(_ frequency: Double) -> Double {
            var real = 0.0, imaginary = 0.0
            for (index, value) in windowed.enumerated() {
                let phase = 2 * Double.pi * frequency * Double(index) / rate
                real += value * cos(phase)
                imaginary += value * sin(phase)
            }
            return 16 * (real * real + imaginary * imaginary) / (count * count)
        }
        func detected(_ frequency: Double) -> Bool {
            let signalPower = power(frequency)
            let spacing = rate / count
            let background = [-6.0, -4.0, 4.0, 6.0].reduce(0.0) {
                $0 + power(frequency + $1 * spacing)
            } / 4
            return signalPower > 1e-8 && signalPower > background * 12
        }
        return detected(firstFrequency) && detected(secondFrequency)
    }
}

public final class SelfTestPlayer {
    public init() {}
    private let audio = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    public func play(_ signal: SelfTestSignal, rate: Double) throws {
        stop()
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let values = signal.samples(rate: rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(values.count))!
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            values.withUnsafeBufferPointer { source in
                buffer.floatChannelData![channel].update(from: source.baseAddress!, count: values.count)
            }
        }
        if player.engine == nil { audio.attach(player) }
        audio.connect(player, to: audio.mainMixerNode, format: format)
        try audio.start()
        player.scheduleBuffer(buffer)
        player.play()
    }
    public func stop() { player.stop(); audio.stop() }
    deinit { stop() }
}
