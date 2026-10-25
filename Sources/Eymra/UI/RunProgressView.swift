import SwiftUI

struct RunProgressView: View {
    let vm: RunViewModel
    @State private var breathe = false

    private var progress: PipelineProgress? {
        if case .running(let p) = vm.phase { p } else { nil }
    }

    /// Friendly lines for each step.
    private func line(_ stage: PipelineProgress.Stage) -> String {
        switch stage {
        case .ingest: String(localized: "Gathering your photos…")
        case .analyse: String(localized: "Getting to know each photo…")
        case .scenes: String(localized: "Finding the places you went…")
        case .clusters: String(localized: "Spotting the almost-same shots…")
        case .scoring: String(localized: "Picking the best of each moment…")
        case .judge: String(localized: "Asking Claude for a second look…")
        case .selection: String(localized: "Putting your story together…")
        case .done: String(localized: "Here it comes…")
        }
    }

    var body: some View {
        VStack(spacing: 34) {
            Spacer()
            ZStack {
                Circle().fill(.white.opacity(0.35)).frame(width: 190, height: 190).blur(radius: 30)
                    .scaleEffect(breathe ? 1.15 : 0.9)
                Circle().fill(.white.opacity(0.25)).frame(width: 120, height: 120).blur(radius: 12)
                    .scaleEffect(breathe ? 0.95 : 1.1)
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .light))
                    .symbolEffect(.pulse, options: .repeating)
            }
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathe)
            if let p = progress {
                VStack(spacing: 16) {
                    Text(line(p.stage))
                        .font(Theme.title(26))
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                        .animation(.easeInOut, value: p.stage)
                    if p.total > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.ink.opacity(0.12))
                                Capsule().fill(Theme.ink.opacity(0.75))
                                    .frame(width: max(8, geo.size.width * p.fraction))
                                    .animation(.easeOut(duration: 0.3), value: p.fraction)
                            }
                        }
                        .frame(width: 240, height: 6)
                        Text(p.stage == .judge
                             ? String(localized: "\(p.completed) of \(p.total) batches")
                             : String(localized: "\(p.completed) of \(p.total) photos"))
                            .font(.system(size: 14).monospacedDigit())
                            .foregroundStyle(Theme.inkSoft)
                            .accessibilityIdentifier("progressCaption")
                    }
                    if p.inCloud > 0 {
                        Text("\(p.inCloud) photos are still in iCloud, so we skipped them")
                            .font(.footnote).foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(26)
                .frame(maxWidth: .infinity)
                .glassCard()
            }
            Spacer()
            Button("Stop") { vm.cancel() }
                .buttonStyle(.glassSoft)
                .accessibilityIdentifier("cancelRun")
        }
        .padding(24)
        .foregroundStyle(Theme.ink)
        .background(DreamBackground())
        .interactiveDismissDisabled()
        .onAppear { breathe = true }
    }
}
