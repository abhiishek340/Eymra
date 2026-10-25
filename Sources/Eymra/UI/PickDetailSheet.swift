import SwiftUI

struct PickDetailSheet: View {
    @Bindable var vm: RunViewModel
    let pickID: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirmHide = false

    private var pick: Pick? { vm.result?.picks.first { $0.photoID == pickID } }
    private var cluster: Cluster? { vm.result?.cluster(containing: pickID) }

    var body: some View {
        NavigationStack {
            if let pick, let r = vm.result {
                List {
                    Section {
                        Color.clear
                            .aspectRatio(r.setRatio.value, contentMode: .fit)
                            .overlay { PhotoThumbnail(photoID: pick.photoID, longEdge: 1200) }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowInsets(EdgeInsets())
                        Text(pick.reason).font(.headline)
                        if pick.clusterSize > 1 && !pick.reason.contains("\(pick.clusterSize)") {
                            Text("Best of \(pick.clusterSize) near-identical shots").foregroundStyle(.secondary)
                        }
                    }

                    let others = runnerUps(r)
                    if !others.isEmpty {
                        Section("Runner-ups – tap to swap") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(others, id: \.self) { id in
                                        Button {
                                            vm.swap(pickID, with: id)
                                            dismiss()
                                        } label: {
                                            VStack(spacing: 4) {
                                                PhotoThumbnail(photoID: id)
                                                    .frame(width: 96, height: 120)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                Text(String(format: "Q %.2f", r.scores[id]?.quality ?? 0))
                                                    .font(.caption2.monospacedDigit())
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Swap in runner-up")
                                    }
                                }
                            }
                        }
                    }

                    Section("Why it scored") {
                        scoreRow("Quality", pick.score.quality)
                        scoreRow("Technical (sharpness, exposure, horizon)", pick.score.technical)
                        scoreRow("Aesthetic", pick.score.aesthetic)
                        scoreRow("Composition", pick.score.composition)
                        if let p = pick.score.people { scoreRow("Faces", p) }
                        if let j = pick.judge {
                            scoreRow("AI Judge", j.score)
                        }
                        LabeledContent("Kind", value: Explanations.categoryName(pick.category))
                    }

                    Section {
                        Button {
                            vm.toggleLock(pickID)
                        } label: {
                            Label(pick.isLocked ? "Unlock" : "Lock (keep on re-run)", systemImage: pick.isLocked ? "lock.open" : "lock")
                        }
                        .accessibilityIdentifier("lockButton")
                        Button {
                            Task { await vm.copyForStories(pickID) }
                        } label: {
                            Label("Copy for Stories (9:16)", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            confirmHide = true
                        } label: {
                            Label("Hide this photo for good", systemImage: "eye.slash")
                        }
                    }
                }
                .accessibilityIdentifier("pickDetailList")
                .navigationTitle("Pick \(pick.position)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .confirmationDialog("Hide this photo? It won't be picked again until you clear hidden photos in Settings.",
                                    isPresented: $confirmHide, titleVisibility: .visible) {
                    Button("Hide and re-run", role: .destructive) {
                        vm.hide(pickID)
                        dismiss()
                    }
                }
            } else {
                ContentUnavailableView("Pick removed", systemImage: "photo")
            }
        }
        .presentationDetents([.large])
    }

    private func runnerUps(_ r: RunResult) -> [String] {
        guard let c = cluster else { return [] }
        let ranked = c.runnerUpIDs + c.memberIDs.filter { $0 != c.winnerID && !c.runnerUpIDs.contains($0) }
        let picked = Set(r.picks.map(\.photoID))
        // Hard rejects (blurry, eyes closed, too dark…) stay in "Everything else", not in the swap strip.
        return ranked.filter { !picked.contains($0) && r.scores[$0] != nil && !(r.excluded[$0]?.isHardReject ?? false) }
    }

    private func scoreRow(_ title: LocalizedStringKey, _ value: Float) -> some View {
        LabeledContent {
            HStack {
                ProgressView(value: Double(value)).frame(width: 80)
                Text(String(format: "%.2f", value)).monospacedDigit()
            }
        } label: {
            Text(title)
        }
    }
}
