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

                        VStack(alignment: .leading, spacing: 12) {
                            DreamHeading(text: String(localized: "Why we picked it"))
                            meter(String(localized: "Sharp and well lit"), pick.score.technical)
                            meter(String(localized: "Looks good"), pick.score.aesthetic)
                            meter(String(localized: "Nicely framed"), pick.score.composition)
                            if let p = pick.score.people { meter(String(localized: "Faces"), p) }
                            if let j = pick.judge { meter(String(localized: "Overall feel"), j.score) }
                        }
                        .padding(18)
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
        return ranked.filter { !picked.contains($0) && r.scores[$0] != nil && !(r.excluded[$0]?.isHardReject ?? false) }
    }

    private func meter(_ title: String, _ value: Float) -> some View {
        HStack {
            Text(title).font(.system(size: 15))
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.12))
                    Capsule().fill(Theme.ink.opacity(0.7)).frame(width: geo.size.width * CGFloat(max(0.04, value)))
                }
            }
            .frame(width: 110, height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(Int(value * 100)) out of 100")
    }
}
