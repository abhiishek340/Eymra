import SwiftUI

/// Create: setup → working → story, as states of one screen (no covers or pushes stacked on each other).
struct CreateView: View {
    @Bindable var vm: RunViewModel

    var body: some View {
        ZStack {
            switch vm.screen {
            case .setup:
                SetupView(vm: vm)
                    .transition(.blurReplace(.downUp))
            case .working:
                MagicView(vm: vm)
                    .transition(.blurReplace)
            case .story:
                ResultsView(vm: vm)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 40)), removal: .opacity))
            }
        }
        .animation(.smooth(duration: 0.7), value: vm.screen)
        .sensoryFeedback(.success, trigger: vm.screen == .story)
        .alert("Something went wrong", isPresented: Binding(get: { if case .failed = vm.phase { true } else { false } },
                                                            set: { if !$0 { vm.cancel() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if case .failed(let message) = vm.phase { Text(message) }
        }
    }
}

/// The setup screen, laid out like a magazine page: a quiet masthead, your own photos as a slow film on one large
/// print, then one calm panel of choices, each with its current answer set in italic serif.
struct SetupView: View {
    @Environment(AppModel.self) private var app
    @Bindable var vm: RunViewModel
    @Namespace private var focusPill
    @Namespace private var rangePill

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                HeroReel(ids: vm.previewIDs, count: vm.photoCount, span: spanLabel)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .riseIn(delay: 0.05)
                    // Scrolling up, the print sinks back a little and fades as the page passes over it.
                    .scrollTransition(.interactive, axis: .vertical) { content, phase in
                        content
                            .scaleEffect(phase.value < 0 ? 1 + phase.value * 0.08 : 1, anchor: .bottom)
                            .offset(y: phase.value < 0 ? -phase.value * 70 : 0)
                            .opacity(phase.value < 0 ? 1 + phase.value * 0.7 : 1)
                    }
                if let last = vm.result {
                    lastStoryCard(last)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .riseIn(delay: 0.1)
                }
                if !app.access.isUsable {
                    accessCard.padding(.horizontal, 16).padding(.top, 18)
                }
                choices
                    .padding(.horizontal, 16)
                    .padding(.top, 22)
                if app.access == .limited {
                    limitedCard.padding(.horizontal, 16).padding(.top, 16)
                }
            }
            .padding(.bottom, 190)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                BottomFade(height: 220)
                runButton
            }
        }
        .dreamScreen()
        .task { vm.refreshCount() }
        .onChange(of: app.access) { vm.refreshCount(); vm.refreshDays() }
    }

    // MARK: Masthead

    private var masthead: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1.8)
                    .foregroundStyle(Theme.inkFaint)
                Text(greeting)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .revealOnAppear(duration: 1.1, trigger: greeting)
            }
            Spacer()
            Text(String(app.account.greetingName.prefix(1)).uppercased())
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.onInk)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Theme.ink))
                .overlay(Circle().strokeBorder(Theme.ember.opacity(0.7), lineWidth: 1).padding(-4))
                .accessibilityHidden(true)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = app.account.greetingName
        switch hour {
        case 5..<12: return String(localized: "Good morning, \(name)")
        case 12..<17: return String(localized: "Good afternoon, \(name)")
        default: return String(localized: "Good evening, \(name)")
        }
    }

    /// "Fri – Sun", "Today", or "12 Oct – 1 Nov" for longer spans.
    private var spanLabel: String {
        let r = vm.range, cal = Calendar.current
        let last = r.end.addingTimeInterval(-1)
        if cal.isDate(r.start, inSameDayAs: last) {
            return cal.isDateInToday(r.start) ? String(localized: "Today") : r.start.formatted(.dateTime.weekday(.wide))
        }
        let long = r.duration > 6.5 * 86_400
        let style: Date.FormatStyle = long ? .dateTime.day().month(.abbreviated) : .dateTime.weekday(.abbreviated)
        return "\(r.start.formatted(style)) – \(last.formatted(style))"
    }

    // MARK: Choices

    /// One panel, rows split by hairlines: a small label, the current answer in italic serif, then the control.
    private var choices: some View {
        VStack(spacing: 0) {
            row("When", value: vm.preset.title, delay: 0.14) { whenSection }
            hairline
            row("Post to", value: vm.platformPreset.name, delay: 0.2) { whereSection }
            hairline
            row("How many", value: String(localized: "\(vm.count) of \(vm.platformPreset.maxCount)"), delay: 0.26) { countSection }
            hairline
            row("Focus", value: focusName, delay: 0.32) { focusSection }
        }
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 24, y: 10)
    }

    private var hairline: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.horizontal, 20)
    }

    private func row<Content: View>(_ label: LocalizedStringKey, value: String, delay: Double,
                                    @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1.6)
                    .foregroundStyle(Theme.inkFaint)
                Spacer()
                Text(value)
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .italic()
                    .contentTransition(.interpolate)
                    .animation(Theme.Motion.snap, value: value)
            }
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .riseIn(delay: delay)
    }

    private var focusName: String {
        switch vm.mix {
        case .moreOfMe: String(localized: "Only me")
        case .balanced: String(localized: "A mix")
        case .moreScenery: String(localized: "More places")
        }
    }

    // MARK: When: a chart of your last 7 days, then the spans

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            DayChart(days: vm.days, isSelected: vm.isSelected) { day in
                withAnimation(Theme.Motion.snap) { vm.selectDay(day) }
            }
            HStack(spacing: 2) {
                ForEach(RangePreset.allCases) { preset in
                    let on = vm.preset == preset
                    Button {
                        withAnimation(Theme.Motion.snap) { vm.preset = preset }
                    } label: {
                        Text(preset.short)
                            .font(.system(size: 13, weight: on ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(on ? Theme.onInk : Theme.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                if on {
                                    Capsule().fill(Theme.ink).matchedGeometryEffect(id: "range", in: rangePill)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("range-\(preset.rawValue)")
                }
            }
            .padding(4)
            .background(Capsule().fill(Theme.ink.opacity(0.05)))
            .sensoryFeedback(.selection, trigger: vm.preset)
            if vm.preset == .custom {
                VStack(spacing: 8) {
                    DatePicker("From", selection: $vm.customStart, in: ...Date())
                    DatePicker("To", selection: $vm.customEnd, in: ...Date())
                }
                .font(.system(size: 15))
                .tint(Theme.ink)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Where: the real shape of each post

    private var whereSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PlatformPreset.all) { p in
                    PlatformTile(preset: p, selected: vm.platform == p.id) {
                        withAnimation(Theme.Motion.pop) { vm.platform = p.id }
                    }
                    .accessibilityIdentifier("platform-\(p.id.rawValue)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, -20)
    }

    // MARK: How many: one dot per photo

    private var countSection: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                Button { if vm.count > 1 { vm.count -= 1 } } label: { Image(systemName: "minus") }
                    .buttonStyle(RoundGlassButtonStyle())
                    .disabled(vm.count <= 1)
                    .accessibilityLabel("Fewer")
                Spacer()
                Text("\(vm.count)")
                    .font(Theme.display(56))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(vm.count)))
                    .accessibilityIdentifier("countValue")
                Spacer()
                Button { if vm.count < vm.platformPreset.maxCount { vm.count += 1 } } label: { Image(systemName: "plus") }
                    .buttonStyle(RoundGlassButtonStyle())
                    .disabled(vm.count >= vm.platformPreset.maxCount)
                    .accessibilityLabel("More")
            }
            CountDots(count: $vm.count, maximum: vm.platformPreset.maxCount)
        }
        .animation(Theme.Motion.pop, value: vm.count)
        .sensoryFeedback(.selection, trigger: vm.count)
    }

    // MARK: Focus: from you to places

    private var focusSection: some View {
        HStack(spacing: 4) {
            focusOption(.moreOfMe, symbol: "person.fill", short: "Me", label: "Only photos of me")
            focusOption(.balanced, symbol: "circle.grid.2x2.fill", short: "Mix", label: "A mix")
            focusOption(.moreScenery, symbol: "mountain.2.fill", short: "Places", label: "More places")
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.ink.opacity(0.05)))
    }

    private func focusOption(_ mix: Mix, symbol: String, short: LocalizedStringKey, label: LocalizedStringKey) -> some View {
        let selected = vm.mix == mix
        return Button {
            withAnimation(Theme.Motion.snap) { vm.mix = mix }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                    .popWhenSelected(selected)
                Text(short).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(selected ? Theme.onInk : Theme.ink.opacity(0.65))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.ink)
                        .matchedGeometryEffect(id: "focus", in: focusPill)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }

    // MARK: Cards

    private func lastStoryCard(_ run: RunResult) -> some View {
        Button { vm.showResults = true } label: {
            HStack(spacing: 12) {
                HStack(spacing: -16) {
                    ForEach(run.picks.prefix(3)) { pick in
                        PhotoThumbnail(photoID: pick.photoID, longEdge: 200)
                            .frame(width: 44, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your last story")
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(Theme.inkFaint)
                    Text(run.title.isEmpty ? String(localized: "Your story") : run.title)
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
            .padding(14)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 24)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("lastStoryCard")
    }

    private var accessCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 26, weight: .light))
            Text("Eymra can't see your photos yet.").font(.system(size: 15, weight: .medium))
            Spacer()
            Button(app.access == .denied ? "Settings" : "Allow") {
                if app.access == .denied { app.openSystemSettings() } else { Task { await app.requestAccess() } }
            }
            .buttonStyle(.glassSoft)
        }
        .padding(16)
        .glassCard()
    }

    private var limitedCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "eye.trianglebadge.exclamationmark").font(.system(size: 22, weight: .light))
            Text("Only some photos are visible.").font(.system(size: 14))
            Spacer()
            Button("Allow all") { app.openSystemSettings() }.buttonStyle(.glassSoft)
        }
        .padding(16)
        .glassCard()
    }

    private var runButton: some View {
        Button {
            vm.run()
        } label: {
            HStack(spacing: 10) {
                Text("Find my best photos")
                Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
            }
        }
        .buttonStyle(.glassPrimarySheen)
        .disabled(vm.photoCount == 0 || !app.access.isUsable)
        .padding(.horizontal, 20)
        .padding(.bottom, 84)
        .accessibilityIdentifier("runButton")
    }
}

