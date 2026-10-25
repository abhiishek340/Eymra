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

struct StoryRow: View {
    let run: RunResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(run.picks.prefix(4)) { pick in
                    PhotoThumbnail(photoID: pick.photoID, longEdge: 260)
                        .aspectRatio(0.8, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(run.title.isEmpty ? String(localized: "Your story") : run.title)
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                Text("\(run.picks.count) photos · \(PlatformPreset.preset(run.config.platform).name) · \(run.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .glassCard(cornerRadius: 26)
    }
}
