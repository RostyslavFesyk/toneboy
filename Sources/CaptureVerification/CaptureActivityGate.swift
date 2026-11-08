// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk
import Foundation

/// Functional capture evidence while our own test player is stopped.
/// Silence, DC offsets, invalid data and isolated short spikes are not enough.
public struct CaptureActivityGate {
    private var activeDuration = 0.0
    public init() {}

    public mutating func observe(_ samples: [Float], rate: Double) -> Bool {
        guard rate.isFinite, rate > 0, !samples.isEmpty,
              samples.allSatisfy({ $0.isFinite }) else {
            activeDuration = 0
            return false
        }
        let count = Double(samples.count)
        let mean = samples.reduce(0.0) { $0 + Double($1) } / count
        let variance = samples.reduce(0.0) {
            let centered = Double($1) - mean
            return $0 + centered * centered
        } / count
        // At least 80 ms of varying audio above -80 dBFS RMS, before the pilot.
        let activeSamples = samples.reduce(0) { total, sample in
            total + ((abs(sample) > 0.0001 && abs(Double(sample) - mean) > 0.0001) ? 1 : 0)
        }
        if variance > 1e-8 && Double(activeSamples) / count > 0.5 {
            activeDuration += Double(activeSamples) / rate
        }
        else { activeDuration = 0 }
        return activeDuration >= 0.08
    }
}
