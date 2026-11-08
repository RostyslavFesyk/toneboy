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

private final class PermissionStub {
    var status: SystemAudioPermission.Status = .authorized
    var requests = 0
    var completion: ((SystemAudioPermission.Status) -> Void)?
    func request(_ completion: @escaping (SystemAudioPermission.Status) -> Void) {
        requests += 1
        self.completion = completion
    }
    func resolve(_ result: SystemAudioPermission.Status) {
        status = result
        let callback = completion
        completion = nil
        callback?(result)
    }
}

@MainActor
final class LifecycleTests: XCTestCase {
    private var engine: FakeEngine!
    private var permission: PermissionStub!
    private var model: EQModel!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        engine = FakeEngine()
        permission = PermissionStub()
        suite = "toneboy.lifecycle-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        model = EQModel(engine: engine, permissionStatus: { [permission] in permission!.status },
                        requestPermission: { [permission] in permission!.request($0) },
                        defaults: defaults, monitorSystem: false)
    }
    override func tearDown() {
        model.stop()
        model = nil
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAuthorizedStartsWithoutPlayingMusicAndIgnoresDuplicateStart() {
        model.start()
        model.start()
        XCTAssertTrue(model.running)
        XCTAssertFalse(model.starting)
        XCTAssertTrue(engine.active)
        XCTAssertEqual(engine.starts, 1)
        XCTAssertEqual(permission.requests, 0)
    }
    func testDeniedNeverStartsMutingEngineAndGrantResumesAutomatically() {
        permission.status = .denied
        model.start()
        for _ in 0..<100 { model.resumeAfterAudioSettings() }
        XCTAssertFalse(model.running)
        XCTAssertEqual(engine.starts, 0)
        XCTAssertEqual(permission.requests, 0)
        permission.status = .authorized
        model.resumeAfterAudioSettings()
        XCTAssertTrue(model.running)
        XCTAssertEqual(engine.starts, 1)
    }
    func testFirstUseWaitsForConsentThenStarts() {
        permission.status = .undetermined
        model.start()
        model.start()
        XCTAssertTrue(model.starting)
        XCTAssertFalse(model.running)
        XCTAssertEqual(engine.starts, 0)
        XCTAssertEqual(permission.requests, 1)
        permission.resolve(.authorized)
        XCTAssertTrue(model.running)
        XCTAssertEqual(engine.starts, 1)
    }
    func testDeclinedRequestLeavesEngineStopped() {
        permission.status = .undetermined
        model.start()
        permission.resolve(.denied)
        XCTAssertFalse(model.running)
        XCTAssertFalse(model.starting)
        XCTAssertEqual(model.audioAccess, .denied)
        XCTAssertEqual(engine.starts, 0)
    }
    func testLateConsentCannotUndoManualStop() {
        permission.status = .undetermined
        model.start()
        model.stop()
        permission.resolve(.authorized)
        model.resumeAfterAudioSettings()
        XCTAssertFalse(model.running)
        XCTAssertEqual(engine.starts, 0)
    }
    func testRevocationStopsRouteAndRegrantRestarts() {
        model.start()
        permission.status = .denied
        model.resumeAfterAudioSettings()
        XCTAssertFalse(model.running)
        XCTAssertFalse(engine.active)
        XCTAssertEqual(engine.stops, 1)
        permission.status = .authorized
        model.resumeAfterAudioSettings()
        XCTAssertTrue(model.running)
        XCTAssertEqual(engine.starts, 2)
    }
    func testManualBypassDoesNotAutoEnableOnFocus() {
        model.start()
        model.stop()
        for _ in 0..<100 { model.resumeAfterAudioSettings() }
        XCTAssertFalse(model.running)
        XCTAssertEqual(engine.starts, 1)
    }
    func testUnavailablePermissionFailsClosed() {
        permission.status = .unavailable
        model.start()
        XCTAssertFalse(model.running)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(engine.starts, 0)
        for value in [-1, 3, 255, Int.max] {
            XCTAssertEqual(SystemAudioPermission.Status.decode(value), .unavailable)
        }
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
