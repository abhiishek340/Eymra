import SwiftUI

/// The "working" state, like sorting prints on a desk: your photos pack into a slowly turning ball while the
/// counters roll up. When the run is done they fly out into piles (You, People, Places…), each pile counting
/// what it caught, and then the keepers lift out into a fanned hand just before the story appears.
struct MagicView: View {
    let vm: RunViewModel
    @State private var appeared: [String: Date] = [:]
    @State private var sortStart: Date?
    @State private var countsShown = false
    @State private var gathering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Photos fly to their piles over this long, then the picks gather.
    private static let gatherDelay = 1.6
    private static let tileSide: CGFloat = 30

    private var progress: PipelineProgress? {
        if case .running(let p) = vm.phase { p } else { nil }
    }

    private var stage: PipelineProgress.Stage { progress?.stage ?? .ingest }

    private var piles: [(bucket: SortBucket, count: Int)] {
        vm.sorting.map { SortBucket.counts(in: $0) } ?? []
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                pileCards(in: size)
                TimelineView(.animation(paused: reduceMotion || Theme.stillMotion)) { context in
                    tiles(now: context.date, in: size)
                }
                .accessibilityElement()
                .accessibilityLabel("Looking through your photos")
                VStack(spacing: 0) {
                    counters
                        .padding(.top, 20)
                    Spacer()
                    statusLine
                    Button("Stop") { vm.cancel() }
                        .buttonStyle(.glassSoft)
                        .opacity(sortStart == nil ? 1 : 0)
                        .disabled(sortStart != nil)
                        .accessibilityIdentifier("cancelRun")
                        .padding(.top, 14)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 24)
            }
        }
        .background { WarmMesh().opacity(gathering ? 0.4 : 1).animation(.easeOut(duration: 0.8), value: gathering) }
        .foregroundStyle(Theme.ink)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: stage)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.8), trigger: sortStart != nil)
        .sensoryFeedback(.success, trigger: gathering)
        .onChange(of: vm.pool) { _, ids in
            let now = Date()
            for id in ids where appeared[id] == nil { appeared[id] = now }
        }
        .onChange(of: vm.sorting?.id) { _, id in
            guard id != nil, sortStart == nil else { return }
            sortStart = Date()
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.spring(duration: 0.9, bounce: 0.15)) { countsShown = true }
                try? await Task.sleep(for: .milliseconds(Int(Self.gatherDelay * 1000) - 450))
                withAnimation(.easeOut(duration: 0.5)) { gathering = true }
            }
        }
    }

    // MARK: Counters

    /// Big numbers across the top: photos looked at, then moments and places once the run is sorted.
    private var counters: some View {
        let result = vm.sorting
        let looked = result?.stats.photoCount ?? (stage == .analyse ? progress?.completed ?? 0 : 0)
        let total = progress?.total ?? 0
        return HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                counterLabel(result == nil && total > 0 && stage == .analyse ? String(localized: "Photos, of \(total)") : String(localized: "Photos"))
                Text("\(looked)")
                    .font(Theme.display(46)).monospacedDigit()
                    .foregroundStyle(Theme.ember)
                    .contentTransition(.numericText(value: Double(looked)))
                    .animation(.snappy, value: looked)
            }
            Spacer()
            smallCounter(String(localized: "Moments"), countsShown ? result?.clusters.count ?? 0 : 0)
            smallCounter(String(localized: "Places"), countsShown ? result?.scenes.count ?? 0 : 0)
        }
        .opacity(gathering ? 0.35 : 1)
        .accessibilityElement(children: .combine)
    }

    private func smallCounter(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            counterLabel(label)
            Text("\(value)")
                .font(Theme.display(28)).monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
        }
    }

    private func counterLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(Theme.inkFaint)
    }

    // MARK: Status

    private var statusLine: some View {
        let text = gathering ? String(localized: "Here are your keepers")
            : sortStart != nil ? String(localized: "Sorting your day") : line(stage)
        return Text(text)
            .font(Theme.title(26))
            .multilineTextAlignment(.center)
            .revealOnAppear(duration: 0.9, trigger: text)
            .shimmer(active: sortStart == nil)
            .id(text)
            .frame(height: 70)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("magicLine")
    }

    /// What the user reads: what is happening to their day, never how.
    private func line(_ stage: PipelineProgress.Stage) -> String {
        switch stage {
        case .ingest: String(localized: "Gathering your day")
        case .analyse: String(localized: "Looking at every moment")
        case .scenes: String(localized: "Finding where you went")
        case .clusters: String(localized: "Setting aside the almost-same ones")
        case .scoring: String(localized: "Keeping the best of each moment")
        case .judge: String(localized: "Taking a closer look")
        case .selection, .done: String(localized: "Weaving your story")
        }
    }

    // MARK: Piles

    /// Two columns of piles under the ball. Tiles and cards share this layout, so photos land exactly in them.
    private func pileFrame(_ index: Int, in size: CGSize) -> CGRect {
        let gap: CGFloat = 10, side: CGFloat = 24
        let width = (size.width - side * 2 - gap) / 2, height: CGFloat = 64
        let column = CGFloat(index % 2), row = CGFloat(index / 2)
        return CGRect(x: side + column * (width + gap), y: size.height * 0.27 + row * (height + gap), width: width, height: height)
    }

    private func pileCards(in size: CGSize) -> some View {
        ZStack {
            ForEach(Array(piles.enumerated()), id: \.element.bucket) { i, pile in
                let frame = pileFrame(i, in: size)
                PileCard(bucket: pile.bucket, count: countsShown ? pile.count : 0)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .opacity(sortStart == nil ? 0 : gathering ? 0.3 : 1)
                    .offset(y: sortStart == nil ? 16 : 0)
                    .animation(.spring(duration: 0.6, bounce: 0.2).delay(Double(i) * 0.05), value: sortStart != nil)
                    .animation(.easeOut(duration: 0.5), value: gathering)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Tiles

    private struct Tile: Identifiable {
        var id: String
        var x: CGFloat
        var y: CGFloat
        var scale: CGFloat
        var opacity: Double
        var rotation: Double
        var z: Double
    }

    private func tiles(now: Date, in size: CGSize) -> some View {
        let t = now.timeIntervalSinceReferenceDate
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.42)
        return ZStack {
            SoftGlow(radius: 170)
                .frame(width: 340, height: 340)
                .position(centre)
                .opacity(sortStart == nil ? 1 : 0)
                .animation(.easeOut(duration: 0.6), value: sortStart != nil)
            ForEach(layout(now: now, t: t, centre: centre, size: size)) { tile in
                PhotoThumbnail(photoID: tile.id, longEdge: 160)
                    .frame(width: Self.tileSide, height: Self.tileSide)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.16 * tile.opacity), radius: 3, y: 2)
                    .scaleEffect(tile.scale)
                    .rotationEffect(.degrees(tile.rotation))
                    .opacity(tile.opacity)
                    .position(x: tile.x, y: tile.y)
                    .zIndex(tile.z)
            }
        }
    }

    private func layout(now: Date, t: Double, centre: CGPoint, size: CGSize) -> [Tile] {
        let picks = vm.finalPicks
        var ids = vm.pool
        for id in picks where !ids.contains(id) { ids.append(id) }
        let n = max(1, ids.count)
        // The ball grows with the photos in it, so it always looks packed.
        let radius = min(Double(size.width) * 0.4, 14 * Double(n).squareRoot() + 16)
        let spin = t * 0.22
        let stagger = min(0.02, 0.7 / Double(n))
        let pileIndex = Dictionary(uniqueKeysWithValues: piles.enumerated().map { ($1.bucket, $0) })
        var filled: [SortBucket: Int] = [:]

        return ids.enumerated().map { k, id in
            let seed = Self.seed(id)
            // A sunflower spiral: evenly packed, densest in the middle.
            let r = radius * ((Double(k) + 0.5) / Double(n)).squareRoot()
            let angle = Double(k) * 2.399963 + spin
            let depth = r / radius
            var tile = Tile(id: id,
                            x: centre.x + cos(angle) * r,
                            y: centre.y + sin(angle) * r * 0.94,
                            scale: 1.2 - 0.42 * depth * depth,
                            opacity: 1,
                            rotation: (seed - 0.5) * 36,
                            z: 1 - depth)
            // New arrivals drop in from below.
            let enter = appeared[id].map { ease(min(1, now.timeIntervalSince($0) / 0.7)) } ?? 1
            tile.y += (1 - enter) * 240
            tile.opacity *= enter
            tile.scale *= 0.5 + 0.5 * enter

            guard let start = sortStart, let result = vm.sorting else { return tile }
            // Out of the ball into its pile, one after another.
            let bucket = SortBucket.of(id, in: result)
            let slot = filled[bucket, default: 0]
            filled[bucket] = slot + 1
            let frame = pileFrame(pileIndex[bucket] ?? 0, in: size)
            let tx = frame.minX + 24 + CGFloat(min(slot, 7)) * 14
            let ty = frame.maxY - 18
            let p = ease(min(1, max(0, (now.timeIntervalSince(start) - Double(k) * stagger) / 0.7)))
            tile.x = lerp(tile.x, tx, p)
            tile.y = lerp(tile.y, ty, p)
            tile.scale = lerp(tile.scale, 0.62, p)
            tile.rotation = lerp(tile.rotation, (seed - 0.5) * 16, p)
            tile.z = lerp(tile.z, 2 + Double(slot) * 0.01, p)

            // The keepers lift out of their piles into a fan; everything else stays behind, dimmed.
            let g = ease(min(1, max(0, (now.timeIntervalSince(start) - Self.gatherDelay) / 0.9)))
            guard g > 0 else { return tile }
            if let i = picks.firstIndex(of: id) {
                let mid = Double(picks.count - 1) / 2, offset = Double(i) - mid
                let spread = min(30, (Double(size.width) - 90) / Double(max(1, picks.count)))
                tile.x = lerp(tile.x, centre.x + offset * spread, g)
                tile.y = lerp(tile.y, size.height * 0.4 + abs(offset) * 5, g)
                tile.rotation = lerp(tile.rotation, offset * 5, g)
                tile.scale = lerp(tile.scale, 2.5, g)
                tile.z = 20 + Double(i)
                tile.opacity = 1
            } else {
                tile.opacity *= 1 - 0.75 * g
            }
            return tile
        }
    }

    // MARK: Maths

    /// A stable 0–1 number for a photo ID (not Swift's per-launch randomised hash).
    static func seed(_ id: String) -> Double {
        var h: UInt64 = 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Double(h % 10_000) / 10_000
    }

    private func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * t }
    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

/// One pile: what it holds and how many, with room underneath for the photos that land in it.
private struct PileCard: View {
    let bucket: SortBucket
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: bucket.symbol).font(.system(size: 11, weight: .semibold))
                Text(bucket.title).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(bucket == .you ? Theme.ember : Theme.inkSoft)
                    .contentTransition(.numericText(value: Double(count)))
            }
            .foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

extension SortBucket {
    var title: String {
        switch self {
        case .you: String(localized: "You")
        case .people: String(localized: "People")
        case .places: String(localized: "Places")
        case .food: String(localized: "Food & drinks")
        case .details: String(localized: "Little things")
        case .same: String(localized: "Almost the same")
        case .aside: String(localized: "Set aside")
        }
    }

    var symbol: String {
        switch self {
        case .you: "person.fill"
        case .people: "person.2.fill"
        case .places: "mountain.2.fill"
        case .food: "fork.knife"
        case .details: "camera.macro"
        case .same: "square.stack.fill"
        case .aside: "tray.fill"
        }
    }
}
