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
struct DreamBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                MeshGradient(width: 3, height: 3, points: points(t), colors: colors)
                orbs(t)
            }
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

    private func orbs(_ t: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Circle().fill(.white.opacity(scheme == .dark ? 0.10 : 0.45))
                    .frame(width: w * 0.9).blur(radius: 60)
                    .position(x: w * (0.25 + 0.08 * sin(t * 0.09)), y: h * (0.18 + 0.04 * cos(t * 0.12)))
                Circle().fill(Color(red: 1, green: 0.93, blue: 0.85).opacity(scheme == .dark ? 0.08 : 0.35))
                    .frame(width: w * 0.7).blur(radius: 70)
                    .position(x: w * (0.8 + 0.06 * cos(t * 0.08)), y: h * (0.55 + 0.05 * sin(t * 0.1)))
                Circle().fill(.white.opacity(scheme == .dark ? 0.06 : 0.25))
                    .frame(width: w * 0.6).blur(radius: 50)
                    .position(x: w * (0.4 + 0.1 * sin(t * 0.06 + 2)), y: h * (0.9 + 0.03 * cos(t * 0.09)))
            }
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

    /// Standard page padding and the dreamy background.
    func dreamScreen() -> some View {
        self
            .foregroundStyle(Theme.ink)
            .background(DreamBackground())
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
