// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import Foundation
import AVFoundation

struct SelfTestSignal {
    let firstFrequency: Double
    let secondFrequency: Double
    init(firstFrequency: Double = Double.random(in: 900...1300),
         secondFrequency: Double = Double.random(in: 1700...2200)) {
        self.firstFrequency = firstFrequency
        self.secondFrequency = secondFrequency
    }
    func samples(rate: Double, duration: Double = 0.7) -> [Float] {
        (0..<Int(rate * duration)).map { index in
            let time = Double(index) / rate
            let envelope = max(0, min(1, min(time / 0.025, (duration - time) / 0.025)))
            return Float(0.003 * envelope * (sin(2 * .pi * firstFrequency * time)
                + sin(2 * .pi * secondFrequency * time)))
        }
    }
    func matches(_ samples: [Float], rate: Double) -> Bool {
        guard samples.count >= 2048, rate > 0, samples.allSatisfy({ $0.isFinite }) else { return false }
        let count = Double(samples.count)
        let energy = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        guard energy / count > 1e-10 else { return false }
        func fraction(_ frequency: Double) -> Double {
            var real = 0.0, imaginary = 0.0
            for (index, value) in samples.enumerated() {
                let phase = 2 * Double.pi * frequency * Double(index) / rate
                real += Double(value) * cos(phase)
                imaginary += Double(value) * sin(phase)
            }
            return 2 * (real * real + imaginary * imaginary) / (count * energy)
        }
        let first = fraction(firstFrequency), second = fraction(secondFrequency)
        return first > 0.15 && second > 0.15 && first + second > 0.65
    }
}

final class SelfTestPlayer {
    private let audio = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    func play(_ signal: SelfTestSignal, rate: Double) throws {
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
    func stop() { player.stop(); audio.stop() }
    deinit { stop() }
}
