// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import XCTest
import AudioDSP

final class AudioDSPTests: XCTestCase {
    func render(_ dsp: OpaquePointer, _ input: [Float], right: [Float]? = nil) -> ([Float], [Float]) {
        var leftOutput = [Float](repeating: 0, count: input.count)
        var rightOutput = leftOutput
        input.withUnsafeBufferPointer { l in
            (right ?? input).withUnsafeBufferPointer { r in
                leftOutput.withUnsafeMutableBufferPointer { ol in
                    rightOutput.withUnsafeMutableBufferPointer { or in
                        tb_process(dsp, l.baseAddress, r.baseAddress, ol.baseAddress, or.baseAddress, UInt32(input.count))
                    }
                }
            }
        }
        return (leftOutput, rightOutput)
    }
    func sine(frequency: Double, rate: Double = 48000, amplitude: Double = 0.05, count: Int = 48000) -> [Float] {
        (0..<count).map { Float(amplitude*sin(2 * .pi * frequency * Double($0)/rate)) }
    }
    func rms(_ values: ArraySlice<Float>) -> Double {
        sqrt(values.reduce(0) { $0 + Double($1*$1) } / Double(values.count))
    }
    func testFlatIsTransparentAndChannelsRemainIndependent() {
        let d = tb_create(48000)!
        defer { tb_destroy(d) }
        let input = sine(frequency: 1000)
        let output = render(d, input, right: Array(repeating: 0, count: input.count))
        XCTAssertLessThan(zip(input,output.0).map { abs($0-$1) }.max()!, 1e-6)
        XCTAssertEqual(output.1.max(), 0)
    }
    func testBellGainMatchesAtCenterAcrossSampleRates() {
        for rate in [44100.0,48000,96000] {
            let d = tb_create(rate)!
            defer { tb_destroy(d) }
            tb_set_band(d, 2, 1000, 6, 1)
            let input = sine(frequency: 1000,rate: rate)
            let output = render(d,input).0
            let measuredDB = 20*log10(rms(output.suffix(20000))/rms(input.suffix(20000)))
            XCTAssertEqual(measuredDB, 6, accuracy: 0.03)
            XCTAssertEqual(tb_response(1000,1000,6,1,rate), 6, accuracy: 0.00001)
        }
    }
    func testCutAndOutputHeadroom() {
        let d = tb_create(48000)!
        defer { tb_destroy(d) }
        tb_set_band(d, 2, 1000, -9, 2)
        tb_set_output(d,-3,false)
        let input = sine(frequency: 1000)
        let output = render(d,input).0
        XCTAssertEqual(20*log10(rms(output.suffix(20000))/rms(input.suffix(20000))), -12, accuracy: 0.03)
    }
    func testBypassRestoresOriginalAfterCrossfade() {
        let d = tb_create(48000)!
        defer { tb_destroy(d) }
        tb_set_band(d, 2, 1000, 12, 1)
        tb_set_output(d,-12,true)
        let input = sine(frequency: 1000)
        let output = render(d,input).0
        XCTAssertLessThan(zip(input.suffix(10000),output.suffix(10000)).map { abs($0-$1) }.max()!, 1e-6)
    }
    func testLimiterAndExtremeSettingsRemainFinite() {
        let d = tb_create(48000)!
        defer { tb_destroy(d) }
        for i in 0..<Int(TB_BANDS) { tb_set_band(d,Int32(i),1000,18,12) }
        let output = render(d,sine(frequency: 1000,amplitude: 0.9)).0
        XCTAssertTrue(output.allSatisfy { $0.isFinite && abs($0) <= 0.98001 })
        tb_set_band(d,2,.nan,18,1)
        let silence = render(d,Array(repeating: 0,count: 100000)).0
        XCTAssertTrue(silence.allSatisfy(\.isFinite))
        XCTAssertLessThan(abs(silence.last!), 0.0001)
    }
    func testShelfPlateausMidpointAndMeasuredResponse() {
        for rate in [44100.0, 48000, 96000] {
            for band: Int32 in [0, 3] {
                for gain in [-9.0, 6.0] {
                    let center = 1000.0
                    let low = tb_band_response(band, 0, center, gain, 0.8, rate)
                    let high = tb_band_response(band, rate/2, center, gain, 0.8, rate)
                    XCTAssertEqual(low, band == 0 ? gain : 0, accuracy: 0.0001)
                    XCTAssertEqual(high, band == 3 ? gain : 0, accuracy: 0.0001)
                    XCTAssertEqual(tb_band_response(band, center, center, gain, 0.8, rate), gain/2, accuracy: 0.0001)
                    for frequency in [100.0, 1000, 10000] {
                        let d = tb_create(rate)!
                        tb_set_band(d, band, center, gain, 0.8)
                        let input = sine(frequency: frequency, rate: rate)
                        let output = render(d,input).0
                        let actual = 20*log10(rms(output.suffix(20000))/rms(input.suffix(20000)))
                        XCTAssertEqual(actual, tb_band_response(band,frequency,center,gain,0.8,rate), accuracy: 0.04)
                        tb_destroy(d)
                    }
                }
            }
        }
    }
    func testAnalyzerQueueIsBoundedAndDrains() {
        let d = tb_create(48000)!
        defer { tb_destroy(d) }
        _ = render(d,sine(frequency: 440))
        var samples = [Float](repeating: 0,count: 2048)
        XCTAssertEqual(tb_read_analysis(d,&samples,2048), 2048)
        XCTAssertTrue(samples.contains { abs($0) > 0.001 })
        XCTAssertEqual(tb_read_analysis(d,&samples,2048), 0)
    }
}
