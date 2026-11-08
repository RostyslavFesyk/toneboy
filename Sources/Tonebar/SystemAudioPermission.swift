// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import Foundation
import Darwin

/// Direct-distribution build only. TCC SPI is not eligible for Mac App Store submission.
/// ABI reference: insidegui/AudioCap, AudioRecordingPermission.swift.
enum SystemAudioPermission {
    enum Status: Equatable {
        case undetermined, denied, authorized, unavailable
        static func decode(_ result: Int) -> Status {
            switch result {
            case 0: return .authorized
            case 1: return .denied
            case 2: return .undetermined
            default: return .unavailable
            }
        }
    }
    private typealias Check = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void
    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let library = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_LAZY | RTLD_LOCAL)
    private static let check: Check? = {
        guard let library, let symbol = dlsym(library, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: Check.self)
    }()
    private static let request: Request? = {
        guard let library, let symbol = dlsym(library, "TCCAccessRequest") else { return nil }
        return unsafeBitCast(symbol, to: Request.self)
    }()
    static func status() -> Status {
        guard let check else { return .unavailable }
        return Status.decode(check(service, nil))
    }
    static func requestAccess(completion: @escaping (Status) -> Void) {
        guard let request else { completion(.unavailable); return }
        request(service, nil) { allowed in
            DispatchQueue.main.async { completion(allowed ? .authorized : .denied) }
        }
    }
}
