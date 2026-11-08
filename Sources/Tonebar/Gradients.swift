// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import SwiftUI

enum GradientPalette: String, CaseIterable {
    case ocean, iris, rose, forest
    var title: String { rawValue.capitalized }
    var center: Color {
        switch self {
        case .ocean:return Color(red:0.02,green:0.48,blue:1.00)
        case .iris:return Color(red:0.53,green:0.12,blue:0.98)
        case .rose:return Color(red:0.91,green:0.10,blue:0.56)
        case .forest:return Color(red:0.00,green:0.66,blue:0.56)
        }
    }
    var bottom: Color {
        switch self {
        case .ocean:return Color(red:0.06,green:0.13,blue:0.68)
        case .iris:return Color(red:0.14,green:0.04,blue:0.62)
        case .rose:return Color(red:0.32,green:0.03,blue:0.64)
        case .forest:return Color(red:0.00,green:0.28,blue:0.39)
        }
    }
    var halo: Color {
        switch self {
        case .ocean:return Color(red:0.44,green:0.89,blue:1.00)
        case .iris:return Color(red:0.96,green:0.55,blue:0.89)
        case .rose:return Color(red:1.00,green:0.62,blue:0.65)
        case .forest:return Color(red:0.57,green:0.92,blue:0.70)
        }
    }
}
final class GradientStore: ObservableObject {
    @Published private(set) var current: GradientPalette
    init() {
        current = UserDefaults.standard.string(forKey:"gradient-palette").flatMap(GradientPalette.init(rawValue:)) ?? .ocean
        if let i=CommandLine.arguments.firstIndex(of:"--gradient"), CommandLine.arguments.count>i+1,
           let preview=GradientPalette(rawValue:CommandLine.arguments[i+1]) { current=preview }
    }
    func select(_ palette: GradientPalette) {
        current=palette
        UserDefaults.standard.set(palette.rawValue,forKey:"gradient-palette")
    }
}
struct GradientMotion: Equatable {
    var energy = 0.0
    var bass = 0.0
    var balance = 0.0

    mutating func follow(_ levels: [Double]) {
        let average = levels.reduce(0, +) / Double(levels.count)
        // Preserve transients instead of averaging them away across all five bands.
        let intensity = 0.65 * (levels.max() ?? 0) + 0.35 * average
        func step(_ value: Double, toward target: Double, rate: Double) -> Double {
            // Two former smoothing steps per tick: half the settling time.
            let fasterRate = 1 - (1 - rate) * (1 - rate)
            return value + min(0.05, max(-0.05, (target - value) * fasterRate))
        }
        energy = step(energy, toward: intensity, rate: intensity > energy ? 0.18 : 0.08)
        bass = step(bass, toward: levels[0], rate: levels[0] > bass ? 0.20 : 0.10)
        balance = step(balance, toward: (levels[3] + levels[4] - levels[0] - levels[1]) / 2, rate: 0.08)
    }
}

struct GradientSurface: View, Animatable {
    var palette: GradientPalette
    var motion = GradientMotion()
    var activation = 1.0
    var animatableData: Double {
        get { activation }
        set { activation = newValue }
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Canvas { context, size in
            let movement = reduceMotion ? GradientMotion() : motion
            let progress = min(1, max(0, activation))
            let radius = 1.13 * (reduceMotion ? 1 : 0.75 + 0.25 * progress)
            func faded(_ color: Color) -> Color {
                Color(nsColor: NSColor(color).blended(withFraction: 1 - progress, of: .white) ?? .white)
            }
            let middleStop = max(0.42, min(0.76,
                0.52 - movement.balance * 0.15 + movement.bass * 0.12))
            let haloStop = max(middleStop + 0.28, 0.88 + movement.energy * 0.24)
            context.scaleBy(x: size.width, y: size.height)
            let bounds = Path(CGRect(x: 0, y: 0, width: 1, height: 1))
            let core = CGPoint(x: 0.5, y: 1.12)
            func colors(middle: Double, halo: Double) -> Gradient {
                let extent = max(1, halo)
                return Gradient(stops: [
                    .init(color: faded(palette.bottom), location: 0),
                    .init(color: faded(palette.bottom), location: 0.13 / extent),
                    .init(color: faded(palette.center), location: middle / extent),
                    .init(color: faded(palette.halo), location: halo / extent),
                    .init(color: faded(palette.halo), location: 1)
                ])
            }
            // The entire dark core and its transition stay on a fixed base.
            context.fill(bounds, with: .radialGradient(colors(middle: 0.52, halo: 0.88),
                center: core, startRadius: 0, endRadius: radius))
            context.drawLayer { layer in
                // Clip only the animated rings, leaving the underlying core untouched.
                layer.clipToLayer { maskLayer in
                    let mask = Gradient(stops: (0...20).map { index in
                        let position = Double(index) / 20
                        let t = min(1, max(0, (position - 0.32) / 0.30))
                        let alpha = t * t * (3 - 2 * t)
                        return Gradient.Stop(color: .white.opacity(alpha), location: position)
                    })
                    maskLayer.fill(bounds, with: .radialGradient(mask,
                        center: core, startRadius: 0, endRadius: radius))
                }
                layer.fill(bounds, with: .radialGradient(colors(middle: middleStop, halo: haloStop),
                    center: core, startRadius: 0, endRadius: radius * max(1, haloStop)))
            }
            context.fill(bounds, with: .linearGradient(
                Gradient(stops: [
                    .init(color: faded(Color(red:0.98,green:0.98,blue:1)), location: 0),
                    .init(color: Color.white.opacity(0.96), location: 0.10),
                    .init(color: Color.white.opacity(0.52), location: 0.25),
                    .init(color: Color.white.opacity(0), location: 0.45),
                    .init(color: Color.white.opacity(0), location: 1)
                ]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: 1)))
        }
        .background(Color.white)
        .allowsHitTesting(false)
    }
}
