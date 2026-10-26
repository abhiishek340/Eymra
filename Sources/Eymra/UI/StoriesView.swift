import SwiftUI

/// Past picks, newest first.
struct StoriesView: View {
    @Environment(AppModel.self) private var app
    var refresh = 0
    let open: (RunResult) -> Void
    @State private var runs: [RunResult]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your stories").font(Theme.title(34)).padding(.top, 16)
                    .revealOnAppear(trigger: refresh)
                Text("Every set Eymra picked for you.").font(.system(size: 17, design: .serif)).foregroundStyle(Theme.inkSoft)
                    .revealOnAppear(delay: 0.3, trigger: refresh)
                if let runs, runs.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "book.closed").font(.system(size: 40, weight: .light))
                        Text("Nothing here yet").font(Theme.title(22))
                        Text("Your picked photos will show up here.").foregroundStyle(Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .glassCard()
                }
                ForEach(Array((runs ?? []).enumerated()), id: \.element.id) { index, run in
                    Button { open(run) } label: { StoryRow(run: run) }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("storyRow-\(index)")
                        .riseIn(delay: 0.15 + Double(min(index, 5)) * 0.07)
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content.scaleEffect(phase.isIdentity ? 1 : 0.95).opacity(phase.isIdentity ? 1 : 0.7)
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .dreamScreen()
        .task(id: refresh) { runs = await app.store.recentRuns() }
    }
}

/// A past story as a photo mosaic: one big photo, two small, the title over the image.
struct StoryRow: View {
    let run: RunResult

    var body: some View {
        let ids = run.picks.map(\.photoID)
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                tile(ids.first)
                VStack(spacing: 4) {
                    tile(ids.dropFirst().first)
                    tile(ids.dropFirst(2).first)
                }
                .frame(width: 110)
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 6) {
                Text(run.title.isEmpty ? String(localized: "Your story") : run.title)
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Label("\(run.picks.count)", systemImage: "photo.stack")
                    Label(PlatformPreset.preset(run.config.platform).shortName, systemImage: PlatformPreset.preset(run.config.platform).symbol)
                    Text(run.createdAt, format: .relative(presentation: .named))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
        }
        .padding(6)
        .glassCard(cornerRadius: 30)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func tile(_ id: String?) -> some View {
        if let id {
            PhotoThumbnail(photoID: id, longEdge: 500)
        } else {
            Rectangle().fill(Theme.ink.opacity(0.06))
        }
    }
}
