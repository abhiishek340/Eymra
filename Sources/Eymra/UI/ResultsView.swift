import SwiftUI

struct ResultsView: View {
    @Environment(AppModel.self) private var app
    @Bindable var vm: RunViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Pick?
    @State private var shareItems: [URL] = []
    @State private var showShare = false
    @State private var exporting = false

    var body: some View {
        ScrollView {
            if let r = vm.result {
                VStack(alignment: .leading, spacing: 22) {
                    header(r)
                    ForEach(r.picks) { pick in
                        Button { selected = pick } label: { StoryCard(pick: pick, ratio: r.setRatio) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("pick-\(pick.position)")
                    }
                    ExcludedSection(vm: vm, result: r)
                }
                .padding(.horizontal, 20)
                .padding(.top, 70)
                .padding(.bottom, 130)
            }
        }
        .scrollIndicators(.hidden)
        .dreamScreen()
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { ZStack(alignment: .top) { BottomFade(height: 110, edge: .top); topBar } }
        .overlay(alignment: .bottom) { ZStack(alignment: .bottom) { BottomFade(height: 140); actionBar } }
        .sheet(item: $selected) { pick in
            PickDetailSheet(vm: vm, pickID: pick.photoID)
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        .overlay(alignment: .bottom) {
            if let toast = vm.toast {
                Text(toast)
                    .font(.system(size: 15, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .glassCapsule(tint: .white.opacity(0.5), interactive: false)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2.8))
                        withAnimation { vm.toast = nil }
                    }
                    .accessibilityIdentifier("toast")
            }
        }
        .animation(.spring(duration: 0.4), value: vm.toast)
    }

    private var topBar: some View {
        HStack {
            Button { vm.showResults = false } label: { Image(systemName: "chevron.left") }
                .buttonStyle(RoundGlassButtonStyle())
                .accessibilityLabel("Back")
                .accessibilityIdentifier("resultsBack")
            Spacer()
            Menu {
                Button { vm.rerun() } label: { Label("Pick again (keep the ones I locked)", systemImage: "arrow.clockwise") }
                Button { Task { exporting = true; shareItems = await vm.shareFiles(); exporting = false; showShare = !shareItems.isEmpty } } label: {
                    Label("Share all", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .glassCapsule()
            }
            .accessibilityLabel("More")
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    @ViewBuilder private func header(_ r: RunResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(r.title.isEmpty ? String(localized: "Your story") : r.title)
                .font(Theme.title(34))
                .accessibilityIdentifier("storyTitle")
            Text("\(r.picks.count) photos, picked from \(r.stats.photoCount)")
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(Theme.inkSoft)
                .accessibilityIdentifier("resultsTitle")
            HStack(spacing: 6) {
                if r.stats.judgeUsed {
                    GlassTag(text: String(localized: "Claude helped"), systemImage: "sparkles")
                } else {
                    GlassTag(text: String(localized: "Picked on your phone"), systemImage: "iphone")
                }
                if r.stats.recognisedMe { GlassTag(text: String(localized: "Found you"), systemImage: "person.crop.circle.badge.checkmark") }
                GlassTag(text: "\(r.stats.sceneCount) \(r.stats.sceneCount == 1 ? String(localized: "place") : String(localized: "places"))", systemImage: "mappin")
            }
            let notes = [r.stats.judgeNote, r.stats.meNote].compactMap { $0 } + r.stats.relaxations
                + (r.stats.shortfall > 0 ? [String(localized: "We only found \(r.picks.count) different moments worth posting, so you have \(r.picks.count) instead of \(r.config.count).")] : [])
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(notes, id: \.self) { Text($0) }
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 18)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button { Task { exporting = true; await vm.saveAlbum(); exporting = false } } label: {
                Label(exporting ? "Saving…" : "Save to Photos", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.glassPrimary)
            .accessibilityIdentifier("saveAlbum")
            Button { vm.openPlatformApp() } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 56, height: 56)
                    .glassCapsule()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(vm.result.map { PlatformPreset.preset($0.config.platform).name } ?? "")")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .disabled(exporting)
    }
}

/// One photo in the story: big image, its number, why it was picked.
struct StoryCard: View {
    let pick: Pick
    let ratio: AspectRatio

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Color.clear
                .aspectRatio(ratio.value, contentMode: .fit)
                .overlay { PhotoThumbnail(photoID: pick.photoID, longEdge: 1000) }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text("\(pick.position)")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 34, height: 34)
                        .glassCapsule(interactive: false)
                        .padding(10)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 6) {
                        if let role = pick.role { GlassTag(text: Explanations.roleName(role)) }
                        if pick.isLocked {
                            Image(systemName: "lock.fill").font(.system(size: 12))
                                .frame(width: 30, height: 30).glassCapsule(interactive: false)
                        }
                    }
                    .padding(10)
                }
            Text(pick.reason)
                .font(.system(size: 17, weight: .medium, design: .serif))
                .lineLimit(2)
                .padding(.horizontal, 4)
            HStack(spacing: 6) {
                GlassTag(text: Explanations.categoryName(pick.category), systemImage: pick.category.symbol)
                if pick.clusterSize > 1 { GlassTag(text: String(localized: "best of \(pick.clusterSize)")) }
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .glassCard(cornerRadius: 30)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Photo \(pick.position): \(pick.reason)")
    }
}
