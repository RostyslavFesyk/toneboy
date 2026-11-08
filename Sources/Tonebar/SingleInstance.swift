// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk
import Foundation
import Darwin

/// The kernel releases the lock on exit or crash. Keep the file in place so
/// another process cannot create a second inode while the first lock is held.
final class SingleInstanceLock {
    private let descriptor: Int32
    init?(url: URL) {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        self.descriptor = descriptor
    }
    deinit { close(descriptor) }
}
