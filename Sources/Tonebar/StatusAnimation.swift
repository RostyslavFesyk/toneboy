// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import AppKit
import QuartzCore

/// A full-color capsule with white audio marks in either menu-bar appearance.
final class StatusAnimation {
    private var timer: Timer?
    private var lastTime = CACurrentMediaTime()
    private var phase = 0.0
    private var activity = 0.0
    private var levels = [Double](repeating: 0, count: 5)

    func start(button: NSStatusBarButton, model: EQModel) {
        stop()
        lastTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self, weak button, weak model] _ in
            guard let self, let button, let model else { return }
            let now = CACurrentMediaTime()
            let dt = min(0.1, now - self.lastTime)
            self.lastTime = now
            let peak = model.running ? model.peak : 0
            let target = peak > 0.001 ? 1.0 : 0.0
            self.activity += (target - self.activity) * (1 - exp(-dt / 0.3))
            for i in self.levels.indices {
                let targetLevel = model.running ? model.statusLevels[i] : 0
                self.levels[i] += (targetLevel - self.levels[i]) * (1 - exp(-dt / 0.018))
            }
            self.phase = (self.phase + dt * 2.2).truncatingRemainder(dividingBy: .pi * 2)
            button.image = Self.image(phase: self.phase, activity: self.activity, levels: self.levels, palette: GradientPalette(rawValue: UserDefaults.standard.string(forKey: "gradient-palette") ?? "") ?? .ocean)
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() { timer?.invalidate(); timer = nil }
    deinit { stop() }

    private static var backgrounds: [GradientPalette: NSImage] = [:]

    private static func background(for palette: GradientPalette) -> NSImage {
        if let cached = backgrounds[palette] { return cached }
        let image = NSImage(size: NSSize(width: 32, height: 20), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).addClip()
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            palette.drawStatusGradient(in: context, size: rect.size)
            return true
        }
        backgrounds[palette] = image
        return image
    }

    static func image(phase: Double, activity: Double, levels: [Double], palette: GradientPalette = .ocean) -> NSImage {
        let background = background(for: palette)
        let image = NSImage(size: NSSize(width: 32, height: 20), flipped: false) { rect in
            background.draw(in: rect)
            let wave = NSBezierPath()
            wave.lineWidth = 1.65
            wave.lineCapStyle = .round
            for step in 0...60 {
                let x = 6.5 + Double(step) / 60 * 19
                let y = 10 + sin(Double(step) / 60 * .pi * 2 - phase) * 3.5
                if step == 0 { wave.move(to: NSPoint(x: x, y: y)) }
                else { wave.line(to: NSPoint(x: x, y: y)) }
            }
            NSColor.white.withAlphaComponent(1 - activity).setStroke()
            wave.stroke()

            NSColor.white.withAlphaComponent(activity).setStroke()
            for i in 0..<5 {
                let height = 2 + 12 * levels[i]
                let bar = NSBezierPath()
                bar.lineWidth = 1.8
                bar.lineCapStyle = .round
                let x = 8 + Double(i) * 4
                bar.move(to: NSPoint(x: x, y: 10 - height / 2))
                bar.line(to: NSPoint(x: x, y: 10 + height / 2))
                bar.stroke()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "toneboy equalizer"
        return image
    }
}
