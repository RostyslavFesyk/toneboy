// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import Accelerate
import Foundation

final class SpectrumAnalyzer {
    // A longer window resolves bass detail; the separate short window keeps the
    // menu icon and reactive background responsive to transients.
    private let detailed = SpectrumWindow(count: 8192)
    private let responsive = SpectrumWindow(count: 2048)
    private let menuMeter = MenuSpectrumMeter()
    private(set) var statusLevels = [Double](repeating: 0, count: 5)
    private var smoothed = [Double](repeating: -90, count: 160)

    func update(_ samples: [Float], count received: Int, rate: Double) -> [Double] {
        statusLevels = menuMeter.update(responsive.update(samples, count: received, rate: rate))
        let raw = detailed.update(samples, count: received, rate: rate)
        for i in smoothed.indices {
            let smoothing = raw[i] > smoothed[i] ? 0.65 : 0.12
            smoothed[i] += smoothing * (raw[i] - smoothed[i])
        }
        return smoothed
    }
}

private final class SpectrumWindow {
    private let count: Int
    private let setup: vDSP_DFT_Setup
    private var history: [Float]
    private var window: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var outReal: [Float]
    private var outImaginary: [Float]
    private var previousRate = 0.0

    init(count: Int) {
        self.count = count
        history = Array(repeating: 0, count: count)
        window = history; real = history; imaginary = history
        outReal = history; outImaginary = history
        setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(count), .FORWARD)!
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
    }
    deinit { vDSP_DFT_DestroySetup(setup) }

    func update(_ samples: [Float], count received: Int, rate: Double) -> [Double] {
        if previousRate != rate {
            history = Array(repeating: 0, count: count)
            previousRate = rate
        }
        let received = min(samples.count, max(0, received))
        if received >= count {
            history = Array(samples[(received-count)..<received])
        } else if received > 0 {
            history.removeFirst(received)
            history.append(contentsOf: samples.prefix(received))
        } else {
            for i in history.indices { history[i] *= 0.65 }
        }
        vDSP_vmul(history, 1, window, 1, &real, 1, vDSP_Length(count))
        vDSP_DFT_Execute(setup, real, imaginary, &outReal, &outImaginary)
        let magnitudes = (0..<count/2).map { bin in
            max(-90, Double(20 * log10(max(0.00001,
                hypot(outReal[bin], outImaginary[bin]) * 4 / Float(count)))))
        }
        func interpolated(_ position: Double) -> Double {
            let position = min(Double(magnitudes.count - 1), max(1, position))
            let lower = Int(position)
            let upper = min(magnitudes.count - 1, lower + 1)
            let fraction = position - Double(lower)
            return magnitudes[lower] + (magnitudes[upper] - magnitudes[lower]) * fraction
        }
        return (0..<160).map { bucket in
            let low = 20 * pow(1000, Double(bucket) / 160) / rate * Double(count)
            let high = 20 * pow(1000, Double(bucket + 1) / 160) / rate * Double(count)
            // Narrow bass buckets sample between FFT bins instead of repeating
            // the same rounded bin across multiple screen positions.
            if high - low < 1 { return interpolated(sqrt(low * high)) }
            var db = max(interpolated(low), interpolated(high))
            let start = max(1, Int(ceil(low)))
            let end = min(magnitudes.count - 1, Int(floor(high)))
            if start <= end {
                for bin in start...end { db = max(db, magnitudes[bin]) }
            }
            return db
        }
    }
}

/// Fast visual envelope relative to a slow musical reference, independent of graph smoothing.
final class MenuSpectrumMeter {
    private var reference = [Double](repeating: -40, count: 5)
    private var levels = [Double](repeating: 0, count: 5)
    private var initialized = false

    func update(_ spectrum: [Double]) -> [Double] {
        let boundaries = [20.0, 200, 600, 1800, 5000, 20001]
        var peaks = [Double](repeating: -90, count: 5)
        for (i, db) in spectrum.enumerated() {
            let hz = 20 * pow(1000, (Double(i) + 0.5) / Double(spectrum.count))
            if let band = (0..<5).first(where: { hz >= boundaries[$0] && hz < boundaries[$0 + 1] }) {
                peaks[band] = max(peaks[band], db)
            }
        }
        let loudest = peaks.max() ?? -90
        if !initialized && loudest > -65 {
            reference = peaks.map { max($0, loudest - 18) }
            initialized = true
        }
        for i in levels.indices {
            // Freeze the reference through pauses; don't amplify silence or noise.
            if peaks[i] > -65 {
                reference[i] += (peaks[i] - reference[i]) * 0.012
            }
            let baseline = max(-55, max(reference[i], (reference.max() ?? -40) - 18))
            let relative = min(1, max(0, (peaks[i] - baseline + 12) / 24))
            let gate = min(1, max(0, (peaks[i] + 65) / 12))
            let target = pow(relative, 1.5) * gate
            levels[i] += (target - levels[i]) * (target > levels[i] ? 0.92 : 0.48)
        }
        return levels
    }
}
