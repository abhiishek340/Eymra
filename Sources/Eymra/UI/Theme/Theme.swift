import SwiftUI
import UIKit

/// Eymra's look: a soft, slowly moving sky behind clear glass, serif headlines, calm ink-coloured text.
enum Theme {
    /// UI tests launched with -stillMotion pause the endless decorative motion (sky, orbit, shimmer), the same
    /// way Reduce Motion does, so the app settles between taps. Finite animations still run.
    static let stillMotion = ProcessInfo.processInfo.arguments.contains("-stillMotion")

    /// Main text on glass.
    static let ink = Color("Ink")
    static let inkSoft = Color("Ink").opacity(0.66)
    static let inkFaint = Color("Ink").opacity(0.42)
    /// Text and icons on the solid ink button.
    static let onInk = Color("OnInk")
    /// The page, the cards on it, and the one accent (used sparingly: counts, the opener, progress).
    static let paper = Color("Paper")
    static let surface = Color("Surface")
    static let ember = Color("Ember")
    static let hairline = Color("Ink").opacity(0.08)

    /// Spring presets, so every press and move feels like the same app.
    enum Motion {
        /// Quick and exact: toggles, chips, tab pill.
        static let snap = Animation.spring(response: 0.28, dampingFraction: 0.86)
        /// A little bounce: buttons, cards arriving.
        static let pop = Animation.spring(response: 0.42, dampingFraction: 0.72)
        /// Calm and soft: screens and large layout changes.
        static let settle = Animation.spring(response: 0.62, dampingFraction: 0.9)
    }

    static func title(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static func display(_ size: CGFloat = 44) -> Font { .system(size: size, weight: .medium, design: .serif) }
    static let body = Font.system(.body, design: .default)
    static let caption = Font.system(.footnote, design: .default)
}

// MARK: - Background

/// The page: warm paper in light mode, warm charcoal in dark mode (never blue), with one soft light at the top.
/// Flat and still, like Hinge or Uber: the photos are the colour, not the background.
struct DreamBackground: View {
    /// Kept for call sites; the page never animates.
    var animated = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            Theme.paper
            RadialGradient(colors: [Theme.ember.opacity(scheme == .dark ? 0.10 : 0.07), .clear],
                           center: .init(x: 0.85, y: 0), startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The welcome page: warm paper with soft peach and ember light drifting slowly underneath, like late sun on a wall.
/// Still under Reduce Motion and in UI tests; never blue or purple.
struct WarmMesh: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || Theme.stillMotion)) { context in
            let t = reduceMotion || Theme.stillMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: points(t), colors: colors)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Corners stay put and edge points only slide along their edge, so the mesh always covers the screen.
    private func points(_ t: Double) -> [SIMD2<Float>] {
        let s = { (speed: Double, phase: Double, amount: Float) in Float(sin(t * speed + phase)) * amount }
        return [
            [0, 0], [0.5 + s(0.22, 0, 0.15), 0], [1, 0],
            [0, 0.5 + s(0.25, 1, 0.12)], [0.5 + s(0.35, 0, 0.08), 0.45 + s(0.28, 2, 0.08)], [1, 0.45 + s(0.2, 1, 0.14)],
            [0, 1], [0.5 + s(0.28, 2, 0.12), 1], [1, 1],
        ]
    }

    private var colors: [Color] {
        scheme == .dark
            ? [Color(red: 0.11, green: 0.10, blue: 0.09), Color(red: 0.16, green: 0.12, blue: 0.10), Color(red: 0.24, green: 0.14, blue: 0.10),
               Color(red: 0.12, green: 0.11, blue: 0.10), Color(red: 0.20, green: 0.13, blue: 0.10), Color(red: 0.14, green: 0.12, blue: 0.10),
               Color(red: 0.10, green: 0.09, blue: 0.08), Color(red: 0.13, green: 0.11, blue: 0.10), Color(red: 0.11, green: 0.10, blue: 0.09)]
            : [Color(red: 0.98, green: 0.96, blue: 0.93), Color(red: 0.99, green: 0.92, blue: 0.86), Color(red: 0.99, green: 0.84, blue: 0.74),
               Color(red: 0.98, green: 0.95, blue: 0.91), Color(red: 1.00, green: 0.89, blue: 0.80), Color(red: 0.99, green: 0.93, blue: 0.87),
               Color(red: 0.97, green: 0.94, blue: 0.90), Color(red: 0.98, green: 0.92, blue: 0.86), Color(red: 0.97, green: 0.95, blue: 0.92)]
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

    /// A quick springy pop when this becomes the selected one (the one being let go of stays still).
    func popWhenSelected(_ selected: Bool) -> some View {
        keyframeAnimator(initialValue: 1.0, trigger: selected) { content, scale in
            content.scaleEffect(selected ? scale : 1)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(1.22, duration: 0.14)
                SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
            }
        }
    }
}

