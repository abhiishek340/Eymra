import SwiftUI

/// Eymra's look: a soft, slowly moving sky behind clear glass, serif headlines, calm ink-coloured text.
enum Theme {
    /// Main text on glass.
    static let ink = Color("Ink")
    static let inkSoft = Color("Ink").opacity(0.68)
    static let inkFaint = Color("Ink").opacity(0.45)

    static func title(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static func display(_ size: CGFloat = 44) -> Font { .system(size: size, weight: .medium, design: .serif) }
    static let body = Font.system(.body, design: .default)
    static let caption = Font.system(.footnote, design: .default)
}

// MARK: - Background

/// A dreamy sky: a slowly breathing mesh gradient (sky, haze, meadow) with soft drifting light.
/// Drawn once, behind the whole app. The light is radial gradients (no blur filters), and the whole layer is
/// flattened into one Metal-backed image per frame, so it stays smooth while everything above it moves.
struct DreamBackground: View {
    var animated = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !animated || reduceMotion || scenePhase != .active)) { context in
            let t = animated && !reduceMotion ? context.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                MeshGradient(width: 3, height: 3, points: points(t), colors: colors)
                orbs(t)
            }
            .drawingGroup()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        let a = Float(sin(t * 0.13)) * 0.06, b = Float(cos(t * 0.11)) * 0.05, c = Float(sin(t * 0.07 + 1)) * 0.07
        return [
            [0, 0], [0.5 + a, 0], [1, 0],
            [0, 0.45 + b], [0.5 + c, 0.5 + a], [1, 0.5 - b],
            [0, 1], [0.5 - a, 1], [1, 1],
        ]
    }

    private var colors: [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.10, green: 0.14, blue: 0.30), Color(red: 0.16, green: 0.20, blue: 0.40), Color(red: 0.22, green: 0.16, blue: 0.36),
                Color(red: 0.12, green: 0.24, blue: 0.36), Color(red: 0.30, green: 0.24, blue: 0.42), Color(red: 0.36, green: 0.22, blue: 0.34),
                Color(red: 0.08, green: 0.20, blue: 0.22), Color(red: 0.12, green: 0.26, blue: 0.24), Color(red: 0.18, green: 0.18, blue: 0.26),
            ]
        }
        return [
            Color(red: 0.55, green: 0.74, blue: 0.95), Color(red: 0.70, green: 0.84, blue: 0.98), Color(red: 0.80, green: 0.80, blue: 0.97),
            Color(red: 0.78, green: 0.90, blue: 0.96), Color(red: 0.98, green: 0.91, blue: 0.86), Color(red: 0.93, green: 0.84, blue: 0.93),
            Color(red: 0.62, green: 0.80, blue: 0.62), Color(red: 0.76, green: 0.87, blue: 0.68), Color(red: 0.86, green: 0.90, blue: 0.74),
        ]
    }

    private func light(_ color: Color, _ opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }

    private func orbs(_ t: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let dark = scheme == .dark
            ZStack {
                light(.white, dark ? 0.12 : 0.55, size: w * 1.3)
                    .position(x: w * (0.25 + 0.08 * sin(t * 0.09)), y: h * (0.18 + 0.04 * cos(t * 0.12)))
                light(Color(red: 1, green: 0.92, blue: 0.84), dark ? 0.10 : 0.45, size: w * 1.1)
                    .position(x: w * (0.8 + 0.06 * cos(t * 0.08)), y: h * (0.55 + 0.05 * sin(t * 0.1)))
                light(.white, dark ? 0.08 : 0.30, size: w)
                    .position(x: w * (0.4 + 0.1 * sin(t * 0.06 + 2)), y: h * (0.9 + 0.03 * cos(t * 0.09)))
            }
        }
    }
}

// MARK: - Motion

/// Text that writes itself in: each line fades and un-blurs in turn (a TextRenderer, so wrapping stays native).
struct RevealRenderer: TextRenderer, Animatable {
    /// 0 → hidden, 1 → fully shown.
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let runs = layout.flatMap { line in line.flatMap { run in Array(run) } }
        let count = max(1, runs.count)
        for (i, slice) in runs.enumerated() {
            // Each glyph starts a little after the previous one and takes 35% of the timeline to arrive.
            let start = Double(i) / Double(count) * 0.65
            let local = min(1, max(0, (progress - start) / 0.35))
            var copy = context
            copy.opacity = local
            if local < 1 { copy.addFilter(.blur(radius: (1 - local) * 6)) }
            copy.translateBy(x: 0, y: (1 - local) * 6)
            copy.draw(slice)
        }
    }
}

extension View {
    /// Writes text in with a soft blur when it appears (or when `trigger` changes).
    func revealOnAppear<T: Equatable>(delay: Double = 0, duration: Double = 1.1, trigger: T = 0) -> some View {
        modifier(RevealModifier(delay: delay, duration: duration, trigger: trigger))
    }

    /// Fades, lifts and un-blurs a view into place when it appears.
    func riseIn(delay: Double = 0) -> some View {
        modifier(RiseInModifier(delay: delay))
    }

    /// A soft light that sweeps across the content (for "working" text).
    func shimmer(active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}

private struct RevealModifier<T: Equatable>: ViewModifier {
    let delay: Double
    let duration: Double
    let trigger: T
    @State private var progress = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .textRenderer(RevealRenderer(progress: reduceMotion ? 1 : progress))
            .onAppear { play() }
            .onChange(of: trigger) { progress = 0; play() }
    }

    private func play() {
        withAnimation(.easeOut(duration: duration).delay(delay)) { progress = 1 }
    }
}

private struct RiseInModifier: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97, anchor: .top)
            .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.18).delay(delay)) { shown = true } }
    }
}

private struct ShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: phase * geo.size.width * 1.5)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

// MARK: - Glass

extension View {
    /// A clean glass card: Liquid Glass on iOS 26, frosted material with a hairline highlight before that.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 28, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(tint.map { shape.fill($0) })
                .overlay(shape.strokeBorder(.white.opacity(0.45), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        }
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: Capsule())
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .background(tint.map { Capsule().fill($0) })
                .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        }
    }

    /// Ink text over the app's shared sky (the background itself is drawn once, at the root).
    func dreamScreen() -> some View {
        self
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden)
    }
}

/// The main call to action: a bright glass pill.
struct GlassPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold, design: .serif))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .glassCapsule(tint: .white.opacity(0.55))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// A quieter glass pill.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassCapsule()
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassPrimaryButtonStyle {
    static var glassPrimary: GlassPrimaryButtonStyle { GlassPrimaryButtonStyle() }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glassSoft: GlassButtonStyle { GlassButtonStyle() }
}

/// A selectable chip: clear glass, or bright white when chosen.
struct GlassChip: View {
    let title: String
    var systemImage: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 14, weight: .medium)) }
                Text(title).font(.system(size: 15, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(Theme.ink.opacity(selected ? 1 : 0.75))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassCapsule(tint: selected ? .white.opacity(0.7) : nil)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A small label pill on glass.
struct GlassTag: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassCapsule(interactive: false)
    }
}

/// A frosted fade at the bottom of the screen, so content melts away under floating buttons and the tab bar.
struct BottomFade: View {
    var height: CGFloat = 180
    var edge: VerticalEdge = .bottom

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.85), location: 0.45),
                                         .init(color: .black, location: 1)],
                                 startPoint: edge == .bottom ? .top : .bottom, endPoint: edge == .bottom ? .bottom : .top))
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: edge == .bottom ? .bottom : .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Section heading in the serif face.
struct DreamHeading: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold, design: .serif))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
