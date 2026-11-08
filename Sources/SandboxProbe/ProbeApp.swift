// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import AppKit
import SwiftUI
import AudioDSP

final class ProbeModel: ObservableObject {
    @Published private(set) var phase = "Stopped"
    @Published private(set) var detail = "Public Core Audio API • App Sandbox • No private permission checks"
    @Published private(set) var callbacks: UInt64 = 0
    @Published private(set) var inputPeak: Float = 0
    @Published private(set) var canProcess = false
    @Published private(set) var processing = false
    @Published private(set) var captureActive = false
    @Published private(set) var bassCut = false
    private let engine = SystemAudioEngine()
    private let selfTestPlayer = SelfTestPlayer()
    private var challenge = SelfTestSignal()
    private var challengeStarted: Date?
    private var verificationSamples: [Float] = []
    private var verified = false
    private var verificationFailed = false
    private var timer: Timer?
    private var lastSignal = Date.distantPast
    private var started = Date()
    private var lastCallback = Date()
    private var ticks = 0
    private var returnFromSettings = false
    private var observations: [NSObjectProtocol] = []
    private(set) var reportURL: URL

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("toneboy-sandbox-probe", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        reportURL = folder.appendingPathComponent("report.json")
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.stop("Stopped for sleep. Restart capture after wake to verify the route again.")
            })
        writeReport()
    }
    deinit {
        timer?.invalidate()
        for observation in observations { NSWorkspace.shared.notificationCenter.removeObserver(observation) }
    }
    func start() {
        selfTestPlayer.stop()
        challenge = SelfTestSignal(); challengeStarted = nil
        verificationSamples = []; verified = false; verificationFailed = false
        engine.stop()
        processing = false; canProcess = false; captureActive = false
        inputPeak = 0; callbacks = 0; lastSignal = .distantPast
        phase = "Starting capture"
        do {
            try engine.start(includeOwnAudio: true)
            started = Date(); lastCallback = started
            captureActive = true
            phase = "Checking audio access"
            detail = "Allow the macOS request. toneboy will play a short, quiet verification sound automatically."
        } catch {
            phase = "Capture failed"
            detail = error.localizedDescription
        }
        writeReport()
    }
    func enableEQ() {
        guard captureActive, verified else { return }
        do {
            try engine.enableProcessing()
            processing = true; phase = "Processing"
            detail = "Sandboxed EQ is routing audio. Compare Flat with Bass cut. Stop restores the original route."
        } catch {
            captureActive = false; canProcess = false
            phase = "Processing failed"; detail = error.localizedDescription
        }
        writeReport()
    }
    func toggleBass() {
        guard processing, let dsp = engine.dsp else { return }
        bassCut.toggle()
        tb_set_band(dsp, 0, 250, bassCut ? -12 : 0, 0.8)
        writeReport()
    }
    func stop(_ reason: String = "Original playback restored.") {
        selfTestPlayer.stop()
        engine.stop()
        verified = false; challengeStarted = nil
        captureActive = false; processing = false; canProcess = false; bassCut = false
        inputPeak = 0; phase = "Stopped"; detail = reason
        writeReport()
    }
    func openSettings() {
        returnFromSettings = true
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
    }
    func becameActive() {
        guard returnFromSettings else { return }
        returnFromSettings = false
        start()
    }
    private func tick() {
        guard captureActive, let dsp = engine.dsp else { return }
        let count = tb_callback_count(dsp)
        if count != callbacks { lastCallback = Date() }
        callbacks = count
        inputPeak = tb_input_peak(dsp)
        if inputPeak > 0.00001 { lastSignal = Date() }
        if !verified && !verificationFailed {
            if challengeStarted == nil, NSApp.isActive, Date().timeIntervalSince(started) > 0.5 {
                // Discard earlier audio: only the fresh randomized challenge can verify capture.
                var discarded = [Float](repeating: 0, count: 32768)
                _ = tb_read_analysis(dsp, &discarded, UInt32(discarded.count))
                do {
                    try selfTestPlayer.play(challenge, rate: engine.sampleRate)
                    challengeStarted = Date()
                } catch {
                    stop("Could not play the verification sound. Check the output device and retry.")
                    return
                }
            }
            if let challengeStarted {
                var fresh = [Float](repeating: 0, count: 8192)
                let count = tb_read_analysis(dsp, &fresh, UInt32(fresh.count))
                verificationSamples.append(contentsOf: fresh.prefix(Int(count)))
                if verificationSamples.count > 8192 { verificationSamples.removeFirst(verificationSamples.count - 8192) }
                if challenge.matches(verificationSamples, rate: engine.sampleRate) {
                    selfTestPlayer.stop()
                    verified = true; canProcess = true
                    phase = "Audio access verified"
                    detail = "The app captured its own verification sound through the system tap. Starting EQ automatically."
                    enableEQ()
                    return
                }
                if Date().timeIntervalSince(challengeStarted) > 2 {
                    selfTestPlayer.stop()
                    verificationFailed = true
                    engine.stop(); captureActive = false; canProcess = false
                    phase = "Audio access could not be verified"
                    detail = "Enable system audio access in Settings, then retry. A muted or unsupported output can also prevent verification."
                    writeReport()
                    return
                }
            }
        }
        if engine.routeChanged() {
            stop("Output changed. Restart capture to verify the new route.")
            return
        }
        if Date().timeIntervalSince(lastCallback) > 5 {
            stop("No callbacks for five seconds. The route was stopped; retry capture or check access.")
            return
        }
        // After the challenge succeeds, ordinary silence must not stop the EQ.
        // Revocation handling after activation remains a separate experiment.
        ticks += 1
        if ticks % 10 == 0 { writeReport() }
    }
    private func writeReport() {
        let report: [String: Any] = [
            "phase": phase, "detail": detail, "callbacks": callbacks,
            "inputPeak": inputPeak, "processing": processing, "bassCut": bassCut, "selfTestVerified": verified,
            "output": engine.outputName, "sampleRate": engine.sampleRate,
            "bundleID": Bundle.main.bundleIdentifier ?? "unbundled",
            "containerHome": NSHomeDirectory(), "pid": ProcessInfo.processInfo.processIdentifier,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: reportURL, options: .atomic)
        }
    }
}

