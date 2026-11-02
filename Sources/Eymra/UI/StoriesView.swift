import SwiftUI

/// Past picks, newest first, on the same evening stage as Create: each story a framed mosaic of its photos.
struct StoriesView: View {
    @Environment(AppModel.self) private var app
    var refresh = 0
    let open: (RunResult) -> Void
    @State private var runs: [RunResult]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let runs, runs.isEmpty {
                    emptyState
                }
                ForEach(Array((runs ?? []).enumerated()), id: \.element.id) { index, run in
                    Button { open(run) } label: { StoryRow(run: run, number: index + 1) }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("storyRow-\(index)")
                        .riseIn(delay: 0.15 + Double(min(index, 5)) * 0.07)
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content.scaleEffect(phase.isIdentity ? 1 : 0.95).opacity(phase.isIdentity ? 1 : 0.6)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .foregroundStyle(Luxe.text)
        .task(id: refresh) { runs = await app.store.recentRuns() }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(runs.map { $0.count == 1 ? String(localized: "1 story") : String(localized: "\($0.count) stories") } ?? " ")
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1.8)
                    .foregroundStyle(Luxe.gold)
                    .contentTransition(.numericText())
                Text("Your stories")
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                    .revealOnAppear(trigger: refresh)
                Text("Every set Eymra picked for you.")
                    .font(.system(size: 16, design: .serif))
                    .italic()
                    .foregroundStyle(Luxe.soft)
                    .revealOnAppear(delay: 0.3, trigger: refresh)
            }
            Spacer()
            IconBadge(symbol: "books.vertical.fill", color: Luxe.gold, size: 44)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            IconBadge(symbol: "book.closed.fill", color: Luxe.honey, size: 56)
            Text("Nothing here yet").font(.system(size: 22, weight: .semibold, design: .serif))
            Text("Your picked photos will show up here.").foregroundStyle(Luxe.soft)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Luxe.card.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Luxe.line, lineWidth: 1))
    }
}

/// A past story as a framed mosaic: one big photo, two small, the title and its details over the image.
struct StoryRow: View {
    let run: RunResult
    var number = 1

    var body: some View {
        let ids = run.picks.map(\.photoID)
        let platform = PlatformPreset.preset(run.config.platform)
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                tile(ids.first)
                VStack(spacing: 4) {
                    tile(ids.dropFirst().first)
                    tile(ids.dropFirst(2).first)
                }
                .frame(width: 112)
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 10) {
                Text(String(format: "N° %02d", number))
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(Luxe.champagne)
                Text(run.title.isEmpty ? String(localized: "Your story") : run.title)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    chip("\(run.picks.count)", symbol: "photo.stack.fill", color: Luxe.coral)
                    chip(platform.shortName, symbol: platform.symbol, color: Luxe.amber)
                    chip(run.createdAt.formatted(.relative(presentation: .named)), symbol: "clock.fill", color: Luxe.emerald)
                }
            }
            .padding(16)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Luxe.card.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Luxe.gold.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 12)
        .accessibilityElement(children: .combine)
    }

    /// A small glass pill with a coloured icon.
    private func chip(_ text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }

    @ViewBuilder private func tile(_ id: String?) -> some View {
        if let id {
            PhotoThumbnail(photoID: id, longEdge: 500)
        } else {
            Rectangle().fill(Color.white.opacity(0.05))
        }
    }
}
