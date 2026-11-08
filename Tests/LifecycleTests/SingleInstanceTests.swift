// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk
import XCTest
@testable import Tonebar

final class SingleInstanceTests: XCTestCase {
    func testSecondInstanceCannotAcquireHeldLock() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let first = SingleInstanceLock(url: url)
        XCTAssertNotNil(first)
        withExtendedLifetime(first) { XCTAssertNil(SingleInstanceLock(url: url)) }
    }
    func testReleasedLockCanBeAcquiredWithoutDeletingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var first: SingleInstanceLock? = SingleInstanceLock(url: url)
        XCTAssertNotNil(first)
        first = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNotNil(SingleInstanceLock(url: url))
    }
}
