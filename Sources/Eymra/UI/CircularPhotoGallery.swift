import SwiftUI

/// How far the page has scrolled. Only the ring reads it, so scrolling turns the ring without redrawing the page.
@MainActor @Observable
final class GalleryScroll {
    var offset: CGFloat = 0
}

/// Your photos as a turntable of framed pairs, like a showroom: the ring glides one card on with a soft overshoot,
/// rests to show the pair in front, and a streak of light passes over them as they settle. Cards bob gently, cast a
/// faint reflection on a pool of gold light, and fade out before they turn side-on. Scrolling spins it, a tap steps it.
struct CircularPhotoGallery: View {
    let ids: [String]
    let scroll: GalleryScroll
    @State private var taps = 0
    @State private var tapsFrom = 0
    @State private var tappedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let card = CGSize(width: 132, height: 186)
    private static let slotCount = 12
    /// One step every this many seconds: the glide takes `glide`, the rest is the pause.
    private static let period = 2.6
    private static let glide = 1.0

    private var still: Bool { reduceMotion || Theme.stillMotion }

    /// Two photos per card; photos repeat round the ring when there are only a few.
    private var pairs: [(String?, String?)] {
        guard !ids.isEmpty else { return Array(repeating: (nil, nil), count: Self.slotCount) }
        return (0..<Self.slotCount).map { (ids[(2 * $0) % ids.count], ids[(2 * $0 + 1) % ids.count]) }
    }

    var body: some View {
        TimelineView(.animation(paused: still)) { context in
            GeometryReader { geo in
                ring(now: context.date, size: geo.size)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { tap() }
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityHidden(true)
    }

    private func ring(now: Date, size: CGSize) -> some View {
        let items = pairs
        let n = Double(items.count)
        let t = still ? 0 : now.timeIntervalSinceReferenceDate
        let (steps, settle) = autoSteps(t)
        // Half a step off centre, so a pair of cards shares the front.
        let rotation = -(steps + tapSteps(now)) * 360 / n + Double(scroll.offset) * 0.35 + 180 / n
        let radius = Double(Self.card.width) * 1.1 / (2 * sin(.pi / n))
        let depth = 1300.0
        let floor = Double(size.height) * 0.5 + Double(Self.card.height) * 0.5 - 14
        return ZStack {
            // A pool of gold light on the floor under the front pair.
            Ellipse()
                .fill(RadialGradient(colors: [Luxe.gold.opacity(0.32), Luxe.gold.opacity(0)], center: .center, startRadius: 0, endRadius: 170))
                .frame(width: 360, height: 80)
                .position(x: size.width / 2, y: floor + 16)
                .blur(radius: 6)
            ForEach(Array(items.enumerated()), id: \.offset) { i, pair in
                let angle = (Double(i) * 360 / n + rotation).truncatingRemainder(dividingBy: 360)
                let rad = angle * .pi / 180
                let facing = cos(rad)   // 1 facing you, -1 round the back
                let scale = depth / (depth + radius * (1 - facing))
                let opacity = min(1, max(0, (facing - 0.05) / 0.45))
                // A slow wave runs round the ring.
                let bob = still ? 0 : sin(t * 1.4 + Double(i) * 0.9) * 4
                if opacity > 0 {
                    framedPair(pair, number: i + 1, facing: facing, shine: facing > 0.9 ? settle : nil)
                        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.25)
                        .scaleEffect(scale)
                        .offset(x: sin(rad) * radius * scale, y: (1 - scale) * -70 + bob)
                        .opacity(opacity)
                        .zIndex(facing)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: A card

    /// Two photos stacked in one frame, with a reflection fading into the floor below.
    private func framedPair(_ pair: (String?, String?), number: Int, facing: Double, shine: Double?) -> some View {
        let face = card(pair, number: number, facing: facing, shine: shine)
        return VStack(spacing: 4) {
            face
            face
                .scaleEffect(x: 1, y: -1)
                .frame(height: 46, alignment: .bottom)
                .clipped()
                .mask(LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
        }
        .offset(y: 25)
    }

    private func card(_ pair: (String?, String?), number: Int, facing: Double, shine: Double?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(spacing: 3) {
            half(pair.0, tone: number)
            half(pair.1, tone: number + 3)
        }
        .padding(4)
        .background(Luxe.card)
        .overlay(alignment: .bottomLeading) {
            Text(String(format: "N° %02d", number))
                .font(.system(size: 11, weight: .medium, design: .serif))
                .italic()
                .foregroundStyle(Luxe.champagne)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.45)))
                .padding(9)
        }
        .overlay {
            // The streak of light that passes over the front pair as it settles.
            if let shine {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white.opacity(0.32), location: 0.5),
                                       .init(color: .clear, location: 1)],
                               startPoint: UnitPoint(x: shine * 1.8 - 0.6, y: 0), endPoint: UnitPoint(x: shine * 1.8 - 0.2, y: 1))
                    .blendMode(.plusLighter)
            }
        }
        // Cards turning away sink into the dark.
        .overlay(Color.black.opacity((1 - facing) * 0.35))
        .frame(width: Self.card.width, height: Self.card.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [Luxe.champagne.opacity(0.55), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                                    lineWidth: 1))
        .shadow(color: .black.opacity(0.5 * facing), radius: 16, y: 12)
    }

    @ViewBuilder private func half(_ id: String?, tone: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        if let id {
            PhotoThumbnail(photoID: id, longEdge: 360).clipShape(shape)
        } else {
            let tones = [Luxe.coral, Luxe.gold, Luxe.emerald, Luxe.rose, Luxe.amber, Luxe.sea]
            shape.fill(LinearGradient(colors: [tones[tone % tones.count].opacity(0.85), Luxe.card], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    // MARK: Motion

    /// The turntable: whole steps so far plus the eased glide of the current one, and how far the light streak has
    /// got across the front pair after it settles (nil while gliding or once it has passed).
    private func autoSteps(_ t: Double) -> (Double, Double?) {
        guard !still else { return (0, nil) }
        let cycle = t / Self.period
        let whole = cycle.rounded(.down)
        let into = (cycle - whole) * Self.period
        let glide = min(1, into / Self.glide)
        let shineProgress = (into - Self.glide) / 0.9
        let shine: Double? = (0...1).contains(shineProgress) ? shineProgress : nil
        return (whole + Self.easeOutBack(glide), shine)
    }

    /// Eases out past the target a touch and settles back, like a turntable coming to rest.
    private static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.2, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    private func tap() {
        tapsFrom = Int(tapSteps(Date()).rounded())
        taps += 1
        tappedAt = Date()
    }

    private func tapSteps(_ now: Date) -> Double {
        guard let at = tappedAt, !still else { return Double(taps) }
        let p = min(1, max(0, now.timeIntervalSince(at) / 0.7))
        return Double(tapsFrom) + (Double(taps) - Double(tapsFrom)) * Self.easeOutBack(p)
    }
}
