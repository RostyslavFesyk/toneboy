// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import XCTest
@testable import Tonebar

private final class FakeEngine: AudioEngineControlling {
    var dsp: OpaquePointer? { nil }
    var sampleRate = 48000.0
    var outputName = "Test output"
    var starts = 0
    var stops = 0
    var active = false
    var changedRoute = false
    var enables = 0
    var enableFailure = false
    func enableProcessing() throws {
        if enableFailure { throw AudioFailure(message: "Enable failed") }
        enables += 1
    }
    var failures: [AudioFailure] = []
    func start() throws {
        starts += 1
        if !failures.isEmpty { active = false; throw failures.removeFirst() }
        active = true
    }
    func stop() { stops += 1; active = false }
    func routeChanged() -> Bool {
        defer { changedRoute = false }
        return changedRoute
    }
}

private final class VerificationStub: CaptureVerifying {
    var immediate: Bool? = true
    var completion: ((Bool) -> Void)?
    func begin(dsp: OpaquePointer?, rate: Double, completion: @escaping (Bool) -> Void) {
        self.completion = completion
        if let immediate { completion(immediate) }
    }
    // Intentionally retain callback to test stale completions after cancellation.
    func cancel() {}
    func resolve(_ result: Bool) { completion?(result) }
}

@MainActor
final class LifecycleTests: XCTestCase {
    private var engine: FakeEngine!
    private var verification: VerificationStub!
    private var model: EQModel!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        engine = FakeEngine()
        verification = VerificationStub()
        suite = "toneboy.lifecycle-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        model = EQModel(engine: engine, verifier: verification,
                        defaults: defaults, monitorSystem: false)
    }
    override func tearDown() {
        model.stop()
        model = nil
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testVerifiedStartsWithoutMusicAndIgnoresDuplicateStart() {
        model.start()
        model.start()
        XCTAssertTrue(model.running)
        XCTAssertFalse(model.starting)
        XCTAssertEqual(engine.starts, 1)
        XCTAssertEqual(engine.enables, 1)
    }
    func testFailedVerificationNeverMutesAndReturnFromSettingsRetries() {
        verification.immediate = false
        model.start()
        XCTAssertFalse(model.running)
        XCTAssertFalse(engine.active)
        XCTAssertEqual(engine.enables, 0)
        XCTAssertEqual(model.audioAccess, .needsHelp)
        verification.immediate = true
        model.resumeAfterAudioSettings()
        XCTAssertTrue(model.running)
        XCTAssertEqual(engine.starts, 2)
    }
    func testWaitingForVerificationNeverEnablesProcessing() {
        verification.immediate = nil
        model.start()
        model.start()
        XCTAssertTrue(model.starting)
        XCTAssertFalse(model.running)
        XCTAssertEqual(engine.starts, 1)
        XCTAssertEqual(engine.enables, 0)
        verification.resolve(true)
        XCTAssertTrue(model.running)
        XCTAssertEqual(engine.enables, 1)
    }
    func testLateVerificationCannotUndoManualStop() {
        verification.immediate = nil
        model.start()
        model.stop()
        verification.resolve(true)
        model.resumeAfterAudioSettings()
        XCTAssertFalse(model.running)
        XCTAssertEqual(engine.enables, 0)
    }
    func testReturnFromConsentDuringCheckRetriesOnceOnFailure() {
        verification.immediate = nil
        model.start()
        model.resumeAfterAudioSettings()
        verification.resolve(false)
        XCTAssertEqual(engine.starts, 2)
        XCTAssertTrue(model.starting)
        verification.resolve(false)
        XCTAssertEqual(engine.starts, 2)
        XCTAssertFalse(model.starting)
    }
    func testOldCompletionCannotEnableNewRoute() {
        verification.immediate = nil
        model.start()
        let old = verification.completion
        model.stop()
        model.start()
        old?(true)
        XCTAssertFalse(model.running)
        XCTAssertEqual(engine.enables, 0)
        verification.resolve(true)
        XCTAssertTrue(model.running)
    }
    func testManualBypassDoesNotAutoEnableOnFocus() {
        model.start()
        model.stop()
        for _ in 0..<100 { model.resumeAfterAudioSettings() }
        XCTAssertFalse(model.running)
        XCTAssertEqual(engine.starts, 1)
    }
    func testEnableFailureStopsRoute() {
        engine.enableFailure = true
        model.start()
        XCTAssertFalse(engine.active)
        XCTAssertFalse(model.running)
        XCTAssertFalse(model.starting)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.audioAccess, .failed)
    }
    func testFailedVerificationDoesNotRepeatFromAnalysisLoop() {
        verification.immediate = false
        model.start()
        for _ in 0..<300 { model.tick() }
        XCTAssertEqual(engine.starts, 1)
        XCTAssertEqual(engine.enables, 0)
    }
    func testNonTransientFailureDoesNotRetryForever() {
        engine.failures = [AudioFailure(message: "Unsupported output")]
        model.start()
        for _ in 0..<100 { model.resumeAfterAudioSettings() }
        XCTAssertFalse(model.running)
        XCTAssertFalse(model.starting)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(engine.starts, 1)
        model.start()
        XCTAssertTrue(model.running)
        XCTAssertNil(model.error)
    }
    func testTransientFailureRetriesOnceThenStops() async throws {
        engine.failures = Array(repeating: AudioFailure(message: "Timeout", status: AudioFailure.serviceTimeout), count: 3)
        model.start()
        XCTAssertTrue(model.starting)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(engine.starts, 2)
        XCTAssertFalse(model.running)
        XCTAssertFalse(model.starting)
        model.resumeAfterAudioSettings()
        XCTAssertEqual(engine.starts, 2)
    }
    func testStopCancelsPendingRetry() async throws {
        engine.failures = [AudioFailure(message: "Timeout", status: AudioFailure.serviceTimeout)]
        model.start()
        model.stop()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(engine.starts, 1)
        XCTAssertFalse(model.running)
    }
    func testRouteChangeReconnectsAndPreservesEQ() {
        model.applyPreset("Bass")
        let gains = model.bands.map(\.gain)
        model.start()
        engine.changedRoute = true
        for _ in 0..<30 { model.tick() }
        XCTAssertTrue(model.running)
        XCTAssertEqual(engine.starts, 2)
        XCTAssertEqual(engine.stops, 1)
        XCTAssertEqual(model.bands.map(\.gain), gains)
    }
    func testSleepStopsAudioAndWakeRestarts() async throws {
        model.start()
        model.prepareForSleep()
        XCTAssertFalse(engine.active)
        model.resumeFromSleep()
        try await Task.sleep(nanoseconds: 1_250_000_000)
        XCTAssertTrue(model.running)
        XCTAssertEqual(engine.starts, 2)
    }
    func testManualStopCancelsDelayedWake() async throws {
        model.start()
        model.prepareForSleep()
        model.resumeFromSleep()
        model.stop()
        try await Task.sleep(nanoseconds: 1_250_000_000)
        XCTAssertFalse(model.running)
        XCTAssertEqual(engine.starts, 1)
    }
    func testManualStopBeforeWakeCancelsResume() async throws {
        model.start()
        model.prepareForSleep()
        model.stop()
        model.resumeFromSleep()
        try await Task.sleep(nanoseconds: 1_250_000_000)
        XCTAssertFalse(model.running)
        XCTAssertEqual(engine.starts, 1)
    }
    func testBypassedAppStaysOffAfterSleep() async throws {
        model.prepareForSleep()
        model.resumeFromSleep()
        try await Task.sleep(nanoseconds: 1_250_000_000)
        XCTAssertFalse(model.running)
        XCTAssertEqual(engine.starts, 0)
    }
    func testRepeatedToggleDoesNotAccumulateActiveRoutes() {
        for _ in 0..<250 {
            model.toggle()
            XCTAssertTrue(engine.active)
            model.toggle()
            XCTAssertFalse(engine.active)
        }
        XCTAssertEqual(engine.starts, 250)
        XCTAssertEqual(engine.stops, 250)
    }
}
