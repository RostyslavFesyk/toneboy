// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk
import Combine
import ServiceManagement

final class LoginItem: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published var error: String?
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let openSettings: () -> Void

    var enabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    init(readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() },
         openSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        self.openSettings = openSettings
        refresh()
    }

    func refresh() { status = readStatus() }

    func setEnabled(_ enabled: Bool) {
        error = nil
        refresh()
        if enabled && needsApproval { openSettings(); return }
        if enabled == self.enabled && !needsApproval { return }
        do {
            if enabled { try register() } else { try unregister() }
            refresh()
            if needsApproval { openSettings() }
            else if enabled && !self.enabled {
                error = "macOS could not enable Launch at Login. Move toneboy to Applications and try again."
            }
        } catch {
            refresh()
            if needsApproval && enabled { openSettings() }
            else { self.error = "Could not update Launch at Login. \(error.localizedDescription)" }
        }
    }

    func showSettings() { openSettings() }
}
