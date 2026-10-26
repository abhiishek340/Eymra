import SwiftUI

struct ResultsView: View {
    @Environment(AppModel.self) private var app
    @Bindable var vm: RunViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Pick?
    @State private var shareItems: [URL] = []
    @State private var showShare = false
    @State private var exporting = false
    @Namespace private var zoom

    var body: some View {
        ScrollView {
            if let r = vm.result {
                VStack(alignment: .leading, spacing: 22) {
                    header(r)
                    ForEach(Array(r.picks.enumerated()), id: \.element.id) { index, pick in
                        Button { selected = pick } label: { StoryCard(pick: pick, ratio: r.setRatio) }
                            .buttonStyle(PressableStyle())
                            .matchedTransitionSource(id: pick.photoID, in: zoom)
                            .accessibilityIdentifier("pick-\(pick.position)")
                            .riseIn(delay: 0.25 + Double(min(index, 4)) * 0.09)
                            .scrollTransition(.interactive, axis: .vertical) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.95)
                                    .opacity(phase.isIdentity ? 1 : 0.75)
                            }
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
        .fullScreenCover(item: $selected) { pick in
            PickDetailSheet(vm: vm, pickID: pick.photoID)
                .navigationTransition(.zoom(sourceID: pick.photoID, in: zoom))
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        .overlay { if selected == nil { ToastOverlay(message: $vm.toast) } }
        .edgeSwipeBack { vm.showResults = false }

    }

    private var topBar: some View {
        HStack {
            Button { vm.showResults = false } label: { Image(systemName: "chevron.backward") }
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
            .accessibilityIdentifier("moreMenu")
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    @ViewBuilder private func header(_ r: RunResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(r.title.isEmpty ? String(localized: "Your story") : r.title)
                .font(Theme.title(34))
                .revealOnAppear(duration: 1.3, trigger: r.id)
                .accessibilityIdentifier("storyTitle")
            Text("\(r.picks.count) photos, picked from \(r.stats.photoCount)")
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(Theme.inkSoft)
                .revealOnAppear(delay: 0.5, trigger: r.id)
                .accessibilityIdentifier("resultsTitle")
            HStack(spacing: 6) {
                GlassTag(text: "\(r.stats.sceneCount) \(r.stats.sceneCount == 1 ? String(localized: "place") : String(localized: "places"))", systemImage: "mappin.and.ellipse")
                if r.stats.recognisedMe { GlassTag(text: String(localized: "Found you"), systemImage: "person.crop.circle.badge.checkmark") }
            }
            .riseIn(delay: 0.7)
            let notes = [r.stats.meNote].compactMap { $0 }
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

    private var appName: String {
        PlatformPreset.preset(vm.result?.config.platform ?? vm.platform).appName
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button { Task { exporting = true; await vm.saveAlbum(); exporting = false } } label: {
                Label(exporting ? "Saving…" : "Save to Photos", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.glassPrimary)
            .accessibilityIdentifier("saveAlbum")
            Button { vm.openPlatformApp() } label: {
                Label(String(localized: "Open \(appName)"), systemImage: "arrow.up.forward.app")
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .glassCapsule()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("openPlatformApp")
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
                .overlay {
                    // A gentle parallax: the photo drifts a little against its frame as the story scrolls.
                    PhotoThumbnail(photoID: pick.photoID, longEdge: 1000)
                        .scaleEffect(1.08)
                        .visualEffect { content, proxy in
                            let y = proxy.frame(in: .scrollView).midY
                            return content.offset(y: max(-18, min(18, -(y - 400) * 0.04)))
                        }
                }
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

/// Cards that sink a little under the finger.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.3), value: configuration.isPressed)
    }
}
