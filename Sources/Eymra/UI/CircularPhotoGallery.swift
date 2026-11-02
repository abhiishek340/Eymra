import SwiftUI

/// How far the page has scrolled. Only the ring reads it, so scrolling turns the ring without redrawing the page.
@MainActor @Observable
final class GalleryScroll {
    var offset: CGFloat = 0
}

/// Your photos standing on a turning ring, seen from the front: two cards face you side by side, the rest turn
/// away and fade out round the back. Scrolling the page spins it; a tap turns it one card on.
struct CircularPhotoGallery: View {
    let ids: [String]
    let scroll: GalleryScroll
    @State private var steps = 0
    @State private var stepsFrom = 0
    @State private var steppedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let card = CGSize(width: 136, height: 184)
    /// Degrees per second when nothing else is moving it.
    private static let drift = 15.0
    /// An even number of cards, so a pair always faces you.
    private static let slotCount = 12

    private var still: Bool { reduceMotion || Theme.stillMotion }

    /// Photos repeat round the ring when there are only a few.
    private var slots: [String?] {
        guard !ids.isEmpty else { return Array(repeating: nil, count: Self.slotCount) }
        return (0..<max(ids.count + ids.count % 2, Self.slotCount)).map { ids[$0 % ids.count] }
    }

    var body: some View {
        TimelineView(.animation(paused: still)) { context in
            GeometryReader { geo in
                ring(now: context.date, size: geo.size)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { step() }
        .sensoryFeedback(.selection, trigger: steps)
        .accessibilityHidden(true)
    }

    private func ring(now: Date, size: CGSize) -> some View {
        let items = slots
        let n = Double(items.count)
        let t = still ? 0 : now.timeIntervalSinceReferenceDate
        // Half a step off centre, so two cards share the front instead of one sitting in the middle.
        let rotation = t * Self.drift + Double(scroll.offset) * 0.35 + stepAngle(now: now, count: n) + 180 / n
        // Neighbouring cards sit one card width apart (plus a small gap) along the ring.
        let radius = Double(Self.card.width) * 1.08 / (2 * sin(.pi / n))
        let depth = 1300.0
        return ZStack {
            ForEach(Array(items.enumerated()), id: \.offset) { i, id in
                let angle = (Double(i) * 360 / n + rotation).truncatingRemainder(dividingBy: 360)
                let rad = angle * .pi / 180
                let facing = cos(rad)   // 1 facing you, -1 round the back
                let scale = depth / (depth + radius * (1 - facing))
                // Fully there at the front, gone by the time a card is side-on, so no edge-on slabs.
                let opacity = min(1, max(0, (facing - 0.05) / 0.45))
                if opacity > 0 {
                    card(id, number: i + 1, slot: i, facing: facing)
                        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.25)
                        .scaleEffect(scale)
                        .offset(x: sin(rad) * radius * scale, y: (1 - scale) * -60)
                        .opacity(opacity)
                        .zIndex(facing)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func card(_ id: String?, number: Int, slot: Int, facing: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let tones = [Luxe.coral, Luxe.gold, Luxe.emerald, Luxe.rose, Luxe.amber, Luxe.sea]
        return ZStack(alignment: .bottomLeading) {
            if let id {
                PhotoThumbnail(photoID: id, longEdge: 420)
            } else {
                // No photos yet: solid jewel tones, so the ring still reads as a set of prints.
                LinearGradient(colors: [tones[slot % tones.count], Luxe.card], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "photo").font(.system(size: 28, weight: .light)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(stops: [.init(color: .clear, location: 0.55), .init(color: .black.opacity(0.7), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            Text(String(format: "N° %02d", number))
                .font(.system(size: 12, weight: .medium, design: .serif))
                .italic()
                .foregroundStyle(Luxe.champagne)
                .padding(11)
            // Cards turning away sink into the dark.
            Color.black.opacity((1 - facing) * 0.35)
        }
        .frame(width: Self.card.width, height: Self.card.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.45 * facing), radius: 16, y: 12)
    }

    // MARK: Tap to turn

    private func step() {
        stepsFrom = Int(currentSteps(Date()).rounded())
        steps += 1
        steppedAt = Date()
    }

    private func currentSteps(_ now: Date) -> Double {
        guard let at = steppedAt else { return Double(steps) }
        let p = min(1, max(0, now.timeIntervalSince(at) / 0.7))
        let eased = 1 - pow(1 - p, 3)
        return Double(stepsFrom) + (Double(steps) - Double(stepsFrom)) * eased
    }

    /// Each tap brings the next card round to the front with an eased turn.
    private func stepAngle(now: Date, count: Double) -> Double {
        -currentSteps(still ? .distantFuture : now) * 360 / count
    }
}
