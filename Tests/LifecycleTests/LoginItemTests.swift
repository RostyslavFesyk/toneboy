// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk
import XCTest
import ServiceManagement
@testable import Tonebar

final class LoginItemTests: XCTestCase {
    func testRegistrationAndRemovalReflectSystemState() {
        var state = SMAppService.Status.notRegistered
        var registrations = 0
        let item = LoginItem(readStatus: { state }, register: { registrations += 1; state = .enabled },
                             unregister: { state = .notRegistered }, openSettings: {})
        XCTAssertFalse(item.enabled)
        item.setEnabled(true)
        item.setEnabled(true)
        XCTAssertTrue(item.enabled)
        XCTAssertEqual(registrations, 1)
        item.setEnabled(false)
        XCTAssertFalse(item.enabled)
    }
    func testApprovalNeverAppearsEnabledAndDoesNotRegisterAgain() {
        var state = SMAppService.Status.notRegistered
        var registrations = 0
        var settingsOpened = 0
        let item = LoginItem(readStatus: { state }, register: { registrations += 1; state = .requiresApproval },
                             unregister: {}, openSettings: { settingsOpened += 1 })
        item.setEnabled(true)
        XCTAssertFalse(item.enabled)
        XCTAssertTrue(item.needsApproval)
        item.setEnabled(true)
        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(settingsOpened, 2)
        state = .enabled
        item.refresh()
        XCTAssertTrue(item.enabled)
        state = .requiresApproval
        item.refresh()
        XCTAssertFalse(item.enabled)
    }
    func testFailureDoesNotInventEnabledState() {
        let item = LoginItem(readStatus: { .notRegistered },
                             register: { throw NSError(domain: "test", code: 1) },
                             unregister: {}, openSettings: {})
        item.setEnabled(true)
        XCTAssertFalse(item.enabled)
        XCTAssertNotNil(item.error)
    }
    func testFailedRemovalKeepsActualEnabledState() {
        let item = LoginItem(readStatus: { .enabled }, register: {},
                             unregister: { throw NSError(domain: "test", code: 2) }, openSettings: {})
        item.setEnabled(false)
        XCTAssertTrue(item.enabled)
        XCTAssertNotNil(item.error)
    }
}
