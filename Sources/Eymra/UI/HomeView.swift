import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Bindable var vm: RunViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if !app.access.isUsable { accessCard }
                    if app.access == .limited { limitedCard }
                    whenCard
                    whereCard
                    countCard
                    focusCard
                    claudeRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 170)
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    BottomFade(height: 220)
                    runButton
                }
            }
            .dreamScreen()
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: Binding(get: { vm.isRunning }, set: { if !$0 { vm.cancel() } })) {
                RunProgressView(vm: vm)
            }
            .navigationDestination(isPresented: $vm.showResults) {
                ResultsView(vm: vm)
            }
            .alert("Something went wrong", isPresented: Binding(get: { if case .failed = vm.phase { true } else { false } },
                                                                set: { if !$0 { vm.cancel() } })) {
                Button("OK", role: .cancel) {}
            } message: {
                if case .failed(let message) = vm.phase { Text(message) }
            }
        }
        .task { vm.refreshCount() }
        .onChange(of: app.access) { vm.refreshCount() }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 13, weight: .medium))
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkSoft)
            Text(greeting).font(Theme.title(34))
            Text("Let's find the photos worth sharing.")
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.top, 16)
        .padding(.bottom, 6)
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

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Eymra can't see your photos yet.", systemImage: "photo.badge.exclamationmark")
                .font(.system(size: 16, weight: .medium))
            Button(app.access == .denied ? "Turn it on in Settings" : "Allow photo access") {
                if app.access == .denied { app.openSystemSettings() } else { Task { await app.requestAccess() } }
            }
            .buttonStyle(.glassSoft)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var limitedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Eymra can only see some of your photos, so it might miss your best ones.")
                .font(.system(size: 15))
            Button("Let Eymra see all photos") { app.openSystemSettings() }
                .buttonStyle(.glassSoft)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var whenCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DreamHeading(text: String(localized: "When were they taken?"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RangePreset.allCases) { preset in
                        GlassChip(title: preset.title, selected: vm.preset == preset) {
                            withAnimation(.spring(duration: 0.3)) { vm.preset = preset }
                        }
                        .accessibilityIdentifier("range-\(preset.rawValue)")
                    }
                }
                .padding(.vertical, 2)
            }
            if vm.preset == .custom {
                VStack(spacing: 10) {
                    DatePicker("From", selection: $vm.customStart, in: ...Date())
                    DatePicker("To", selection: $vm.customEnd, in: ...Date())
                }
                .font(.system(size: 15))
                .tint(Theme.ink)
                .padding(14)
                .glassCard(cornerRadius: 20)
            }
            Group {
                if let n = vm.photoCount {
                    Text(n == 0 ? String(localized: "No photos from this time") : String(localized: "\(n) photos from this time"))
                } else {
                    Text("Counting your photos…")
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(Theme.inkSoft)
            .accessibilityIdentifier("photoCount")
        }
        .padding(20)
        .glassCard()
    }

    private var whereCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DreamHeading(text: String(localized: "Where will you post them?"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlatformPreset.all) { p in
                        GlassChip(title: p.name, systemImage: p.symbol, selected: vm.platform == p.id) {
                            withAnimation(.spring(duration: 0.3)) { vm.platform = p.id }
                        }
                        .accessibilityIdentifier("platform-\(p.id.rawValue)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(20)
        .glassCard()
    }

    private var countCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                DreamHeading(text: String(localized: "How many photos?"))
                Text("\(vm.platformPreset.name) allows up to \(vm.platformPreset.maxCount)")
                    .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Button { if vm.count > 1 { vm.count -= 1 } } label: { Image(systemName: "minus") }
                .buttonStyle(RoundGlassButtonStyle())
                .disabled(vm.count <= 1)
                .accessibilityLabel("Fewer")
            Text("\(vm.count)")
                .font(Theme.display(40))
                .monospacedDigit()
                .frame(minWidth: 52)
                .contentTransition(.numericText())
                .accessibilityIdentifier("countValue")
            Button { if vm.count < vm.platformPreset.maxCount { vm.count += 1 } } label: { Image(systemName: "plus") }
                .buttonStyle(RoundGlassButtonStyle())
                .disabled(vm.count >= vm.platformPreset.maxCount)
                .accessibilityLabel("More")
        }
        .animation(.spring(duration: 0.25), value: vm.count)
        .padding(20)
        .glassCard()
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DreamHeading(text: String(localized: "What should we focus on?"))
            HStack(spacing: 8) {
                GlassChip(title: String(localized: "More of me"), selected: vm.mix == .moreOfMe) { vm.mix = .moreOfMe }
                GlassChip(title: String(localized: "A mix"), selected: vm.mix == .balanced) { vm.mix = .balanced }
                GlassChip(title: String(localized: "More places"), selected: vm.mix == .moreScenery) { vm.mix = .moreScenery }
            }
            if app.account.meReference == nil {
                Text(app.account.faceUnusable
                     ? "Eymra couldn't learn your face on this device, so it can't tell you apart from friends."
                     : "Tip: set up your face in the You tab so Eymra can tell you apart from your friends.")
                    .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(20)
        .glassCard()
    }

    private var claudeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude's help").font(.system(size: 16, weight: .semibold, design: .serif))
                Text(claudeStatus).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    private var claudeStatus: String {
        if !app.settings.judgeEnabled { return String(localized: "Off. Everything stays on your phone.") }
        if app.settings.hasAPIKey || app.isUITesting { return String(localized: "On. Claude gives a second opinion.") }
        return String(localized: "On, but it needs your Claude key (in the You tab).")
    }

    private var runButton: some View {
        Button {
            vm.run()
        } label: {
            Label("Find my best photos", systemImage: "wand.and.stars")
        }
        .buttonStyle(.glassPrimary)
        .disabled(vm.photoCount == 0 || !app.access.isUsable)
        .padding(.horizontal, 20)
        .padding(.bottom, 84)
        .accessibilityIdentifier("runButton")
    }
}

struct RoundGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 44, height: 44)
            .glassCapsule()
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}