// MARK: - Pieces

/// Your photos from the chosen time as a slow film on one large print: each drifts and zooms a little, then
/// dissolves into the next, while two more prints peek out from behind. Tap to move on.
struct HeroReel: View {
    let ids: [String]
    let count: Int?
    let span: String
    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var moving: Bool { !reduceMotion && !Theme.stillMotion }
    private static let height: CGFloat = 440
    private let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)

    var body: some View {
        ZStack(alignment: .top) {
            ForEach([2, 1], id: \.self) { depth in
                backPrint(depth)
            }
            front
                .frame(height: Self.height)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: 30, y: 18)
                .padding(.top, 30)
        }
        .contentShape(shape)
        .onTapGesture { advance() }
        .sensoryFeedback(.selection, trigger: index)
        .task(id: ids) { await cycle() }
    }

    /// The prints stacked behind, a little smaller, higher and turned, showing the photos that come next.
    private func backPrint(_ depth: Int) -> some View {
        let id = ids.isEmpty ? nil : ids[(index + depth) % ids.count]
        return Group {
            if let id {
                PhotoThumbnail(photoID: id, longEdge: 600)
            } else {
                Theme.ink.opacity(0.06)
            }
        }
        .frame(height: Self.height)
        .clipShape(shape)
        .overlay(shape.fill(Theme.paper.opacity(depth == 1 ? 0.25 : 0.45)))
        .scaleEffect(1 - CGFloat(depth) * 0.06, anchor: .top)
        .rotationEffect(.degrees(depth == 1 ? -2.4 : 2.8))
        .offset(y: 30 - CGFloat(depth) * 15)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        .animation(.easeInOut(duration: 1.2), value: index)
        .accessibilityHidden(true)
    }

    private var front: some View {
        ZStack(alignment: .bottomLeading) {
            if ids.isEmpty {
                LinearGradient(colors: [Color(red: 0.99, green: 0.86, blue: 0.76), Color(red: 0.96, green: 0.92, blue: 0.87)],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
                CameraRollIllustration()
                    .scaleEffect(0.85)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: -50)
            } else {
                // One photo at a time, cross-dissolving.
                ZStack {
                    ForEach([ids[index % ids.count]], id: \.self) { id in
                        DriftingPhoto(id: id, moving: moving)
                            .transition(.opacity)
                    }
                }
            }
            LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.62), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            caption
                .padding(24)
        }
        .overlay(alignment: .topTrailing) { ticks.padding(18) }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(count.map { "\($0)" } ?? "–")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(count ?? 0)))
                    .animation(Theme.Motion.pop, value: count)
                Text(count == 1 ? "photo" : "photos")
                Circle().frame(width: 3, height: 3)
                Text(span)
            }
            .font(.system(size: 12, weight: .bold))
            .textCase(.uppercase)
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.85))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(count.map { $0 == 0 ? String(localized: "No photos from this time") : String(localized: "\($0) photos from this time") }
                                ?? String(localized: "Counting your photos…"))
            .accessibilityIdentifier("photoCount")
            (Text("Find your ") + Text("keepers").italic().foregroundColor(Color(red: 1, green: 0.72, blue: 0.58)) + Text("."))
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
    }

    /// Which photo of the reel is showing, like the bars on a story.
    private var ticks: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(ids.count, 1), id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i == index % max(ids.count, 1) ? 0.95 : 0.4))
                    .frame(width: i == index % max(ids.count, 1) ? 18 : 6, height: 4)
            }
        }
        .animation(Theme.Motion.pop, value: index)
        .opacity(ids.count > 1 ? 1 : 0)
        .accessibilityHidden(true)
    }

    private func advance() {
        guard ids.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.8)) { index = (index + 1) % ids.count }
    }

    private func cycle() async {
        index = 0
        guard moving, ids.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.4)) { index = (index + 1) % ids.count }
        }
    }
}

