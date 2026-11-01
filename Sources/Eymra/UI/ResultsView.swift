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
    @State private var checkingFaces = false

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
        .sheet(isPresented: $checkingFaces) {
            FaceCheckSheet(faces: vm.reviewFaces) { me, notMe in vm.answerFaces(me: me, notMe: notMe) }
        }
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
                    .contentShape(Circle())
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
            StoryGlance(result: r)
                .riseIn(delay: 0.35)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.picks.count) photos, picked from \(r.stats.photoCount)")
                .accessibilityValue(r.stats.recognisedMe ? String(localized: "Found you") : "")
                .accessibilityIdentifier("resultsTitle")
            let unsure = vm.unsureFaces
            if !unsure.isEmpty {
                FaceCheckCard(faces: unsure) { checkingFaces = true }
                    .riseIn(delay: 0.45)
            }
            if r.picks.contains(where: { $0.score.matchedFace != nil }) {
                Button { checkingFaces = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 15, weight: .semibold))
                        Text("Check who is in these photos")
                        Image(systemName: "chevron.forward").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.inkFaint)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Capsule().fill(Theme.surface))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .riseIn(delay: 0.48)
                .accessibilityLabel("Check who is in these photos")
                .accessibilityIdentifier("reviewMatchedFaces")
            }
            DayRibbon(result: r)
                .riseIn(delay: 0.5)
            MixBar(picks: r.picks)
                .riseIn(delay: 0.6)
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
                    .contentShape(Capsule())
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
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.surface))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                        .padding(12)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 6) {
                        if let role = pick.role {
                            Text(Explanations.roleName(role))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(Theme.ember))
                                .shadow(color: Theme.ember.opacity(0.35), radius: 6, y: 3)
                        }
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
            HStack(spacing: 10) {
                Image(systemName: pick.category.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(pick.category.tone))
                    .accessibilityLabel(Explanations.categoryName(pick.category))
                if pick.clusterSize > 1 {
                    Label("\(pick.clusterSize)", systemImage: "square.stack.3d.down.right.fill")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.inkSoft)
                        .accessibilityLabel(String(localized: "best of \(pick.clusterSize)"))
                }
                Spacer()
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

// MARK: - At a glance

/// "40 → 10": how many photos went in, how many came out, where, and whether you were found.
struct StoryGlance: View {
    let result: RunResult
    /// The numbers roll up from zero once, when the story first shows.
    @State private var counted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(counted ? result.stats.photoCount : 0)")
                    .font(Theme.display(30)).monospacedDigit()
                    .foregroundStyle(Theme.inkFaint)
                    .contentTransition(.numericText(value: Double(counted ? result.stats.photoCount : 0)))
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                    .offset(x: counted ? 0 : -6)
                    .opacity(counted ? 1 : 0)
                Text("\(counted ? result.picks.count : 0)")
                    .font(Theme.display(30)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(counted ? result.picks.count : 0)))
            }
            Spacer()
            glanceStat(symbol: "mappin.and.ellipse", value: "\(result.stats.sceneCount)")
            if result.stats.recognisedMe {
                glanceStat(symbol: "person.crop.circle.badge.checkmark", value: "\(result.picks.filter { result.scores[$0.photoID]?.withMe == true }.count)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 22)
        .onAppear {
            if reduceMotion { counted = true; return }
            withAnimation(.spring(duration: 1.1, bounce: 0.1).delay(0.5)) { counted = true }
        }
    }

    private func glanceStat(symbol: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            Text(value).font(.system(size: 16, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.ink.opacity(0.07)))
    }
}

/// The day as a line: one dot per place you went, in time order, with your picks floating above it.
struct DayRibbon: View {
    let result: RunResult
    @State private var landed = false

