import SwiftUI

/// How far the page has scrolled. Only the ring reads it, so scrolling turns the ring without redrawing the page.
@MainActor @Observable
final class GalleryScroll {
    var offset: CGFloat = 0
}

/// Your photos standing on a slowly turning ring, seen from the front: the nearest card faces you, the rest turn
/// away and fade around the back. Scrolling the page spins it; a tap turns it one card on.
struct CircularPhotoGallery: View {
    let ids: [String]
    let scroll: GalleryScroll
    @State private var steps = 0
    @State private var stepsFrom = 0
    @State private var steppedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let card = CGSize(width: 166, height: 226)
    /// Degrees per second when nothing else is moving it.
    private static let drift = 7.0

    private var still: Bool { reduceMotion || Theme.stillMotion }

    /// At least eight cards, so the ring is always full; photos repeat when there are only a few.
    private var slots: [String?] {
        guard !ids.isEmpty else { return Array(repeating: nil, count: 10) }
        return (0..<max(ids.count, 8)).map { ids[$0 % ids.count] }
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
        let rotation = t * Self.drift + Double(scroll.offset) * 0.35 + stepAngle(now: now, count: n)
        let radius = max(Double(size.width) * 0.6, 220)
        let depth = 950.0
        return ZStack {
            ForEach(Array(items.enumerated()), id: \.offset) { i, id in
                let angle = (Double(i) * 360 / n + rotation).truncatingRemainder(dividingBy: 360)
                let rad = angle * .pi / 180
                let facing = cos(rad)   // 1 facing you, -1 round the back
                let scale = depth / (depth + radius * (1 - facing))
                card(id, number: i % max(ids.count, 1) + 1, facing: facing)
                    .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                    .scaleEffect(scale)
                    .offset(x: sin(rad) * radius * scale, y: (1 - scale) * -40)
                    .opacity(max(0.22, (facing + 1) / 2))
                    .zIndex(facing)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func card(_ id: String?, number: Int, facing: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            if let id {
                PhotoThumbnail(photoID: id, longEdge: 500)
            } else {
                LinearGradient(colors: [Luxe.coral.opacity(0.6), Luxe.gold.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.7), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            Text(String(format: "N° %02d", number))
                .font(.system(size: 13, weight: .medium, design: .serif))
                .italic()
                .foregroundStyle(Luxe.champagne)
                .padding(12)
            // Cards turning away sink into the dark.
            Color.black.opacity((1 - facing) * 0.3)
        }
        .frame(width: Self.card.width, height: Self.card.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(facing > 0 ? 0.5 * facing : 0), radius: 18, y: 14)
    }

    // MARK: Tap to turn

    private func step() {
        stepsFrom = Int(currentSteps(Date()).rounded())
        steps += 1
        steppedAt = Date()
    }

    private func currentSteps(_ now: Date) -> Double {
        guard let at = steppedAt else { return Double(steps) }
        let p = min(1, max(0, now.timeIntervalSince(at) / 0.8))
        let eased = 1 - pow(1 - p, 3)
        return Double(stepsFrom) + (Double(steps) - Double(stepsFrom)) * eased
    }

    /// Each tap brings the next card round to the front with an eased turn.
    private func stepAngle(now: Date, count: Double) -> Double {
        -currentSteps(still ? .distantFuture : now) * 360 / count
    }
}