struct ProbeView: View {
    @ObservedObject var model: ProbeModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("toneboy · Sandbox probe").font(.title2.bold())
            Text(model.phase).font(.headline)
            Text(model.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Callbacks: \(model.callbacks)")
                Text(String(format: "Input peak: %.6f", model.inputPeak))
            }.font(.system(.body, design: .monospaced))
            HStack {
                Button(model.captureActive ? "Retry capture" : "Start capture") { model.start() }
                Button("Enable EQ test") { model.enableEQ() }.disabled(!model.canProcess || model.processing)
                Button(model.bassCut ? "Flat" : "Bass cut −12 dB") { model.toggleBass() }.disabled(!model.processing)
                Button("Stop") { model.stop() }.disabled(!model.captureActive)
            }
            HStack {
                Button("Open System Settings") { model.openSettings() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            Text("One app, no driver: a short quiet sound verifies capture. After success EQ starts automatically, including during silence. This remains an experimental permission flow.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 650)
    }
}

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    let model = ProbeModel()
    private var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 698, height: 350),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "toneboy Sandbox Probe"
        window.contentViewController = NSHostingController(rootView: ProbeView(model: model))
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--start-capture") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.model.start() }
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) { model.becameActive() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
}

@main enum SandboxProbeApp {
    static func main() {
        let delegate = ProbeDelegate()
        NSApplication.shared.delegate = delegate
        withExtendedLifetime(delegate) { NSApplication.shared.run() }
    }
}
