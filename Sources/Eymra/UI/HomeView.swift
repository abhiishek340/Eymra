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

/// The setup screen: shown, not explained. Your own photos up top, a chart of your days,
/// the real shape of each post, dots for how many, and a slider from you to places.
struct SetupView: View {
    @Environment(AppModel.self) private var app
    @Bindable var vm: RunViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if let last = vm.result { lastStoryCard(last).riseIn(delay: 0.05) }
                if !app.access.isUsable { accessCard }
                PhotoHero(ids: vm.previewIDs, count: vm.photoCount)
                    .frame(maxWidth: .infinity)
                    .riseIn(delay: 0.1)
                section("When") { whenSection }.riseIn(delay: 0.16)
                section("Where") { whereSection }.riseIn(delay: 0.22)
                section("How many") { countSection }.riseIn(delay: 0.28)
                section("Focus") { focusSection }.riseIn(delay: 0.34)
                if app.access == .limited { limitedCard }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 180)
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

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
            (Text("Find your ") + Text("keepers").italic().foregroundColor(Theme.ember) + Text("."))
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .revealOnAppear(duration: 1.2, trigger: greeting)
        }
        .padding(.top, 14)
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

    private func section<Content: View>(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Theme.inkFaint)
            content()
        }
    }

    // MARK: When: a chart of your last 7 days

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DayChart(days: vm.days, isSelected: vm.isSelected) { day in
                withAnimation(Theme.Motion.snap) { vm.selectDay(day) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(RangePreset.allCases) { preset in
                        GlassChip(title: preset.short, selected: vm.preset == preset) {
                            withAnimation(Theme.Motion.snap) { vm.preset = preset }
                        }
                        .accessibilityIdentifier("range-\(preset.rawValue)")
                    }
                }
            }
            if vm.preset == .custom {
                VStack(spacing: 8) {
                    DatePicker("From", selection: $vm.customStart, in: ...Date())
                    DatePicker("To", selection: $vm.customEnd, in: ...Date())
                }
                .font(.system(size: 15))
                .tint(Theme.ink)
                .padding(14)
                .glassCard(cornerRadius: 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .glassCard()
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
            .padding(.vertical, 2)
        }
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
                VStack(spacing: 0) {
                    Text("\(vm.count)")
                        .font(Theme.display(48))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("countValue")
                    Text("of \(vm.platformPreset.maxCount)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                Button { if vm.count < vm.platformPreset.maxCount { vm.count += 1 } } label: { Image(systemName: "plus") }
                    .buttonStyle(RoundGlassButtonStyle())
                    .disabled(vm.count >= vm.platformPreset.maxCount)
                    .accessibilityLabel("More")
            }
            CountDots(count: $vm.count, maximum: vm.platformPreset.maxCount)
        }
        .animation(Theme.Motion.pop, value: vm.count)
        .padding(16)
        .glassCard()
        .sensoryFeedback(.selection, trigger: vm.count)
    }

    // MARK: Focus: from you to places

    private var focusSection: some View {
        HStack(spacing: 8) {
            focusOption(.moreOfMe, symbol: "person.fill", short: "Me", label: "Only photos of me")
            focusOption(.balanced, symbol: "circle.grid.2x2.fill", short: "Mix", label: "A mix")
            focusOption(.moreScenery, symbol: "mountain.2.fill", short: "Places", label: "More places")
        }
        .padding(6)
        .glassCard(cornerRadius: 26)
    }

    private func focusOption(_ mix: Mix, symbol: String, short: LocalizedStringKey, label: LocalizedStringKey) -> some View {
        let selected = vm.mix == mix
        return Button {
            withAnimation(Theme.Motion.snap) { vm.mix = mix }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                Text(short).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(selected ? Theme.onInk : Theme.ink.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                if selected { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.ink) }
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
                    Text("Your last story").font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    Text(run.title.isEmpty ? String(localized: "Your story") : run.title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.forward").foregroundStyle(Theme.inkSoft)
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
        .buttonStyle(.glassPrimary)
        .disabled(vm.photoCount == 0 || !app.access.isUsable)
        .padding(.horizontal, 20)
        .padding(.bottom, 84)
        .accessibilityIdentifier("runButton")
    }
}

// MARK: - Pieces

/// Your own photos from the chosen time as a little scrapbook: tilted prints with white borders, and the count
/// on a round ember sticker slapped across the corner.
struct PhotoHero: View {
    let ids: [String]
    let count: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var float = false

    private struct Spot { var x: CGFloat; var y: CGFloat; var angle: Double; var w: CGFloat }
    private let spots: [Spot] = [
        Spot(x: -98, y: 10, angle: -9, w: 118), Spot(x: 92, y: -6, angle: 7, w: 122),
        Spot(x: -6, y: -16, angle: -2, w: 136), Spot(x: 40, y: 58, angle: 11, w: 96),
    ]

    var body: some View {
        ZStack {
            let shown = Array(ids.prefix(spots.count))
            ForEach(Array(spots.enumerated()), id: \.offset) { i, spot in
                printCard(id: i < shown.count ? shown[i] : nil, width: spot.w)
                    .rotationEffect(.degrees(spot.angle + (float ? (i.isMultiple(of: 2) ? 1.5 : -1.5) : 0)))
                    .offset(x: spot.x, y: spot.y + (float ? -3 : 3) * (i.isMultiple(of: 2) ? 1 : -1))
                    .zIndex(i == 2 ? 2 : Double(i) * 0.1)
            }
            sticker
                .rotationEffect(.degrees(-10))
                .offset(x: 118, y: 78)
                .zIndex(3)
        }
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .animation(Theme.Motion.pop, value: ids)
        .onAppear {
            guard !reduceMotion && !Theme.stillMotion else { return }
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) { float = true }
        }
    }

    private func printCard(id: String?, width: CGFloat) -> some View {
        Group {
            if let id {
                PhotoThumbnail(photoID: id, longEdge: 400)
            } else {
                Theme.ink.opacity(0.06)
                    .overlay(Image(systemName: "photo").font(.system(size: 24, weight: .light)).foregroundStyle(Theme.inkFaint))
            }
        }
        .frame(width: width, height: width * 1.25)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private var sticker: some View {
        VStack(spacing: -2) {
            Text(count.map { "\($0)" } ?? "–")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(count == 1 ? "photo" : "photos")
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .foregroundStyle(.white)
        .frame(width: 94, height: 94)
        .background(Circle().fill(Theme.ember))
        .overlay(Circle().strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [3, 4])).padding(5))
        .shadow(color: Theme.ember.opacity(0.35), radius: 12, y: 6)
        .animation(Theme.Motion.pop, value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { $0 == 0 ? String(localized: "No photos from this time") : String(localized: "\($0) photos from this time") }
                            ?? String(localized: "Counting your photos…"))
        .accessibilityIdentifier("photoCount")
    }
}

/// Photos per day for the last week, as soft bars. Tap a day to pick it.
struct DayChart: View {
    let days: [RunViewModel.DayCount]
    let isSelected: (RunViewModel.DayCount) -> Bool
    let pick: (RunViewModel.DayCount) -> Void

    var body: some View {
        let top = max(1, days.map(\.count).max() ?? 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days) { day in
                let on = isSelected(day)
                Button { pick(day) } label: {
                    VStack(spacing: 6) {
                        Text(day.count > 0 ? "\(day.count)" : "")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(on ? Theme.ink : Theme.inkFaint)
                        Capsule()
                            .fill(on ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.ink.opacity(0.12)))
                            .frame(height: max(6, 64 * CGFloat(day.count) / CGFloat(top)))
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
            .glassCard(cornerRadius: 22, tint: selected ? .white.opacity(0.45) : nil)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.ink.opacity(selected ? 0.85 : 0), lineWidth: 1.5))
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
