// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import AppKit
import SwiftUI
import AudioDSP

struct EQBand: Codable, Identifiable {
    var id: Int
    var frequency: Double
    var gain: Double = 0
    var q: Double = 0.8
    var isShelf: Bool { id == 0 || id == 3 }
    var graphGain: Double { isShelf ? gain/2 : gain }
    var color: Color { [.init(red: 1, green: 0.62, blue: 0.34), .init(red: 0.94, green: 0.76, blue: 0.34),
                         .init(red: 0.57, green: 0.81, blue: 0.57), .init(red: 0.36, green: 0.76, blue: 0.81),
                         .init(red: 0.55, green: 0.63, blue: 0.95), .init(red: 0.79, green: 0.55, blue: 0.87)][id % 6] }
    var frequencyText: String { frequency >= 1000 ? String(format: "%.2g kHz", frequency/1000) : String(format: "%.0f Hz", frequency) }
}

final class EQModel: ObservableObject {
    @Published var bands = [80.0, 400, 2500, 10000].enumerated().map { EQBand(id: $0.offset, frequency: $0.element) }
    @Published var selected = 2
    @Published var preset = "Flat"
    @Published var running = false
    @Published private(set) var starting = false
    private var startRetry: DispatchWorkItem?
    @Published private(set) var audioAccess = AudioAccessState.unchecked
    private var wantsAudio = false
    private var retryAfterActivation = false
    private var permissionGeneration = 0
    @Published var bypass = false
    @Published var autoGain = true
    @Published var outputGain = 0.0
    @Published var appliedGain = 0.0
    @Published var spectrum = [Double](repeating: -90, count: 160)
    @Published var peak = 0.0
    @Published var gradientMotion = GradientMotion()
    @Published var error: String?
    @Published var outputName = "System output"
    @Published var sampleRate = 48000.0
    private(set) var statusLevels = [Double](repeating: 0, count: 5)
    var panelVisible = true
    private let engine: AudioEngineControlling
    private let verifier: CaptureVerifying
    private let defaults: UserDefaults
    private let analyzer = SpectrumAnalyzer()
    private var timer: Timer?
    private var samples = [Float](repeating: 0, count: 8192)
    private var ticks = 0
    private var started = Date()
    private var resumeAfterSleep = false
    private var observers: [NSObjectProtocol] = []
    let presets = ["Flat", "Warm", "Bass", "Vocal", "Soft"]

