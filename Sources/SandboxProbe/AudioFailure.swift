// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import Foundation
import CoreAudio

struct AudioFailure: LocalizedError {
    // MACH_RCV_TIMED_OUT from the macOS SDK: the service reply timed out.
    static let serviceTimeout: OSStatus = 0x10004003
    let message: String
    var status: OSStatus? = nil
    var isTransient: Bool {
        status == Self.serviceTimeout || status == kAudioHardwareNotReadyError
    }
    var errorDescription: String? {
        guard let status else { return message }
        if status == Self.serviceTimeout {
            return "The macOS audio service did not respond in time. Try turning the equalizer on again. If this keeps happening, restart toneboy. (Core Audio \(status))"
        }
        if status == kAudioHardwareNotReadyError {
            return "The audio device is not ready. Check your output device and try again. (Core Audio \(status))"
        }
        return "\(message). (Core Audio \(status))"
    }
}
