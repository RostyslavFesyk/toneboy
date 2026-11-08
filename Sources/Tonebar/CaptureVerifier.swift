// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk
import Foundation
import AudioDSP
import CaptureVerification

enum AudioAccessState { case unchecked, checking, verified, needsHelp, failed }

// All calls, timer ticks, and completion delivery happen on the main run loop.
protocol CaptureVerifying: AnyObject {
    func begin(dsp: OpaquePointer?, rate: Double, completion: @escaping (Bool) -> Void)
    func cancel()
}

final class CaptureVerifier: CaptureVerifying {
    private let player = SelfTestPlayer()
    private var timer: Timer?
    private var completion: ((Bool) -> Void)?

    func begin(dsp: OpaquePointer?, rate: Double, completion: @escaping (Bool) -> Void) {
        cancel()
        guard let dsp, rate.isFinite, rate > 0 else { completion(false); return }
        self.completion = completion
        let diagnostics = ProcessInfo.processInfo.environment["TONEBOY_AUDIO_DIAGNOSTICS"] == "1"
        let signal = SelfTestSignal()
        var began = Date()
        var activity = CaptureActivityGate()
        var attempts = 0
        var played: Date?
        var collected: [Float] = []
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            var buffer = [Float](repeating: 0, count: 32768)
            let n = buffer.withUnsafeMutableBufferPointer {
                tb_read_analysis(dsp, $0.baseAddress, UInt32($0.count))
            }
            if diagnostics { print("capture elapsed=\(Date().timeIntervalSince(began)) samples=\(n) callbacks=\(tb_callback_count(dsp)) inputPeak=\(tb_input_peak(dsp)) rate=\(rate)") }
            guard let playback = played else {
                // The player is stopped here. Sustained real capture already proves
                // this route works; music need not compete with our quiet pilot.
                if activity.observe(Array(buffer.prefix(Int(n))), rate: rate) {
                    if diagnostics { print("capture verified from existing audio") }
                    self.finish(true)
                    return
                }
                guard Date().timeIntervalSince(began) >= 0.5 else { return }
                do {
                    try self.player.play(signal, rate: rate)
                    played = Date()
                    attempts += 1
                    if diagnostics { print("pilot started") }
                } catch { if diagnostics { print("pilot failed: \(error)") }; self.finish(false) }
                return
            }
            collected.append(contentsOf: buffer.prefix(Int(n)))
            if collected.count > 8192 { collected.removeFirst(collected.count - 8192) }
            if signal.matches(collected, rate: rate) {
                if diagnostics { print("capture verified from pilot") }
                self.finish(true)
            }
            else if Date().timeIntervalSince(playback) > 2 {
                // One bounded retry handles Bluetooth startup and music beginning
                // while the pilot was playing. Never mute an unverified route.
                self.player.stop()
                if attempts < 2 {
                    played = nil
                    collected.removeAll(keepingCapacity: true)
                    activity = CaptureActivityGate()
                    began = Date()
                } else { self.finish(false) }
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func finish(_ success: Bool) {
        let callback = completion
        cancel() // Stop playback and pointer-consuming timer before engine changes.
        callback?(success)
    }
    func cancel() {
        timer?.invalidate()
        timer = nil
        player.stop()
        completion = nil
    }
    deinit { cancel() }
}
