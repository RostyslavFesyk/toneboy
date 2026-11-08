// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import SwiftUI
import AppKit

private let ink = Color(nsColor: .windowBackgroundColor)
private let accent = Color.accentColor

struct EQView: View {
    @ObservedObject var model: EQModel
    @StateObject private var palette = GradientStore()
    @State private var showGradients = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [palette.current.halo, palette.current.center, palette.current.bottom],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("toneboy").font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                Spacer(minLength: 10)
                Toggle("Equalizer", isOn: Binding(get: { model.running }, set: { _ in
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    model.toggle()
                }))
                    .labelsHidden()
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11, weight: .medium))
                    .tint(palette.current.center).accentColor(palette.current.center)
                    .accessibilityLabel("Equalizer")
                    .fixedSize().help("Turn the equalizer on or off")
                Menu {
                    Button("Audio Access Settings…") { model.openAudioSettings() }
                    Divider()
                    Toggle("Auto Headroom", isOn: Binding(get: { model.autoGain }, set: { model.autoGain = $0; model.push() }))
                    Divider()
                    Button("Reset EQ") { model.applyPreset("Flat") }
                    Button("Quit") { model.stop(); NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "ellipsis").frame(width: 16) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }.padding(.horizontal, 16).padding(.vertical, 13)
            EQGraph(model: model, palette: palette.current, activation: model.running ? 1 : 0)
                .frame(height: 238)
                .animation(.spring(response: 0.6, dampingFraction: 0.88), value: model.running)
            HStack(spacing: 6) {
                ForEach(model.presets, id: \.self) { name in
                    Button { model.applyPreset(name) } label: {
                        Text(name).font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .foregroundStyle(model.running ? (model.preset == name ? palette.current.bottom : Color.white) : Color.gray.opacity(0.7))
                            .background(model.running ? (model.preset == name ? Color.white : Color.white.opacity(0.16)) : Color.clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(model.running ? .white.opacity(model.preset == name ? 1 : 0.25) : .gray.opacity(0.25), lineWidth: 0.7))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button { showGradients.toggle() } label: {
                    HStack(spacing: 5) {
                        Text(palette.current.title)
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(model.running ? .white : .gray.opacity(0.7))
                    .background(model.running ? .white.opacity(0.16) : .clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(model.running ? .white.opacity(0.25) : .gray.opacity(0.25), lineWidth: 0.7))
                }.buttonStyle(.plain).help("Gradient color")
                .popover(isPresented: $showGradients, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(GradientPalette.allCases, id: \.self) { choice in
                            Button {
                                palette.select(choice); showGradients = false
                            } label: {
                                HStack(spacing: 9) {
                                    Circle().fill(LinearGradient(colors: [choice.halo, choice.center, choice.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 16, height: 16)
                                    Text(choice.title)
                                    Spacer()
                                    if palette.current == choice { Image(systemName: "checkmark") }
                                }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.font(.system(size: 12)).foregroundStyle(.primary).padding(6).frame(width: 180)
                }
            }.padding(.horizontal, 16).padding(.vertical, 12)
                .disabled(!model.running)
                .animation(.easeInOut(duration: 0.6), value: model.running)
        }
        .frame(width: 600)
        .background(
            GradientSurface(palette: palette.current, motion: model.gradientMotion,
                            activation: model.running ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.88), value: model.running)
        )
        .preferredColorScheme(.light)
        .onAppear { model.panelVisible = true }
        .onDisappear { model.panelVisible = false }
        .onChange(of: model.running) { _, running in
            if !running { showGradients = false }
        }
    }
}

struct ScrollCapture: NSViewRepresentable {
    var onScroll: (Double) -> Void
    func makeNSView(context: Context) -> ScrollView {
        let view = ScrollView()
        view.onScroll = onScroll
        return view
    }
    func updateNSView(_ view: ScrollView, context: Context) { view.onScroll = onScroll }
    final class ScrollView: NSView {
        var onScroll: ((Double) -> Void)?
        var monitor: Any?
        override func viewDidMoveToWindow() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window == self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.onScroll?(Double(event.scrollingDeltaY))
                return nil
            }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

struct EQGraph: View, Animatable {
    private let displayGainRange = 12.0
    @ObservedObject var model: EQModel
    var palette: GradientPalette
    var activation: Double
    var animatableData: Double {
        get { activation }
        set { activation = newValue }
    }
    @State private var draggedBand: Int?
    @State private var showBypassMessage = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Canvas { context, _ in
                let rect = plot(size)
                context.opacity = min(1, max(0, activation))
                let energy = reduceMotion ? 0.0 : min(1, max(0, model.peak))
                for frequency in [20.0,50,100,200,500,1000,2000,5000,10000,20000] {
                    let x = xPosition(frequency, rect)
                    var line = Path(); line.move(to: CGPoint(x: x, y: rect.minY)); line.addLine(to: CGPoint(x: x, y: rect.maxY))
                    context.stroke(line, with: .linearGradient(
                        Gradient(stops: [.init(color: .clear, location: 0),
                                         .init(color: .white.opacity(0.16), location: 0.28),
                                         .init(color: .white.opacity(0.16), location: 1)]),
                        startPoint: CGPoint(x: 0, y: rect.minY),
                        endPoint: CGPoint(x: 0, y: rect.maxY)), lineWidth: 1)
                    let label = frequency >= 1000 ? "\(Int(frequency/1000))k" : "\(Int(frequency))"
                    if frequency > 20 && frequency < 20000 {
                        context.draw(Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.85)), at: CGPoint(x: x, y: rect.maxY+17))
                    }
                }
                // Input FFT in dBFS; its scale is separate from the +/-12 dB EQ axis.
                let points = model.spectrum.enumerated().map { i, value in
                    CGPoint(x: rect.minX + Double(i)/Double(model.spectrum.count-1)*rect.width,
                            y: rect.maxY-max(0,min(1,(value+80)/80))*rect.height*0.88)
                }
                let spectrumRidge = smoothRidge(points)
                var spectrum = spectrumRidge
                spectrum.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                spectrum.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                spectrum.closeSubpath()
                // Isolated compositing keeps blur off labels, handles, and the crisp curve.
                if model.running, (model.spectrum.max() ?? -90) > -78 {
                    context.drawLayer { spectrumLayer in
                        spectrumLayer.clip(to: Path(rect))
                        spectrumLayer.drawLayer { glow in
                            glow.addFilter(.blur(radius: 8))
                            glow.stroke(spectrumRidge, with: .color(.white.opacity(0.22)), lineWidth: 6)
                        }
                        spectrumLayer.fill(spectrum, with: .linearGradient(
                            Gradient(stops: [.init(color: .white.opacity(0.12), location: 0),
                                             .init(color: .white.opacity(0.05), location: 0.55),
                                             .init(color: .clear, location: 1)]),
                            startPoint: CGPoint(x: 0,y: rect.minY), endPoint: CGPoint(x: 0,y: rect.maxY)))
                        spectrumLayer.stroke(spectrumRidge, with: .linearGradient(
                            Gradient(stops: [.init(color: .clear, location: 0),
                                             .init(color: .white.opacity(0.8), location: 0.25),
                                             .init(color: .white.opacity(0.65), location: 0.8),
                                             .init(color: .clear, location: 1)]),
                            startPoint: CGPoint(x: 0,y: rect.minY), endPoint: CGPoint(x: 0,y: rect.maxY)), lineWidth: 1.4)
                        // Fade the composited result, including blur, before it reaches the floor.
                        spectrumLayer.blendMode = .destinationIn
                        spectrumLayer.fill(Path(rect), with: .linearGradient(
                            Gradient(stops: [.init(color: .white, location: 0),
                                             .init(color: .white, location: 0.84),
                                             .init(color: .clear, location: 1)]),
                            startPoint: CGPoint(x: 0, y: rect.minY),
                            endPoint: CGPoint(x: 0, y: rect.maxY)))
                    }
                }

                let curve = responsePath(rect)
                // Shade the actual combined response relative to unity, including cuts.
                // A single continuous region keeps overlapping filters from hiding the net EQ.
                var difference = curve
                difference.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                difference.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                difference.closeSubpath()
                context.fill(difference, with: .linearGradient(
                    Gradient(stops: [.init(color: .white.opacity(0.27), location: 0),
                                     .init(color: .white.opacity(0.12), location: 0.5),
                                     .init(color: .white.opacity(0.24), location: 1)]),
                    startPoint: CGPoint(x: 0,y: rect.minY), endPoint: CGPoint(x: 0,y: rect.maxY)))
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 10))
                    glow.stroke(curve, with: .color(.white.opacity(0.22+energy*0.06)), lineWidth: 12)
                }
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 3))
                    glow.stroke(curve, with: .color(.white.opacity(0.35)), lineWidth: 5)
                }
                context.stroke(curve, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                for band in model.bands {
                    let point = CGPoint(x: xPosition(band.frequency, rect), y: yPosition(band.graphGain, rect))
                    let circle = Path(ellipseIn: CGRect(x: point.x-10, y: point.y-10, width: 20, height: 20))
                    context.fill(circle, with: .color(.white))
                    context.fill(circle, with: .color(palette.center.opacity(min(1, max(0, activation)))))
                    context.stroke(circle, with: .color(.white),
                                   lineWidth: 2.5)
                    if model.running && draggedBand == band.id {
                        let labelX = min(rect.maxX-36, max(rect.minX+36, point.x))
                        let labelY = point.y < rect.minY+35 ? point.y+30 : point.y-29
                        let labelRect = CGRect(x: labelX-32, y: labelY-11, width: 64, height: 22)
                        context.fill(Path(roundedRect: labelRect, cornerRadius: 11), with: .color(ink.opacity(0.94)))
                        let number = context.resolve(Text(String(format: "%+.1f", band.gain))
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(.primary))
                        let unit = context.resolve(Text("dB")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.primary))
                        let maxNumber = context.resolve(Text("+18.0")
                            .font(.system(size: 11, weight: .medium)).monospacedDigit())
                        let proposal = CGSize(width: 100, height: 22)
                        let numberWidth = maxNumber.measure(in: proposal).width
                        let unitWidth = unit.measure(in: proposal).width
                        let gap = 4.0
                        let left = labelX - (numberWidth + gap + unitWidth) / 2
                        // Center the number in a fixed slot; the unit never shifts with its value.
                        context.draw(number, at: CGPoint(x: left + numberWidth / 2, y: labelY))
                        context.draw(unit, at: CGPoint(x: left + numberWidth + gap, y: labelY), anchor: .leading)
                    }
                }


            }
            .background(ScrollCapture { delta in
                guard model.running else { return }
                let band = model.bands[model.selected]
                model.changeBand(model.selected, q: band.q * exp(delta * 0.015))
            })
            .allowsHitTesting(model.running)
            .overlay {
                VStack(spacing: 12) {
                    Text(model.audioAccess == .denied ? "System audio access is required." :
                         (model.starting ? (model.audioAccess == .authorized ? "Starting equalizer…" : "Allow system audio access to enable toneboy.") :
                         (model.error == nil ? "Equalizer is bypassed" : "Couldn’t start audio. Try again.")))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.gray.opacity(0.7))
                    if model.audioAccess == .denied || model.audioAccess == .unavailable {
                        Button("Open System Settings") { model.openAudioSettings() }
                            .font(.system(size: 11, weight: .medium))
                            .buttonStyle(.bordered)
                    }
                }
                .scaleEffect(showBypassMessage ? 1 : 0.9)
                .opacity(showBypassMessage ? 1 : 0)
                .allowsHitTesting(!model.running && showBypassMessage)
            }
            .onChange(of: model.running) { _, running in
                if !running { draggedBand = nil }
                if running {
                    withAnimation(.easeOut(duration: 0.25)) { showBypassMessage = false }
                }
            }
            .task(id: model.running) {
                guard !model.running else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                    showBypassMessage = true
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard model.running else { draggedBand = nil; return }
                let rect = plot(size)
                if draggedBand == nil {
                    let nearest = model.bands.min { a,b in
                        hypot(xPosition(a.frequency,rect)-value.startLocation.x,yPosition(a.graphGain,rect)-value.startLocation.y) < hypot(xPosition(b.frequency,rect)-value.startLocation.x,yPosition(b.graphGain,rect)-value.startLocation.y)
                    }
                    guard let nearest, hypot(xPosition(nearest.frequency,rect)-value.startLocation.x,yPosition(nearest.graphGain,rect)-value.startLocation.y) < 30 else { return }
                    draggedBand = nearest.id; model.selected = nearest.id
                }
                guard let index = draggedBand else { return }
                let x = min(1,max(0,(value.location.x-rect.minX)/rect.width))
                let gain = displayGainRange-(value.location.y-rect.minY)/rect.height*(2*displayGainRange)
                model.changeBand(index, frequency: 20*pow(1000,x), gain: gain * (model.bands[index].isShelf ? 2 : 1))
            }.onEnded { _ in draggedBand = nil }, including: model.running ? .all : .subviews)
            .help("Drag a point horizontally to change frequency or vertically to change gain. Scroll over the graph to adjust the selected band’s width.")
            .accessibilityLabel("Equalizer response graph. Drag a point to adjust frequency and gain. Scroll to adjust the selected band width.")
        }

    }
    private func smoothRidge(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: first)
            for i in 1..<points.count {
                let previous = points[i-1], current = points[i]
                let middle = CGPoint(x: (previous.x+current.x)/2, y: (previous.y+current.y)/2)
                path.addQuadCurve(to: middle, control: previous)
            }
            path.addLine(to: last)
        }
    }
    private func plot(_ size: CGSize) -> CGRect { CGRect(x: 0, y: 12, width: size.width, height: size.height-43) }
    private func xPosition(_ f: Double, _ rect: CGRect) -> Double { rect.minX + log10(f/20)/3*rect.width }
    private func yPosition(_ db: Double, _ rect: CGRect) -> Double {
        rect.minY + (displayGainRange-min(displayGainRange,max(-displayGainRange,db)))/(2*displayGainRange)*rect.height
    }
    private func responsePath(_ rect: CGRect, band: EQBand? = nil) -> Path {
        Path { p in
            for i in 0...360 {
                let ratio = Double(i)/360
                let db = model.bypass && band == nil ? 0 : model.response(at: 20*pow(1000,ratio), band: band)
                let point = CGPoint(x: rect.minX+ratio*rect.width, y: yPosition(db,rect))
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
        }
    }
}
