import SwiftUI

/// Create's evening look: a near-black stage with warm light pooling behind it, champagne type and one jewel colour
/// per choice. Never purple or dark blue.
enum Luxe {
    static let stage = Color(red: 0.055, green: 0.047, blue: 0.043)
    static let card = Color(red: 0.11, green: 0.098, blue: 0.09)
    static let line = Color.white.opacity(0.08)
    static let champagne = Color(red: 0.96, green: 0.87, blue: 0.70)
    static let gold = Color(red: 0.85, green: 0.69, blue: 0.43)
    static let text = Color(red: 0.97, green: 0.95, blue: 0.92)
    static let soft = Color(red: 0.97, green: 0.95, blue: 0.92).opacity(0.62)
    static let faint = Color(red: 0.97, green: 0.95, blue: 0.92).opacity(0.38)

    // One colour per choice, so a glance tells them apart.
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.28)
    static let honey = Color(red: 0.93, green: 0.78, blue: 0.40)
    static let coral = Color(red: 0.98, green: 0.47, blue: 0.36)
    static let rose = Color(red: 0.95, green: 0.43, blue: 0.52)
    static let emerald = Color(red: 0.22, green: 0.74, blue: 0.60)
    static let sea = Color(red: 0.30, green: 0.70, blue: 0.80)
    static let sand = Color(red: 0.86, green: 0.74, blue: 0.58)

    static let goldGradient = LinearGradient(colors: [Color(red: 0.98, green: 0.90, blue: 0.72), gold, Color(red: 0.72, green: 0.55, blue: 0.32)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// The stage: near-black, with ember, gold and emerald light drifting slowly behind everything.
struct LuxeStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion || Theme.stillMotion)) { context in
            let t = reduceMotion || Theme.stillMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Luxe.stage
                glow(Luxe.coral, size: 520, x: 0.9 + 0.08 * sin(t * 0.13), y: 0.02 + 0.04 * cos(t * 0.11), strength: 0.34)
                glow(Luxe.gold, size: 460, x: 0.08 + 0.06 * cos(t * 0.09), y: 0.42 + 0.05 * sin(t * 0.1), strength: 0.2)
                glow(Luxe.emerald, size: 480, x: 0.85 + 0.05 * sin(t * 0.07 + 1), y: 0.86 + 0.03 * cos(t * 0.12), strength: 0.16)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, size: CGFloat, x: Double, y: Double, strength: Double) -> some View {
        GeometryReader { geo in
            Circle()
                .fill(RadialGradient(colors: [color.opacity(strength), color.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
                .frame(width: size, height: size)
                .position(x: geo.size.width * x, y: geo.size.height * y)
        }
    }
}

/// A round jewel badge for an icon: its colour as a soft gradient, the symbol in white.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 34
    var lit = true

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(lit ? .white : color)
            .frame(width: size, height: size)
            .background {
                Circle().fill(lit ? AnyShapeStyle(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(color.opacity(0.16)))
            }
            .overlay(Circle().strokeBorder(.white.opacity(lit ? 0.25 : 0.06), lineWidth: 1))
            .shadow(color: color.opacity(lit ? 0.45 : 0), radius: 8, y: 3)
    }
}

/// A choice on the stage: an icon badge over a short name. Chosen, it lights up in its own colour and glows.
struct LuxeTile: View {
    let title: String
    let symbol: String
    let color: Color
    let selected: Bool
    var width: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                IconBadge(symbol: symbol, color: color, lit: selected)
                    .popWhenSelected(selected)
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Luxe.text : Luxe.soft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? color.opacity(0.16) : Color.white.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? color.opacity(0.85) : Luxe.line, lineWidth: selected ? 1.5 : 1)
            }
            .shadow(color: color.opacity(selected ? 0.35 : 0), radius: 14, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .animation(Theme.Motion.snap, value: selected)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// A panel on the stage: dark glass with a hairline, a jewel icon, a small capital label and the current answer.
struct LuxePanel<Content: View>: View {
    let label: LocalizedStringKey
    let symbol: String
    let color: Color
    let value: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                IconBadge(symbol: symbol, color: color, size: 26)
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1.6)
                    .foregroundStyle(Luxe.faint)
                Spacer()
                Text(value)
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(Luxe.champagne)
                    .contentTransition(.interpolate)
                    .animation(Theme.Motion.snap, value: value)
            }
            content
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Luxe.card.opacity(0.82)))
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial).opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Luxe.line, lineWidth: 1))
    }
}

/// The gold call to action, with a streak of light now and then.
struct LuxeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Luxe.stage)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .contentShape(Capsule())
            .background {
                Capsule().fill(Luxe.goldGradient)
                    .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                    .shadow(color: Luxe.gold.opacity(configuration.isPressed ? 0.2 : 0.45), radius: configuration.isPressed ? 8 : 22, y: 8)
            }
            .modifier(SheenModifier())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// A round control on the stage (minus, plus).
struct LuxeRoundButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Luxe.text)
            .frame(width: 46, height: 46)
            .contentShape(Circle())
            .background(Circle().fill(Color.white.opacity(0.07)))
            .overlay(Circle().strokeBorder(Luxe.line, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.3)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
    }
}
