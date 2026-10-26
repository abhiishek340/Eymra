import SwiftUI

/// The "working" state: the user's own photos orbit a breathing light while Eymra looks through them,
/// then the chosen ones gather into a fanned hand just before the story appears.
struct MagicView: View {
    let vm: RunViewModel
    @State private var appeared: [String: Date] = [:]
    @State private var gatherStart: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: PipelineProgress? {
        if case .running(let p) = vm.phase { p } else { nil }
    }

    private var stage: PipelineProgress.Stage { progress?.stage ?? .ingest }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            orbit
                .frame(height: 400)
            Spacer(minLength: 20)
            VStack(spacing: 10) {
                Text(line(stage))
                    .font(Theme.title(26))
                    .multilineTextAlignment(.center)
                    .revealOnAppear(duration: 0.9, trigger: stage)
                    .shimmer(active: gatherStart == nil)
                    .id(stage)
                if let p = progress, p.stage == .analyse, p.total > 0 {
                    Text("\(p.completed) of \(p.total)")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.inkFaint)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: p.completed)
                }
            }
            .frame(height: 90)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line(stage))
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("magicLine")
            Spacer(minLength: 20)
            Button("Stop") { vm.cancel() }
                .buttonStyle(.glassSoft)
                .opacity(gatherStart == nil ? 1 : 0)
                .disabled(gatherStart != nil)
                .accessibilityIdentifier("cancelRun")
                .padding(.bottom, 30)
        }
        .padding(.horizontal, 24)
        .foregroundStyle(Theme.ink)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: stage)
        .onChange(of: vm.pool) { _, ids in
            let now = Date()
            for id in ids where appeared[id] == nil { appeared[id] = now }
        }
        .onChange(of: vm.finalPicks) { _, picks in
            if !picks.isEmpty && gatherStart == nil { gatherStart = Date() }
        }
    }

    // MARK: Orbit

    private var orbit: some View {
        TimelineView(.animation(paused: reduceMotion || Theme.stillMotion)) { context in
            let now = context.date
            let t = now.timeIntervalSinceReferenceDate
            let gather = gatherStart.map { ease(min(1, now.timeIntervalSince($0) / 1.0)) } ?? 0
            GeometryReader { geo in
                let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    glow(t: t, gather: gather)
                        .position(centre)
                    ForEach(cards(now: now, t: t, gather: gather), id: \.id) { card in
                        PhotoThumbnail(photoID: card.id, longEdge: 240)
                            .frame(width: 70, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1))
                            .shadow(color: .black.opacity(0.18 * card.opacity), radius: 10, y: 6)
                            .scaleEffect(card.scale)
                            .rotationEffect(.degrees(card.rotation))
                            .opacity(card.opacity)
                            .position(x: centre.x + card.x, y: centre.y + card.y)
                            .zIndex(card.z)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Looking through your photos")
    }

    private struct Card: Identifiable {
        var id: String
        var x: CGFloat
        var y: CGFloat
        var scale: CGFloat
        var opacity: Double
        var rotation: Double
        var z: Double
    }

    private func cards(now: Date, t: Double, gather: Double) -> [Card] {
        let picks = vm.finalPicks
        var ids = vm.pool
        for id in picks where !ids.contains(id) { ids.append(id) }
        return ids.map { id in
            let seed = Self.seed(id)
            // Stable place on a tilted ring, so new arrivals never make others jump.
            let angle = seed * 2 * .pi + t * 0.32
            let radius = 120 + 55 * Self.seed(id + "r")
            let depth = sin(angle)                          // -1 back … 1 front
            let enter = appeared[id].map { ease(min(1, now.timeIntervalSince($0) / 0.8)) } ?? 1
            var card = Card(id: id,
                            x: cos(angle) * radius,
                            y: depth * radius * 0.36 - 10,
                            scale: (0.62 + 0.38 * (depth + 1) / 2) * (0.6 + 0.4 * enter),
                            opacity: (0.35 + 0.65 * (depth + 1) / 2) * enter,
                            rotation: cos(angle) * -8,
                            z: depth)
            // Gathering: picks fan out at the centre, everything else fades away.
            if gather > 0 {
                if let k = picks.firstIndex(of: id) {
                    let mid = Double(picks.count - 1) / 2, offset = Double(k) - mid
                    let spread = min(26, 220 / Double(max(1, picks.count)))
                    card.x = lerp(card.x, offset * spread, gather)
                    card.y = lerp(card.y, abs(offset) * 4 + 6, gather)
                    card.rotation = lerp(card.rotation, offset * 5, gather)
                    card.scale = lerp(card.scale, 1.15, gather)
                    card.opacity = lerp(card.opacity, 1, gather)
                    card.z = lerp(card.z, 10 + Double(k), gather)
                } else {
                    card.opacity *= 1 - gather
                    card.scale *= 1 - 0.4 * gather
                }
            }
            return card
        }
    }

    // MARK: Light

    private func glow(t: Double, gather: Double) -> some View {
        let breathe = reduceMotion || Theme.stillMotion ? 1 : 1 + 0.06 * sin(t * 1.4)
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.85), .white.opacity(0.25), .white.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 120))
                .frame(width: 240, height: 240)
                .scaleEffect(breathe * (1 + 0.5 * gather))
            Circle()
                .trim(from: 0, to: overallProgress)
                .stroke(Theme.ember, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 76, height: 76)
                .opacity(1 - gather)
                .animation(.smooth(duration: 0.6), value: overallProgress)
            Circle()
                .stroke(Theme.ink.opacity(0.1), lineWidth: 2.5)
                .frame(width: 76, height: 76)
                .opacity(1 - gather)
        }
    }

    /// One number for the whole job, weighted by how long each part usually takes.
    private var overallProgress: Double {
        guard let p = progress else { return 0.02 }
        switch p.stage {
        case .ingest: return 0.04
        case .analyse: return 0.05 + 0.7 * p.fraction
        case .scenes: return 0.78
        case .clusters: return 0.82
        case .scoring: return 0.86
        case .judge: return 0.88 + 0.08 * p.fraction
        case .selection: return 0.98
        case .done: return 1
        }
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
