// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import SwiftUI

struct ToneboyLogo: View {
    var palette: GradientPalette

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            context.scaleBy(x: side / 1000, y: side / 1000)
            context.clip(to: Self.silhouette, style: FillStyle(eoFill: true))

            context.withCGContext { cgContext in
                cgContext.translateBy(x: 0, y: 1000)
                cgContext.scaleBy(x: 1, y: -1)
                palette.drawStatusGradient(in: cgContext, size: CGSize(width: 1000, height: 1000))
            }
        }
        .accessibilityHidden(true)
    }

    private static let silhouette = Path { path in
        path.addPath(head.subtracting(earcup(clearance: 34)).subtracting(expression))
        path.addPath(earcup(clearance: 0))
    }

    private static func earcup(clearance: CGFloat) -> Path {
        let bounds = CGRect(x: -102, y: -159, width: 204, height: 318)
            .insetBy(dx: -clearance, dy: -clearance)
        let transform = CGAffineTransform(rotationAngle: -13 * .pi / 180)
            .concatenating(CGAffineTransform(translationX: 146, y: 602))
        return Path(roundedRect: bounds, cornerRadius: bounds.width / 2).applying(transform)
    }

    private static let head = Path { path in
        path.move(to: CGPoint(x: 341, y: 224))
        path.addCurve(to: CGPoint(x: 551, y: 80),
                      control1: CGPoint(x: 365, y: 149), control2: CGPoint(x: 450, y: 80))
        path.addCurve(to: CGPoint(x: 768, y: 231),
                      control1: CGPoint(x: 663, y: 80), control2: CGPoint(x: 759, y: 143))
        path.addCurve(to: CGPoint(x: 759, y: 301),
                      control1: CGPoint(x: 771, y: 256), control2: CGPoint(x: 768, y: 280))
        path.addQuadCurve(to: CGPoint(x: 763, y: 325), control: CGPoint(x: 754, y: 312))
        path.addCurve(to: CGPoint(x: 815, y: 442),
                      control1: CGPoint(x: 791, y: 364), control2: CGPoint(x: 810, y: 408))
        path.addQuadCurve(to: CGPoint(x: 824, y: 458), control: CGPoint(x: 817, y: 451))
        path.addCurve(to: CGPoint(x: 889, y: 613),
                      control1: CGPoint(x: 867, y: 501), control2: CGPoint(x: 889, y: 555))
        path.addCurve(to: CGPoint(x: 634, y: 920),
                      control1: CGPoint(x: 889, y: 741), control2: CGPoint(x: 781, y: 874))
        path.addCurve(to: CGPoint(x: 238, y: 824),
                      control1: CGPoint(x: 484, y: 967), control2: CGPoint(x: 320, y: 924))
        path.addCurve(to: CGPoint(x: 144, y: 470),
                      control1: CGPoint(x: 158, y: 727), control2: CGPoint(x: 118, y: 603))
        path.addCurve(to: CGPoint(x: 326, y: 240),
                      control1: CGPoint(x: 165, y: 359), control2: CGPoint(x: 245, y: 263))
        path.addQuadCurve(to: CGPoint(x: 341, y: 224), control: CGPoint(x: 336, y: 237))
        path.closeSubpath()
    }

    private static let expression = Path { path in
        path.move(to: CGPoint(x: 730, y: 584.1))
        path.addCurve(to: CGPoint(x: 765.8, y: 631.5),
                      control1: CGPoint(x: 754.9, y: 585.6), control2: CGPoint(x: 774.6, y: 605.1))
        path.addCurve(to: CGPoint(x: 700.8, y: 714.7),
                      control1: CGPoint(x: 755.5, y: 662.5), control2: CGPoint(x: 727.6, y: 693.2))
        path.addCurve(to: CGPoint(x: 519.1, y: 759.6),
                      control1: CGPoint(x: 651.4, y: 754.1), control2: CGPoint(x: 584.4, y: 772.7))
        path.addCurve(to: CGPoint(x: 495.7, y: 753.4),
                      control1: CGPoint(x: 511.3, y: 758), control2: CGPoint(x: 503.2, y: 755.9))
        path.addCurve(to: CGPoint(x: 476.6, y: 744.8),
                      control1: CGPoint(x: 489.2, y: 751.2), control2: CGPoint(x: 482.7, y: 747.8))
        path.addCurve(to: CGPoint(x: 414.9, y: 661.1),
                      control1: CGPoint(x: 449, y: 731), control2: CGPoint(x: 402.5, y: 698.2))
        path.addCurve(to: CGPoint(x: 427.3, y: 644.9),
                      control1: CGPoint(x: 417, y: 654.9), control2: CGPoint(x: 422.3, y: 649.9))
        path.addCurve(to: CGPoint(x: 440.2, y: 638.6),
                      control1: CGPoint(x: 431.2, y: 642.4), control2: CGPoint(x: 435.8, y: 639.5))
        path.addCurve(to: CGPoint(x: 505.3, y: 676.9),
                      control1: CGPoint(x: 468, y: 633.1), control2: CGPoint(x: 484.7, y: 664.6))
        path.addCurve(to: CGPoint(x: 599, y: 688.4),
                      control1: CGPoint(x: 533.3, y: 693.7), control2: CGPoint(x: 566.4, y: 692.4))
        path.addCurve(to: CGPoint(x: 679.8, y: 642),
                      control1: CGPoint(x: 628.3, y: 680), control2: CGPoint(x: 657.9, y: 667.9))
        path.addCurve(to: CGPoint(x: 730, y: 584.1),
                      control1: CGPoint(x: 697, y: 621.6), control2: CGPoint(x: 703, y: 591.8))
        path.closeSubpath()

        path.move(to: CGPoint(x: 479.4, y: 467.5))
        path.addCurve(to: CGPoint(x: 564.1, y: 512),
                      control1: CGPoint(x: 512, y: 471.6), control2: CGPoint(x: 547.9, y: 479.6))
        path.addCurve(to: CGPoint(x: 533.9, y: 548.8),
                      control1: CGPoint(x: 566.3, y: 530.2), control2: CGPoint(x: 556.3, y: 552))
        path.addCurve(to: CGPoint(x: 512.9, y: 536.3),
                      control1: CGPoint(x: 525.4, y: 547.5), control2: CGPoint(x: 520.2, y: 540.7))
        path.addCurve(to: CGPoint(x: 493.8, y: 528.7),
                      control1: CGPoint(x: 507.1, y: 532.8), control2: CGPoint(x: 500.3, y: 530.6))
        path.addCurve(to: CGPoint(x: 408.7, y: 568.8),
                      control1: CGPoint(x: 454.9, y: 520.9), control2: CGPoint(x: 434.1, y: 543.4))
        path.addCurve(to: CGPoint(x: 370, y: 544.5),
                      control1: CGPoint(x: 391.2, y: 582.8), control2: CGPoint(x: 365.3, y: 567.8))
        path.addCurve(to: CGPoint(x: 391.5, y: 511.5),
                      control1: CGPoint(x: 372.4, y: 532.2), control2: CGPoint(x: 383.4, y: 521.5))
        path.addCurve(to: CGPoint(x: 479.4, y: 467.5),
                      control1: CGPoint(x: 418.3, y: 484.7), control2: CGPoint(x: 443.4, y: 472))
        path.closeSubpath()

        path.move(to: CGPoint(x: 674.5, y: 361.4))
        path.addCurve(to: CGPoint(x: 723.7, y: 392.4),
                      control1: CGPoint(x: 695.4, y: 361.4), control2: CGPoint(x: 716.8, y: 371.6))
        path.addCurve(to: CGPoint(x: 730.4, y: 419.2),
                      control1: CGPoint(x: 726.7, y: 401.2), control2: CGPoint(x: 727.9, y: 410.3))
        path.addCurve(to: CGPoint(x: 738.6, y: 510.5),
                      control1: CGPoint(x: 738.7, y: 448), control2: CGPoint(x: 753.2, y: 481.2))
        path.addCurve(to: CGPoint(x: 664, y: 517.2),
                      control1: CGPoint(x: 718.4, y: 535.7), control2: CGPoint(x: 688.2, y: 541.4))
        path.addCurve(to: CGPoint(x: 649.2, y: 478.5),
                      control1: CGPoint(x: 654.4, y: 505.2), control2: CGPoint(x: 652.9, y: 492.8))
        path.addCurve(to: CGPoint(x: 636.7, y: 430.7),
                      control1: CGPoint(x: 645, y: 462.7), control2: CGPoint(x: 641.2, y: 446.5))
        path.addCurve(to: CGPoint(x: 656.3, y: 367.1),
                      control1: CGPoint(x: 630, y: 407), control2: CGPoint(x: 633.2, y: 380.9))
        path.addCurve(to: CGPoint(x: 674.5, y: 361.4),
                      control1: CGPoint(x: 661.7, y: 363.9), control2: CGPoint(x: 668.5, y: 363.1))
        path.closeSubpath()
    }
}
