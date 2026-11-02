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

/// The stage behind Create, Stories and You: your own photos, blurred into colour and slowly drifting, dissolving
/// from one to the next, under ember, gold and emerald light and a dark veil that keeps the type readable.
/// Built to avoid the usual artifacts: the blur is opaque (no see-through halo at the edges), the photo is scaled
/// past the screen so its blurred border never shows, and a whisper of grain breaks up banding in the dark.
struct LuxeStage: View {
    var photoIDs: [String] = []
    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var still: Bool { reduceMotion || Theme.stillMotion }

    var body: some View {
        ZStack {
            Luxe.stage
            if !photoIDs.isEmpty {
                ZStack {
                    ForEach([photoIDs[index % photoIDs.count]], id: \.self) { id in
                        BackdropPhoto(id: id, moving: !still)
                            .transition(.opacity)
                    }
                }
                .opacity(0.62)
            }
            TimelineView(.animation(minimumInterval: 1 / 20, paused: still)) { context in
                let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
                ZStack {
                    glow(Luxe.coral, size: 520, x: 0.9 + 0.08 * sin(t * 0.13), y: 0.02 + 0.04 * cos(t * 0.11), strength: 0.3)
                    glow(Luxe.gold, size: 460, x: 0.08 + 0.06 * cos(t * 0.09), y: 0.42 + 0.05 * sin(t * 0.1), strength: 0.16)
                    glow(Luxe.emerald, size: 480, x: 0.85 + 0.05 * sin(t * 0.07 + 1), y: 0.86 + 0.03 * cos(t * 0.12), strength: 0.14)
                }
            }
            // A veil: darker at the top for the clock, lighter through the middle, darkest under the buttons.
            LinearGradient(stops: [.init(color: Luxe.stage.opacity(0.7), location: 0), .init(color: Luxe.stage.opacity(0.35), location: 0.3),
                                   .init(color: Luxe.stage.opacity(0.55), location: 0.65), .init(color: Luxe.stage.opacity(0.85), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            Grain()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: photoIDs) { await cycle() }
    }

    private func glow(_ color: Color, size: CGFloat, x: Double, y: Double, strength: Double) -> some View {
        GeometryReader { geo in
            Circle()
                .fill(RadialGradient(colors: [color.opacity(strength), color.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
                .frame(width: size, height: size)
                .position(x: geo.size.width * x, y: geo.size.height * y)
        }
    }

    /// A new photo every seven seconds, dissolving slowly into the next.
    private func cycle() async {
        index = 0
        guard !still, photoIDs.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 2.4)) { index = (index + 1) % photoIDs.count }
        }
    }
}

/// One backdrop photo: a small copy, blurred into soft colour, pushing in and drifting while it's on screen.
private struct BackdropPhoto: View {
    let id: String
    let moving: Bool
    @State private var drifted = false

    var body: some View {
        let seed = MagicView.seed(id)
        GeometryReader { geo in
            // A tiny copy is plenty once blurred, and keeps the drift cheap.
            PhotoThumbnail(photoID: id, longEdge: 120)
                .frame(width: geo.size.width, height: geo.size.height)
                .blur(radius: 34, opaque: true)
                .saturation(1.2)
                .scaleEffect(drifted ? 1.42 : 1.25)
                .offset(x: drifted ? (seed - 0.5) * 60 : 0, y: drifted ? -30 : 0)
                .clipped()
        }
        .onAppear {
            guard moving else { return }
            withAnimation(.easeInOut(duration: 14)) { drifted = true }
        }
    }
}

/// Fine film grain, drawn once, tiled across the screen at a whisper so dark gradients don't band.
private struct Grain: View {
    @MainActor private static let tile: Image? = {
        let side = 96
        var bytes = [UInt8](repeating: 0, count: side * side)
        var seed: UInt32 = 2_463_534_242
        for i in bytes.indices {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            bytes[i] = UInt8(truncatingIfNeeded: seed)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return Image(decorative: image, scale: 2)
    }()

    var body: some View {
        if let tile = Self.tile {
            tile.resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(0.07)
                .allowsHitTesting(false)
        }
    }
}

/// A round jewel badge for an icon: its colour as a soft gradient, the symbol in white.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28
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
            VStack(spacing: 7) {
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
            .padding(.vertical, 10)
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
    var value: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                IconBadge(symbol: symbol, color: color, size: 22)
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1.6)
                    .foregroundStyle(Luxe.faint)
                Spacer()
                if let value {
                    Text(value)
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .italic()
                        .foregroundStyle(Luxe.champagne)
                        .contentTransition(.interpolate)
                        .animation(Theme.Motion.snap, value: value)
                }
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
