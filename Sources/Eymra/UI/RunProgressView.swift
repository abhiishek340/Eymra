import SwiftUI

struct RunProgressView: View {
    let vm: RunViewModel

    private var progress: PipelineProgress? {
        if case .running(let p) = vm.phase { p } else { nil }
    }

    private var stages: [PipelineProgress.Stage] {
        PipelineProgress.Stage.allCases.filter { $0 != .done && ($0 != .judge || vm.app.settings.judgeEnabled) }
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating)
            if let p = progress {
                VStack(spacing: 10) {
                    Text(p.stage.title).font(.title2.bold())
                    if p.total > 0 {
                        ProgressView(value: p.fraction)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 280)
                        Text(p.caption)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("progressCaption")
                    } else {
                        ProgressView()
                    }
                    if p.inCloud > 0 {
                        Text("\(p.inCloud) photos are in iCloud and weren't downloaded")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(stages, id: \.self) { stage in
                        let state = Self.state(of: stage, current: p.stage)
                        HStack(spacing: 10) {
                            Image(systemName: state == .done ? "checkmark.circle.fill" : state == .active ? "circle.dotted" : "circle")
                                .foregroundStyle(state == .done ? .green : state == .active ? .accentColor : .secondary)
                            Text(stage.title)
                                .foregroundStyle(state == .pending ? .secondary : .primary)
                        }
                        .font(.callout)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            Spacer()
            Button(role: .cancel) {
                vm.cancel()
            } label: {
                Text("Cancel").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("cancelRun")
        }
        .padding(24)
        .interactiveDismissDisabled()
    }

    enum StageState { case done, active, pending }

    static func state(of stage: PipelineProgress.Stage, current: PipelineProgress.Stage) -> StageState {
        let all = PipelineProgress.Stage.allCases
        guard let a = all.firstIndex(of: stage), let b = all.firstIndex(of: current) else { return .pending }
        return a < b ? .done : a == b ? .active : .pending
    }
}
