// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk
import XCTest
@testable import CaptureVerification

final class CaptureActivityGateTests: XCTestCase {
    func testLoudAudioThatMasksPilotStillProvesFunctionalCapture() {
        let rate = 48000.0
        let music = (0..<4800).map { Float(0.7 * sin(2 * .pi * 110 * Double($0) / rate)) }
        var gate = CaptureActivityGate()
        XCTAssertTrue(gate.observe(music, rate: rate))
    }
    func testDeniedZeroSamplesAndDCNeverVerify() {
        var gate = CaptureActivityGate()
        for _ in 0..<100 {
            XCTAssertFalse(gate.observe(Array(repeating: 0, count: 4800), rate: 48000))
            XCTAssertFalse(gate.observe(Array(repeating: 0.5, count: 4800), rate: 48000))
        }
    }
    func testShortTransientDoesNotVerifyAndSilenceResetsAccumulation() {
        var gate = CaptureActivityGate()
        var spike = [Float](repeating: 0, count: 4800)
        spike[2400] = 1
        XCTAssertFalse(gate.observe(spike, rate: 48000))
        let burst: [Float] = (0..<960).map { $0.isMultiple(of: 2) ? 0.1 : -0.1 }
        XCTAssertFalse(gate.observe(burst, rate: 48000))
        XCTAssertFalse(gate.observe(burst, rate: 48000))
        XCTAssertFalse(gate.observe(Array(repeating: 0, count: 4800), rate: 48000))
        XCTAssertFalse(gate.observe(burst, rate: 48000))
    }
    func testInvalidDataFailsClosed() {
        var gate = CaptureActivityGate()
        XCTAssertFalse(gate.observe(Array(repeating: .nan, count: 4800), rate: 48000))
        XCTAssertFalse(gate.observe([0.5, -0.5], rate: .nan))
        XCTAssertFalse(gate.observe([], rate: 48000))
    }
}
