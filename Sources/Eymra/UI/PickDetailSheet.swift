import SwiftUI

struct PickDetailSheet: View {
    @Bindable var vm: RunViewModel
    let pickID: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirmHide = false
    @GestureState private var pull: CGFloat = 0

    private var pick: Pick? { vm.result?.picks.first { $0.photoID == pickID } }
    private var cluster: Cluster? { vm.result?.cluster(containing: pickID) }

    var body: some View {
        ZStack(alignment: .top) {
            DreamBackground(animated: false)
            if let pick, let r = vm.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Color.clear
                            .aspectRatio(r.setRatio.value, contentMode: .fit)
                            .overlay { PhotoThumbnail(photoID: pick.photoID, longEdge: 1400) }
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            // Pull the photo down to close.
                            .offset(y: max(0, pull) * 0.5)
                            .scaleEffect(1 - min(0.12, max(0, pull) / 1500))
                            .gesture(
                                DragGesture(minimumDistance: 10)
                                    .updating($pull) { value, state, _ in state = value.translation.height }
                                    .onEnded { value in
                                        if value.translation.height > 110 || value.predictedEndTranslation.height > 260 { dismiss() }
                                    }
                            )
                            .animation(.interactiveSpring(duration: 0.3), value: pull)
                            .accessibilityElement()
                            .accessibilityLabel("Photo \(pick.position)")
                            .accessibilityHint("Swipe down to close")
                            .accessibilityAddTraits(.isImage)
                            .accessibilityIdentifier("detailPhoto")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Photo \(pick.position)").font(.system(size: 13, weight: .medium)).textCase(.uppercase).foregroundStyle(Theme.inkSoft)
                            Text(pick.reason).font(Theme.title(24))
                                .revealOnAppear(delay: 0.25)
                        }

                        let others = runnerUps(r)
                        if !others.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                DreamHeading(text: String(localized: "Prefer another one?"))
                                Text("These are almost the same shot. Tap one to use it instead.")
                                    .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(others, id: \.self) { id in
                                            Button {
                                                vm.swap(pickID, with: id)
                                                dismiss()
                                            } label: {
                                                PhotoThumbnail(photoID: id)
                                                    .frame(width: 92, height: 116)
                                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Use this one instead")
                                            .accessibilityIdentifier("runnerUp")
                                        }
                                    }
                                }
                            }
                            .padding(18)
                            .glassCard()
                        }

                        HStack(spacing: 0) {
                            ScoreRing(value: pick.score.technical, symbol: "camera.aperture", label: String(localized: "Sharp"))
                            ScoreRing(value: pick.score.aesthetic, symbol: "sun.max", label: String(localized: "Looks"))
                            ScoreRing(value: pick.score.composition, symbol: "viewfinder", label: String(localized: "Framing"))
                            if let p = pick.score.people {
                                ScoreRing(value: p, symbol: "face.smiling", label: String(localized: "Faces"))
                            } else if let j = pick.judge {
                                ScoreRing(value: j.score, symbol: "heart", label: String(localized: "Feel"))
                            }
                        }
                        .padding(.vertical, 18)
                        .glassCard()

                        VStack(spacing: 10) {
                            Button {
                                vm.toggleLock(pickID)
                            } label: {
                                Label(pick.isLocked ? "Unlock" : "Keep this one", systemImage: pick.isLocked ? "lock.open" : "lock")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassSoft)
                            .accessibilityIdentifier("lockButton")
                            Button {
                                Task { await vm.copyForStories(pickID) }
                            } label: {
                                Label("Copy for my Story", systemImage: "rectangle.portrait.on.rectangle.portrait")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassSoft)
                            .accessibilityIdentifier("copyForStory")
                            Button {
                                confirmHide = true
                            } label: {
                                Label("Never show this photo", systemImage: "eye.slash").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassSoft)
                            .accessibilityIdentifier("hidePhoto")
                        }
                        if pick.isLocked {
                            Text("Kept photos stay when you pick again.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .padding(20)
                    .padding(.top, 50)
                }
                .scrollIndicators(.hidden)
            } else {
                ContentUnavailableView("This photo was removed", systemImage: "photo")
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glassSoft)
                    .accessibilityIdentifier("detailDone")
            }
            .padding(16)
        }
        .foregroundStyle(Theme.ink)
        .overlay { ToastOverlay(message: $vm.toast, bottomPadding: 40) }
        .confirmationDialog("Hide this photo? Eymra won't pick it again. You can undo this in the You tab.",
                            isPresented: $confirmHide, titleVisibility: .visible) {
            Button("Hide and pick again", role: .destructive) {
                vm.hide(pickID)
                dismiss()
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(36)
    }

    private func runnerUps(_ r: RunResult) -> [String] {
        guard let c = cluster else { return [] }
        let ranked = c.runnerUpIDs + c.memberIDs.filter { $0 != c.winnerID && !c.runnerUpIDs.contains($0) }
        let picked = Set(r.picks.map(\.photoID))
        // Hard rejects (blurry, eyes closed, too dark…) stay in "Other photos", not in the swap strip.
        // Never offer a photo of someone else as "the same shot" of you, or the other way round.
        let withMe = r.scores[pickID]?.withMe
        return ranked.filter { id in
            guard !picked.contains(id), let score = r.scores[id], !(r.excluded[id]?.isHardReject ?? false) else { return false }
            if let withMe, let other = score.withMe, other != withMe { return false }
            return true
        }
    }

}

/// A small ring that fills to the score, with an icon in the middle.
struct ScoreRing: View {
    let value: Float
    let symbol: String
    let label: String
    @State private var shown: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Theme.ink.opacity(0.1), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol).font(.system(size: 16, weight: .medium))
            }
            .frame(width: 54, height: 54)
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .onAppear { withAnimation(.smooth(duration: 1.0).delay(0.3)) { shown = Double(max(0.04, value)) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Int(value * 100)) out of 100")
    }
}