/// Every few seconds a narrow streak of light glides across a capsule, like light catching a lacquered button.
/// Applied inside a button style, so it belongs to the button (outside, it showed up as a second element).
private struct SheenModifier: ViewModifier {
    @State private var phase: CGFloat = -0.4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(SheenStreak(phase: phase))
            .onAppear {
                guard !reduceMotion && !Theme.stillMotion else { return }
                withAnimation(.easeInOut(duration: 1.3).delay(2.6).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
    }
}

/// The streak is a gradient inside the capsule whose bright band moves, so nothing is ever drawn outside the button
/// (an offset overlay stretched the button's frame and moved where taps land).
private struct SheenStreak: ViewModifier, Animatable {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        content.overlay {
            Capsule()
                .fill(LinearGradient(stops: [.init(color: .clear, location: 0),
                                             .init(color: .white.opacity(0.26), location: 0.5),
                                             .init(color: .clear, location: 1)],
                                     startPoint: UnitPoint(x: phase - 0.18, y: 0.2), endPoint: UnitPoint(x: phase + 0.18, y: 0.8)))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
                guard !Theme.stillMotion else { return }
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

// MARK: - Glass

extension View {
    /// A card on the page: a solid surface with a hairline and a soft shadow. (Named glassCard for call sites; glass is
    /// kept for things that float over content: the tab bar and floating buttons.)
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 28, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self
            .background(shape.fill(Theme.surface))
            .background(tint.map { _ in shape.fill(Theme.surface) })
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 16, y: 6)
    }

    /// Glass pill. Not interactive by default: on iOS 26 an interactive glass effect inside a Button's label can take
    /// the touch for itself and the button never fires (seen with back buttons on device). Buttons do their own press effect.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
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
    /// A streak of light now and then, for the one button a screen is about.
    var sheen = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.onInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .contentShape(Capsule())
            .background {
                Capsule().fill(Theme.ink)
                    .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center)))
                    .shadow(color: .black.opacity(configuration.isPressed ? 0.10 : 0.22),
                            radius: configuration.isPressed ? 6 : 16, y: configuration.isPressed ? 3 : 8)
            }
            .modifier(OptionalSheen(on: sheen && isEnabled))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// A quieter glass pill.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            // The whole pill takes the tap: Liquid Glass alone doesn't count as tappable content.
            .contentShape(Capsule())
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.02 : 0.05), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == GlassPrimaryButtonStyle {
    static var glassPrimary: GlassPrimaryButtonStyle { GlassPrimaryButtonStyle() }
    static var glassPrimarySheen: GlassPrimaryButtonStyle { GlassPrimaryButtonStyle(sheen: true) }
}

private struct OptionalSheen: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on { content.modifier(SheenModifier()) } else { content }
    }
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
            .foregroundStyle(selected ? Theme.onInk : Theme.ink.opacity(0.8))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Capsule())
            .background {
                if selected {
                    Capsule().fill(Theme.ink).transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    Capsule().fill(Theme.surface).overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                }
            }
            .animation(Theme.Motion.snap, value: selected)
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

// MARK: - Toast and back gesture

/// A short message bubble at the bottom of the screen; clears itself after a few seconds.
struct ToastOverlay: View {
    @Binding var message: String?
    var bottomPadding: CGFloat = 110

    var body: some View {
        VStack {
            Spacer()
            if let message {
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .glassCapsule(tint: .white.opacity(0.5), interactive: false)
                    .padding(.horizontal, 24)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.8))
                        withAnimation { self.message = nil }
                    }
                    .accessibilityIdentifier("toast")
            }
        }
        .animation(.spring(duration: 0.4), value: message)
        .allowsHitTesting(false)
    }
}

/// Swipe right from the left edge to go back, like a navigation stack. The screen follows the finger.
/// Uses UIKit's screen-edge pan (the recogniser navigation controllers use), which is built to coexist with
/// scroll views; plain SwiftUI drags lose the touch to the scroll view on a real device.
struct EdgeSwipeBack: ViewModifier {
    let action: () -> Void
    @State private var drag: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: max(0, drag) * 0.6)
            .gesture(ScreenEdgePan { translation in
                drag = translation
            } ended: { translation, velocity in
                withAnimation(Theme.Motion.snap) { drag = 0 }
                if translation > 90 || velocity > 600 { action() }
            })
    }
}

private struct ScreenEdgePan: UIGestureRecognizerRepresentable {
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
        let recognizer = UIScreenEdgePanGestureRecognizer()
        recognizer.edges = .left
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed: changed(translation)
        case .ended: ended(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed: ended(0, 0)
        default: break
        }
    }
}

extension View {
    func edgeSwipeBack(_ action: @escaping () -> Void) -> some View { modifier(EdgeSwipeBack(action: action)) }
}
