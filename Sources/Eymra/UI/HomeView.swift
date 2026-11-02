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

/// The setup screen as an evening stage: your photos turning on a ring under warm light, a headline in serif,
/// and every choice as a jewel-coloured tile, ending on a gold button.
struct SetupView: View {
    @Environment(AppModel.self) private var app
    @Bindable var vm: RunViewModel
    @State private var galleryScroll = GalleryScroll()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                CircularPhotoGallery(ids: vm.previewIDs, scroll: galleryScroll)
                    .frame(height: 310)
                    .padding(.top, 6)
                    .riseIn(delay: 0.05)
                headline
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .riseIn(delay: 0.12)
                if let last = vm.result {
                    lastStoryCard(last)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .riseIn(delay: 0.16)
                }
                if !app.access.isUsable {
                    accessCard.padding(.horizontal, 16).padding(.top, 18)
                }
                VStack(spacing: 14) {
                    LuxePanel(label: "When", symbol: "calendar", color: Luxe.amber, value: vm.preset.title) { whenSection }
                        .riseIn(delay: 0.2)
                    LuxePanel(label: "Post to", symbol: "paperplane.fill", color: Luxe.coral, value: vm.platformPreset.name) { whereSection }
                        .riseIn(delay: 0.26)
                    LuxePanel(label: "How many", symbol: "number", color: Luxe.gold,
                              value: String(localized: "\(vm.count) of \(vm.platformPreset.maxCount)")) { countSection }
                        .riseIn(delay: 0.32)
                    LuxePanel(label: "Focus", symbol: "scope", color: Luxe.emerald, value: focusName) { focusSection }
                        .riseIn(delay: 0.38)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                if app.access == .limited {
                    limitedCard.padding(.horizontal, 16).padding(.top, 14)
                }
            }
            .padding(.bottom, 190)
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
            galleryScroll.offset = y
        }
        .background { LuxeStage() }
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                LinearGradient(stops: [.init(color: Luxe.stage.opacity(0), location: 0), .init(color: Luxe.stage.opacity(0.94), location: 0.45),
                                       .init(color: Luxe.stage, location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 230)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                runButton
            }
        }
        .foregroundStyle(Luxe.text)
        // The stage is always dark, so the clock and battery stay readable over it.
        .preferredColorScheme(.dark)
        .task { vm.refreshCount() }
        .onChange(of: app.access) { vm.refreshCount(); vm.refreshDays() }
    }

    // MARK: Masthead and headline

    private var masthead: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1.8)
                    .foregroundStyle(Luxe.gold)
                Text(greeting)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(Luxe.text)
                    .revealOnAppear(duration: 1.1, trigger: greeting)
            }
            Spacer()
            Text(String(app.account.greetingName.prefix(1)).uppercased())
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(Luxe.stage)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Luxe.goldGradient))
                .overlay(Circle().strokeBorder(Luxe.gold.opacity(0.5), lineWidth: 1).padding(-4))
                .shadow(color: Luxe.gold.opacity(0.4), radius: 12, y: 4)
                .accessibilityHidden(true)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(vm.photoCount.map { "\($0)" } ?? "–")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(vm.photoCount ?? 0)))
                    .animation(Theme.Motion.pop, value: vm.photoCount)
                Text(vm.photoCount == 1 ? "photo" : "photos")
                Circle().fill(Luxe.gold).frame(width: 4, height: 4)
                Text(spanLabel)
            }
            .font(.system(size: 12, weight: .bold))
            .textCase(.uppercase)
            .tracking(1.6)
            .foregroundStyle(Luxe.champagne)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(vm.photoCount.map { $0 == 0 ? String(localized: "No photos from this time") : String(localized: "\($0) photos from this time") }
                                ?? String(localized: "Counting your photos…"))
            .accessibilityIdentifier("photoCount")
            (Text("Find your ") + Text("keepers").italic().foregroundStyle(Luxe.goldGradient) + Text("."))
                .font(.system(size: 42, weight: .semibold, design: .serif))
                .foregroundStyle(Luxe.text)
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

    private var focusName: String {
        switch vm.mix {
        case .moreOfMe: String(localized: "Only me")
        case .balanced: String(localized: "A mix")
        case .moreScenery: String(localized: "More places")
        }
    }

    // MARK: When

    private static let rangeStyle: [RangePreset: (symbol: String, color: Color)] = [
        .today: ("sun.max.fill", Luxe.amber),
        .yesterday: ("moon.fill", Luxe.honey),
        .last3: ("3.square.fill", Luxe.coral),
        .last7: ("7.square.fill", Luxe.emerald),
        .custom: ("slider.horizontal.3", Luxe.rose),
    ]

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            DayChart(days: vm.days, isSelected: vm.isSelected, tint: Luxe.gold) { day in
                withAnimation(Theme.Motion.snap) { vm.selectDay(day) }
            }
            HStack(spacing: 7) {
                ForEach(RangePreset.allCases) { preset in
                    let style = Self.rangeStyle[preset] ?? ("calendar", Luxe.gold)
                    LuxeTile(title: preset.short, symbol: style.symbol, color: style.color, selected: vm.preset == preset) {
                        withAnimation(Theme.Motion.snap) { vm.preset = preset }
                    }
                    .accessibilityIdentifier("range-\(preset.rawValue)")
                }
            }
            if vm.preset == .custom {
                VStack(spacing: 8) {
                    DatePicker("From", selection: $vm.customStart, in: ...Date())
                    DatePicker("To", selection: $vm.customEnd, in: ...Date())
                }
                .font(.system(size: 15))
                .tint(Luxe.gold)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Where

    private static func platformColor(_ id: PlatformPreset.ID) -> Color {
        switch id {
        case .instagramCarousel: Luxe.coral
        case .instagramSingle: Luxe.rose
        case .reels: Luxe.amber
        case .facebook: Luxe.sea
        case .x: Luxe.sand
        }
    }

    private var whereSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PlatformPreset.all) { p in
                    LuxeTile(title: p.shortName, symbol: p.symbol, color: Self.platformColor(p.id), selected: vm.platform == p.id, width: 74) {
                        withAnimation(Theme.Motion.pop) { vm.platform = p.id }
                    }
                    .accessibilityLabel(p.name)
                    .accessibilityIdentifier("platform-\(p.id.rawValue)")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
        .padding(.horizontal, -18)
    }

    // MARK: How many

    private var countSection: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                Button { if vm.count > 1 { vm.count -= 1 } } label: { Image(systemName: "minus") }
                    .buttonStyle(LuxeRoundButtonStyle())
                    .disabled(vm.count <= 1)
                    .accessibilityLabel("Fewer")
                Spacer()
                Text("\(vm.count)")
                    .font(Theme.display(64))
                    .monospacedDigit()
                    .foregroundStyle(Luxe.goldGradient)
                    .contentTransition(.numericText(value: Double(vm.count)))
                    .shadow(color: Luxe.gold.opacity(0.35), radius: 16)
                    .accessibilityIdentifier("countValue")
                Spacer()
                Button { if vm.count < vm.platformPreset.maxCount { vm.count += 1 } } label: { Image(systemName: "plus") }
                    .buttonStyle(LuxeRoundButtonStyle())
                    .disabled(vm.count >= vm.platformPreset.maxCount)
                    .accessibilityLabel("More")
            }
            CountDots(count: $vm.count, maximum: vm.platformPreset.maxCount, tint: Luxe.gold)
        }
        .animation(Theme.Motion.pop, value: vm.count)
        .sensoryFeedback(.selection, trigger: vm.count)
    }

    // MARK: Focus

    private var focusSection: some View {
        HStack(spacing: 8) {
            focusTile(.moreOfMe, symbol: "person.fill", short: String(localized: "Me"), color: Luxe.coral, label: "Only photos of me")
            focusTile(.balanced, symbol: "circle.grid.2x2.fill", short: String(localized: "Mix"), color: Luxe.honey, label: "A mix")
            focusTile(.moreScenery, symbol: "mountain.2.fill", short: String(localized: "Places"), color: Luxe.emerald, label: "More places")
        }
    }

    private func focusTile(_ mix: Mix, symbol: String, short: String, color: Color, label: LocalizedStringKey) -> some View {
        LuxeTile(title: short, symbol: symbol, color: color, selected: vm.mix == mix) {
            withAnimation(Theme.Motion.snap) { vm.mix = mix }
        }
        .accessibilityLabel(label)
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
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 1))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your last story")
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(Luxe.gold)
                    Text(run.title.isEmpty ? String(localized: "Your story") : run.title)
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundStyle(Luxe.text)
                        .lineLimit(1)
                }
                Spacer()
                IconBadge(symbol: "arrow.up.right", color: Luxe.gold, size: 30)
            }
            .padding(14)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Luxe.card.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Luxe.line, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("lastStoryCard")
    }

    private var accessCard: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: "photo.on.rectangle.angled", color: Luxe.amber)
            Text("Eymra can't see your photos yet.").font(.system(size: 15, weight: .medium))
            Spacer()
            Button(app.access == .denied ? "Settings" : "Allow") {
                if app.access == .denied { app.openSystemSettings() } else { Task { await app.requestAccess() } }
            }
            .buttonStyle(.glassSoft)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Luxe.card))
    }

    private var limitedCard: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: "eye.trianglebadge.exclamationmark", color: Luxe.honey)
            Text("Only some photos are visible.").font(.system(size: 14))
            Spacer()
            Button("Allow all") { app.openSystemSettings() }.buttonStyle(.glassSoft)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Luxe.card))
    }

    private var runButton: some View {
        Button {
            vm.run()
        } label: {
            HStack(spacing: 10) {
                Text("Find my best photos")
                Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
            }
        }
        .buttonStyle(LuxeButtonStyle())
        .disabled(vm.photoCount == 0 || !app.access.isUsable)
        .padding(.horizontal, 20)
        .padding(.bottom, 84)
        .accessibilityIdentifier("runButton")
    }
}

/// Photos per day for the last week, as soft bars. Tap a day to pick it.
struct DayChart: View {
    let days: [RunViewModel.DayCount]
    let isSelected: (RunViewModel.DayCount) -> Bool
    var tint: Color = Theme.ink
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
                            .fill(on ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.ink.opacity(0.12)))
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

/// One small pill per photo you'll post; tap one to set the count.
struct CountDots: View {
    @Binding var count: Int
    let maximum: Int
    var tint: Color = Theme.ink

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(10, maximum))
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<maximum, id: \.self) { i in
                Capsule()
                    .fill(i < count ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)))
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