/// A photo that slowly pushes in and drifts while it's on screen (the Ken Burns move).
private struct DriftingPhoto: View {
    let id: String
    let moving: Bool
    @State private var drifted = false

    var body: some View {
        let seed = MagicView.seed(id)
        PhotoThumbnail(photoID: id, longEdge: 1200)
            .scaleEffect(drifted ? 1.16 : 1.04)
            .offset(x: drifted ? (seed - 0.5) * 34 : 0, y: drifted ? -12 : 0)
            .onAppear {
                guard moving else { return }
                withAnimation(.linear(duration: 9)) { drifted = true }
            }
            .accessibilityHidden(true)
    }
}

/// Photos per day for the last week, as soft bars. Tap a day to pick it.
struct DayChart: View {
    let days: [RunViewModel.DayCount]
    let isSelected: (RunViewModel.DayCount) -> Bool
    let pick: (RunViewModel.DayCount) -> Void
    @State private var grown = false

    var body: some View {
        let top = max(1, days.map(\.count).max() ?? 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                let on = isSelected(day)
                Button { pick(day) } label: {
                    VStack(spacing: 6) {
                        Text(day.count > 0 ? "\(day.count)" : "")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(on ? Theme.ink : Theme.inkFaint)
                        Capsule()
                            .fill(on ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.ink.opacity(0.12)))
                            .frame(height: grown ? max(6, 64 * CGFloat(day.count) / CGFloat(top)) : 6)
                            .animation(.spring(duration: 0.7, bounce: 0.3).delay(0.3 + Double(index) * 0.05), value: grown)
                        Text(label(day.start))
                            .font(.system(size: 11, weight: on ? .bold : .medium))
                            .foregroundStyle(on ? Theme.ink : Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(day.start.formatted(.dateTime.weekday(.wide))), \(day.count) photos")
            }
        }
        .frame(height: 104, alignment: .bottom)
        .animation(Theme.Motion.pop, value: days)
        .onAppear { grown = true }
    }

    private func label(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? String(localized: "Today") : date.formatted(.dateTime.weekday(.narrow))
    }
}

/// A platform shown as the real shape of its post.
struct PlatformTile: View {
    let preset: PlatformPreset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.ink.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.ink.opacity(selected ? 0 : 0.25), lineWidth: 1))
                        .aspectRatio(preset.primaryRatio.value, contentMode: .fit)
                        .frame(height: 50)
                        .frame(maxWidth: 58)
                    Image(systemName: preset.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? Theme.onInk : Theme.inkSoft)
                }
                .frame(height: 56)
                Text(preset.shortName)
                    .font(.system(size: 12, weight: selected ? .bold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.ink)
            .frame(width: 84, height: 104)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(selected ? Theme.surface : Theme.ink.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.ink.opacity(selected ? 0.85 : 0), lineWidth: 1.5))
            .shadow(color: .black.opacity(selected ? 0.08 : 0), radius: 10, y: 4)
            .scaleEffect(selected ? 1 : 0.96)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// One small pill per photo you'll post; tap one to set the count.
struct CountDots: View {
    @Binding var count: Int
    let maximum: Int

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(10, maximum))
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<maximum, id: \.self) { i in
                Capsule()
                    .fill(i < count ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.ink.opacity(0.1)))
                    .frame(height: 10)
                    .scaleEffect(i == count - 1 ? 1.15 : 1)
                    .contentShape(Rectangle().inset(by: -6))
                    .onTapGesture { count = i + 1 }
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: maximum < 10 ? CGFloat(maximum) * 34 : .infinity)
    }
}

struct RoundGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 44, height: 44)
            // The whole circle takes the tap: Liquid Glass alone doesn't count as tappable content,
            // which left only the glyph (9×15 pt) tappable on iOS 26.
            .contentShape(Circle())
            .background(Circle().fill(Theme.surface))
            .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
    }
}