    init(engine: AudioEngineControlling = SystemAudioEngine(),
         verifier: CaptureVerifying = CaptureVerifier(),
         defaults: UserDefaults = .standard,
         monitorSystem: Bool = true) {
        self.engine = engine
        self.verifier = verifier
        self.defaults = defaults
        if let data = defaults.data(forKey: "bands-v2"),
           let saved = try? JSONDecoder().decode([EQBand].self, from: data), saved.count == 4,
           saved.enumerated().allSatisfy({ i, b in b.id == i && (20...20000).contains(b.frequency) && (-18...18).contains(b.gain) && (0.1...12).contains(b.q) }) {
            bands = saved.map { band in
                var b = band
                if b.isShelf { b.q = min(1, b.q) }
                return b
            }
            preset = defaults.string(forKey: "preset") ?? "Custom"
        }
        if defaults.object(forKey: "autoGain") != nil {
            autoGain = defaults.bool(forKey: "autoGain")
            outputGain = min(0, max(-18, defaults.double(forKey: "outputGain")))
        }
        if monitorSystem {
            if let id = try? AudioProperty.defaultOutput(), let name = try? AudioProperty.string(id, kAudioObjectPropertyName) { outputName = name }
            let analysisTimer = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] _ in self?.tick() }
            // Keep consuming audio and updating visuals during AppKit mouse tracking.
            RunLoop.main.add(analysisTimer, forMode: .common)
            timer = analysisTimer
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.prepareForSleep()
            })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.resumeFromSleep()
            })
        }
        push()
    }

    deinit {
        verifier.cancel()
        timer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func prepareForSleep() {
        let shouldResume = running || starting
        stop()
        resumeAfterSleep = shouldResume
    }

    func resumeFromSleep() {
        guard resumeAfterSleep else { return }
        resumeAfterSleep = false
        let generation = permissionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.permissionGeneration == generation else { return }
            self.start()
        }
    }

    func openAudioSettings() {
        wantsAudio = true
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
        if !NSWorkspace.shared.open(url),
           let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open(settings)
        }
    }

    func resumeAfterAudioSettings() {
        // Called on activation, never from the analysis loop: a failed check must
        // not repeatedly play test tones while the user is listening.
        if starting { retryAfterActivation = true }
        else if wantsAudio && !running { start() }
    }

    func start() {
        guard !running, !starting else { return }
        error = nil
        wantsAudio = true
        permissionGeneration += 1
        retryAfterActivation = false
        audioAccess = .checking
        starting = true
        attemptStart(retriesRemaining: 1)
    }

    private func attemptStart(retriesRemaining: Int) {
        guard starting else { return }
        startRetry = nil
        do {
            try engine.start()
            sampleRate = engine.sampleRate
            outputName = engine.outputName
            push()
            let generation = permissionGeneration
            verifier.begin(dsp: engine.dsp, rate: sampleRate) { [weak self] verified in
                guard let self, self.permissionGeneration == generation, self.starting else { return }
                if verified {
                    do {
                        try self.engine.enableProcessing()
                        self.audioAccess = .verified
                        self.started = Date()
                        self.running = true
                        self.starting = false
                    } catch {
                        self.engine.stop()
                        self.starting = false
                        self.wantsAudio = false
                        self.audioAccess = .failed
                        self.error = error.localizedDescription
                    }
                } else {
                    self.engine.stop()
                    self.starting = false
                    self.audioAccess = .needsHelp
                    if self.retryAfterActivation { self.start() }
                }
            }
        } catch {
            // engine.start() has already cleaned up the failed route and tap.
            if let failure = error as? AudioFailure, failure.isTransient, retriesRemaining > 0 {
                let retry = DispatchWorkItem { [weak self] in
                    guard let self, self.starting else { return }
                    self.attemptStart(retriesRemaining: retriesRemaining - 1)
                }
                startRetry = retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: retry)
                return
            }
            self.error = error.localizedDescription
            audioAccess = .failed
            running = false
            starting = false
            // Only permission changes resume automatically; other failures need an explicit retry.
            wantsAudio = false
        }
    }
    func stop() {
        resumeAfterSleep = false
        wantsAudio = false
        retryAfterActivation = false
        permissionGeneration += 1
        startRetry?.cancel()
        startRetry = nil
        starting = false
        verifier.cancel()
        engine.stop()
        audioAccess = .unchecked
        running = false
        peak = 0
        statusLevels = Array(repeating: 0, count: 5)
        spectrum = Array(repeating: -90, count: 160)
    }
    func toggle() { (running || starting) ? stop() : start() }
    func changeBand(_ index: Int, frequency: Double? = nil, gain: Double? = nil, q: Double? = nil) {
        if let frequency { bands[index].frequency = min(20000, max(20, frequency)) }
        if let gain { bands[index].gain = min(18, max(-18, gain)) }
        if let q { bands[index].q = min(bands[index].isShelf ? 1 : 12, max(0.1, q)) }
        preset = "Custom"
        push()
    }
    func applyPreset(_ name: String) {
        let gains: [String: [Double]] = ["Flat": [0,0,0,0], "Warm": [3,0,-1,-2],
            "Bass": [5,-1,0,1], "Vocal": [-2,-1,3,1], "Soft": [1,0,-1,-3]]
        guard let values = gains[name] else { return }
        let frequencies = [80.0,400,2500,10000]
        bands = values.enumerated().map { EQBand(id: $0.offset, frequency: frequencies[$0.offset], gain: $0.element) }
        preset = name
        push()
    }
    func response(at frequency: Double, band: EQBand? = nil) -> Double {
        (band.map { [$0] } ?? bands).reduce(0) { $0 + tb_band_response(Int32($1.id), frequency, $1.frequency, $1.gain, $1.q, sampleRate) }
    }
    func push() {
        let maximum = (0...256).map { response(at: 20*pow(1000, Double($0)/256)) }.max() ?? 0
        appliedGain = min(0, outputGain - (autoGain ? max(0,maximum) : 0))
        appliedGain = max(-24, appliedGain)
        if let dsp = engine.dsp {
            for (i,b) in bands.enumerated() { tb_set_band(dsp, Int32(i), b.frequency, b.gain, b.q) }
            tb_set_output(dsp, appliedGain, bypass)
        }
        if let data = try? JSONEncoder().encode(bands) { defaults.set(data, forKey: "bands-v2") }
        defaults.set(preset, forKey: "preset")
        defaults.set(autoGain, forKey: "autoGain")
        defaults.set(outputGain, forKey: "outputGain")
    }
    func tick() {
        ticks += 1
        var nextMotion = gradientMotion
        nextMotion.follow(statusLevels)
        if abs(nextMotion.energy - gradientMotion.energy)
            + abs(nextMotion.bass - gradientMotion.bass)
            + abs(nextMotion.balance - gradientMotion.balance) > 0.0001 {
            gradientMotion = nextMotion
        }
        guard running else { return }
        if ticks % 30 == 0, engine.routeChanged() {
            stop(); start(); return
        }
        guard let dsp = engine.dsp else { return }
        if Date().timeIntervalSince(started) > 8, tb_callback_count(dsp) == 0 {
            stop()
            error = "No audio callbacks were received. Check your output device and toneboy’s System Audio Recording access in Privacy & Security, then try again."
            return
        }
        let n = samples.withUnsafeMutableBufferPointer { tb_read_analysis(dsp, $0.baseAddress, UInt32($0.count)) }
        // The menu-bar animation also needs level updates while the popover is closed.
        peak = Double(tb_peak(dsp))
        let analyzed = analyzer.update(samples, count: Int(n), rate: sampleRate)
        statusLevels = analyzer.statusLevels
        if panelVisible { spectrum = analyzed }
    }
}