    var body: some View {
        let scenes = result.scenes
        let first = scenes.first?.start ?? Date(), last = scenes.last?.end ?? Date()
        let span = max(1, last.timeIntervalSince(first))
        GeometryReader { geo in
            // Keep dots and photos inside the card: photos are 34 pt wide and stack 9 pt to the right.
            let w = geo.size.width - 64
            let x = { (date: Date) in 26 + w * CGFloat(date.timeIntervalSince(first) / span) }
            ZStack(alignment: .topLeading) {
                Capsule().fill(Theme.ink.opacity(0.12)).frame(height: 3).offset(y: 70)
                ForEach(scenes) { scene in
                    let mid = scene.start.addingTimeInterval(scene.end.timeIntervalSince(scene.start) / 2)
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 9, height: 9)
                        .position(x: x(mid), y: 71.5)
                }
                ForEach(Array(result.picks.enumerated()), id: \.element.id) { i, pick in
                    if let scene = result.scenes.first(where: { $0.photoIDs.contains(pick.photoID) }) {
                        let mid = scene.start.addingTimeInterval(scene.end.timeIntervalSince(scene.start) / 2)
                        let stack = result.picks.prefix(i).filter { p in scene.photoIDs.contains(p.photoID) }.count
                        PhotoThumbnail(photoID: pick.photoID, longEdge: 160)
                            .frame(width: 34, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white, lineWidth: 1.5))
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                            .rotationEffect(.degrees(Double(stack) * 7 - 4))
                            .scaleEffect(landed ? 1 : 0.6)
                            .opacity(landed ? 1 : 0)
                            .position(x: x(mid) + CGFloat(stack) * 9, y: (landed ? 36 : 6) - CGFloat(stack) * 3)
                            .animation(.spring(duration: 0.6, bounce: 0.35).delay(0.65 + Double(min(i, 12)) * 0.05), value: landed)
                    }
                }
                HStack {
                    Text(first, format: .dateTime.hour().minute())
                    Spacer()
                    Text(last, format: .dateTime.hour().minute())
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.inkFaint)
                .offset(y: 82)
            }
        }
        .frame(height: 100)
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 22)
        .onAppear { landed = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result.scenes.count) places through the day")
    }
}

/// The mix of the set as one bar: a soft colour per kind of shot, with its icon.
struct MixBar: View {
    let picks: [Pick]
    @State private var filled = false

    var body: some View {
        let groups = Dictionary(grouping: picks, by: \.category)
            .map { (category: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.category.rawValue < $1.category.rawValue }
        let total = max(1, picks.count)
        VStack(spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(Array(groups.enumerated()), id: \.element.category) { i, g in
                        Capsule()
                            .fill(g.category.tone)
                            .frame(width: max(8, (geo.size.width - CGFloat(groups.count - 1) * 3) * CGFloat(g.count) / CGFloat(total)))
                            .scaleEffect(x: filled ? 1 : 0.001, anchor: .leading)
                            .animation(.spring(duration: 0.7, bounce: 0.15).delay(0.75 + Double(i) * 0.08), value: filled)
                    }
                }
            }
            .frame(height: 10)
            HStack(spacing: 12) {
                ForEach(groups, id: \.category) { g in
                    HStack(spacing: 4) {
                        Circle().fill(g.category.tone).frame(width: 8, height: 8)
                        Image(systemName: g.category.symbol).font(.system(size: 11, weight: .semibold))
                        Text("\(g.count)").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(Theme.inkSoft)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(g.count) \(Explanations.categoryName(g.category))")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
        .onAppear { filled = true }
    }
}

extension Category {
    /// A calm colour per kind of shot (muted, no purple), used by the mix bar and card badges.
    var tone: Color {
        switch self {
        case .me: Color(red: 0.20, green: 0.26, blue: 0.32)
        case .meWithView: Color(red: 0.36, green: 0.49, blue: 0.56)
        case .group: Color(red: 0.29, green: 0.54, blue: 0.50)
        case .friends: Color(red: 0.50, green: 0.62, blue: 0.73)
        case .someone: Color(red: 0.58, green: 0.58, blue: 0.56)
        case .view: Color(red: 0.49, green: 0.66, blue: 0.48)
        case .food: Color(red: 0.84, green: 0.62, blue: 0.38)
        case .detail: Color(red: 0.67, green: 0.60, blue: 0.53)
        case .other: Color(red: 0.62, green: 0.66, blue: 0.70)
        }
    }
}
