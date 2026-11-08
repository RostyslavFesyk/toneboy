// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk
import XCTest
@testable import CaptureVerification

final class SelfTestSignalTests: XCTestCase {
    let signal = SelfTestSignal(firstFrequency: 1123, secondFrequency: 1877)
    func testAcceptsItsOwnSignalAtSupportedRatesAndDifferentVolume() {
        for rate in [44100.0, 48000, 96000] {
            let samples = Array(signal.samples(rate: rate).dropFirst(2000).prefix(4096))
            XCTAssertTrue(signal.matches(samples, rate: rate))
            XCTAssertTrue(signal.matches(samples.map { $0 * 0.05 }, rate: rate))
        }
    }
    func testRejectsSilenceAndInvalidOrIncompleteSamples() {
        XCTAssertFalse(signal.matches(Array(repeating: 0, count: 8192), rate: 48000))
        XCTAssertFalse(signal.matches(Array(repeating: .nan, count: 8192), rate: 48000))
        XCTAssertFalse(signal.matches([0.1], rate: 48000))
    }
    func testRejectsUnrelatedSoundAndAnotherChallenge() {
        let other = SelfTestSignal(firstFrequency: 933, secondFrequency: 2117)
        XCTAssertFalse(signal.matches(Array(other.samples(rate: 48000).dropFirst(2000).prefix(4096)), rate: 48000))
        let tone = (0..<4096).map { Float(0.1 * sin(2 * Double.pi * 440 * Double($0) / 48000)) }
        XCTAssertFalse(signal.matches(tone, rate: 48000))
    }
    func testChallengeCanBeDetectedUnderLouderOtherAudio() {
        let samples = Array(signal.samples(rate: 48000).dropFirst(2000).prefix(8192))
        var seed: UInt64 = 79
        let background: [Float] = (0..<samples.count).map { index in
            seed = seed &* 6364136223846793005 &+ 1
            let noise = Double(seed >> 32) / Double(UInt32.max) * 2 - 1
            return Float(0.025 * noise + 0.15 * sin(2 * .pi * 110 * Double(index) / 48000))
        }
        XCTAssertFalse(signal.matches(background, rate: 48000))
        XCTAssertTrue(signal.matches(zip(samples, background).map(+), rate: 48000))
    }
    func testSignalIsShortQuietAndFadesAtBothEnds() {
        let samples = signal.samples(rate: 48000)
        XCTAssertEqual(samples.count, 33600)
        XCTAssertLessThanOrEqual(samples.map { abs($0) }.max()!, 0.006)
        XCTAssertEqual(samples[0], 0)
        XCTAssertLessThan(abs(samples.last!), 0.00001)
    }
}
