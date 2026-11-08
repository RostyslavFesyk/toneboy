// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = EQModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let statusAnimation = StatusAnimation()
    private var hosting: NSHostingController<EQView>!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 40)
        if let button = statusItem.button {
            button.image = StatusAnimation.image(phase: 0, activity: 0, levels: Array(repeating: 0, count: 5))
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "toneboy · System equalizer"
        }
        hosting = NSHostingController(rootView: EQView(model: model))
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 600, height: 335)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index+1 {
            // A real AppKit-rendered preview; no audio is captured in this mode.
            let path = CommandLine.arguments[index+1]
            hosting.view.frame = NSRect(x: 0, y: 0, width: 600, height: 335)
            let window = NSWindow(contentRect: hosting.view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting.view
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now()+0.5) {
                self.hosting.view.layoutSubtreeIfNeeded()
                if let bitmap = self.hosting.view.bitmapImageRepForCachingDisplay(in: self.hosting.view.bounds) {
                    self.hosting.view.cacheDisplay(in: self.hosting.view.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
                }
                NSApplication.shared.terminate(nil)
            }
        } else {
            if let button = statusItem.button { statusAnimation.start(button: button, model: model) }
            DispatchQueue.main.asyncAfter(deadline: .now()+0.3) {
                self.showPopover()
                self.model.start()
            }
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        model.resumeAfterAudioSettings()
    }

    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }
    func showPopover() {
        guard let button = statusItem.button else { return }
        model.panelVisible = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func popoverDidClose(_ notification: Notification) { model.panelVisible = false }
    func applicationWillTerminate(_ notification: Notification) {
        statusAnimation.stop()
        model.stop()
    }
}

@main
enum TonebarApp {
    static func main() {
        let app = NSApplication.shared
        let identifier = Bundle.main.bundleIdentifier ?? "app.tonebar.local"
        let lockURL = FileManager.default.temporaryDirectory.appendingPathComponent(identifier + ".instance.lock")
        guard let instanceLock = SingleInstanceLock(url: lockURL) else {
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .first(where: { $0.processIdentifier != getpid() })?
                .activate(options: [.activateIgnoringOtherApps])
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime((delegate, instanceLock)) { app.run() }
    }
}
