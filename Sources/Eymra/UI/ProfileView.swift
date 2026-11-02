import SwiftUI

/// The You tab on the evening stage: who you are, your face, your style, deeper picks, photos and privacy,
/// each as a dark glass panel with its own jewel icon.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @State private var keyDraft = ""
    @State private var faceFlow: FaceFlow?
    @State private var note: String?
    @State private var confirmSignOut = false

    enum FaceFlow: String, Identifiable { case camera, upload; var id: String { rawValue } }

    var body: some View {
        @Bindable var settings = app.settings
        @Bindable var account = app.account
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                profileHeader
                faceCard.riseIn(delay: 0.08)
                styleCard(prefs: $account.prefs).riseIn(delay: 0.14)
                claudeCard(settings: settings).riseIn(delay: 0.2)
                photosCard(settings: settings).riseIn(delay: 0.26)
                privacyCard.riseIn(delay: 0.32)
                Button { confirmSignOut = true } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Luxe.coral)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Luxe.coral.opacity(0.1)))
                        .overlay(Capsule().strokeBorder(Luxe.coral.opacity(0.35), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Sign out")
                .accessibilityIdentifier("signOut")
                .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .foregroundStyle(Luxe.text)
        .tint(Luxe.gold)
        .sheet(item: $faceFlow) { flow in
            ZStack {
                DreamBackground(animated: false)
                switch flow {
                case .camera: FaceScanView(done: { faceFlow = nil }, cancel: { faceFlow = nil })
                case .upload: FaceUploadView(done: { faceFlow = nil }, cancel: { faceFlow = nil })
                }
            }
            .foregroundStyle(Theme.ink)
        }
        .confirmationDialog("Sign out? Eymra will forget your name, your answers and your face on this phone.",
                            isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { app.account.signOut() }
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 16) {
            Group {
                if let url = app.account.profile?.pictureURL {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { initials }
                } else {
                    initials
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Luxe.goldGradient, lineWidth: 2).padding(-5))
            .shadow(color: Luxe.gold.opacity(0.35), radius: 16, y: 4)
            .padding(5)
            VStack(alignment: .leading, spacing: 5) {
                Text("Your profile")
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1.8)
                    .foregroundStyle(Luxe.gold)
                Text(app.account.profile?.name ?? "").font(.system(size: 28, weight: .semibold, design: .serif))
                if let email = app.account.profile?.email {
                    Text(email).font(.system(size: 14)).foregroundStyle(Luxe.soft)
                } else {
                    Text("On this phone only").font(.system(size: 14)).foregroundStyle(Luxe.soft)
                }
            }
            Spacer()
        }
        .padding(.top, 20)
        if app.account.profile?.provider == .local && GoogleSignIn.isConfigured {
            // Upgrade a name-only profile; answers and face setup stay as they are.
            Button {
                Task { await app.account.signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    GoogleMark()
                    Text(app.account.isSigningIn ? "Signing in…" : "Sign in with Google")
                }
            }
            .buttonStyle(LuxeButtonStyle())
            .disabled(app.account.isSigningIn)
            .accessibilityIdentifier("profileGoogleSignIn")
            if let error = app.account.signInError {
                Text(error).font(.footnote).foregroundStyle(.red.opacity(0.8))
            }
        }
        }
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Luxe.goldGradient)
            Text(String(app.account.greetingName.prefix(1)).uppercased())
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(Luxe.stage)
        }
    }

    // MARK: Face

    private var faceCard: some View {
        LuxePanel(label: "Your face", symbol: "faceid", color: Luxe.emerald,
                  value: app.account.meReference != nil ? String(localized: "Set up") : nil) {
            VStack(alignment: .leading, spacing: 14) {
            if app.account.hasFace {
                HStack(spacing: -12) {
                    ForEach(app.account.faceImageURLs, id: \.self) { url in
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.3) }
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Luxe.stage, lineWidth: 2))
                    }
                }
            }
            Text(faceStatus).font(.system(size: 14)).foregroundStyle(Luxe.soft)
            HStack(spacing: 10) {
                if FaceScanner.hasCamera {
                    Button(app.account.hasFace ? "Scan again" : "Scan my face") { faceFlow = .camera }.buttonStyle(.glassSoft)
                }
                Button("Choose photos") { faceFlow = .upload }.buttonStyle(.glassSoft)
                    .accessibilityIdentifier("faceChoosePhotos")
            }
            if app.account.hasFace {
                Button("Remove my face") { app.account.removeFace() }
                    .font(.system(size: 14)).foregroundStyle(Luxe.soft)
            }
            }
        }
    }

    private var faceStatus: String {
        if app.account.meReference != nil { return String(localized: "Eymra can find you in your photos, even among friends.") }
        if app.account.faceNeedsRedo { return String(localized: "Eymra got better at recognising you. Please scan your face again.") }
        if app.account.faceUnusable { return String(localized: "We saved your photos, but this device couldn't learn your face from them.") }
        return String(localized: "Not set up yet. Eymra can't tell you apart from your friends.")
    }

    // MARK: Style

    private func styleCard(prefs: Binding<UserPrefs>) -> some View {
        LuxePanel(label: "Your style", symbol: "paintbrush.pointed.fill", color: Luxe.honey) {
            VStack(alignment: .leading, spacing: 14) {
            styleRow(String(localized: "I mostly post")) {
                Picker("I mostly post", selection: prefs.style) {
                    Text("Mostly me").tag(PostingStyle.mostlyMe)
                    Text("Me with friends").tag(PostingStyle.meAndFriends)
                    Text("A bit of everything").tag(PostingStyle.mix)
                    Text("Places and things").tag(PostingStyle.places)
                }
            }
            styleRow(String(localized: "Group photos")) {
                Picker("Group photos", selection: prefs.groups) {
                    Text("Love them").tag(GroupTaste.love)
                    Text("Sometimes").tag(GroupTaste.sometimes)
                    Text("Not really").tag(GroupTaste.rarely)
                }
            }
            styleRow(String(localized: "Photo order")) {
                Picker("Photo order", selection: prefs.story) {
                    Text("Like a story").tag(StoryStyle.story)
                    Text("Best first").tag(StoryStyle.bestFirst)
                }
            }
            }
            .pickerStyle(.menu)
            .tint(Luxe.champagne)
            .font(.system(size: 15))
        }
    }

    private func styleRow<P: View>(_ title: String, @ViewBuilder picker: () -> P) -> some View {
        HStack {
            Text(title).foregroundStyle(Luxe.soft)
            Spacer()
            picker().labelsHidden()
        }
    }

    // MARK: Claude

    private func claudeCard(settings: Settings) -> some View {
        @Bindable var settings = settings
        return LuxePanel(label: "Deeper picks", symbol: "eye.fill", color: Luxe.coral,
                         value: settings.judgeEnabled ? String(localized: "On") : nil) {
            VStack(alignment: .leading, spacing: 14) {
            // The panel already says "Deeper picks"; the switch only explains it (and keeps the name for VoiceOver).
            Toggle(isOn: $settings.judgeEnabled) {
                Text("An even more careful look at your best photos.").font(.system(size: 14)).foregroundStyle(Luxe.soft)
            }
            .tint(Luxe.gold)
            .accessibilityLabel("Deeper picks")
            .accessibilityIdentifier("judgeToggle")
            if settings.judgeEnabled {
                Text("This uses your own Anthropic account. Small copies of your best photos are sent for a closer look, with location and all other details removed. Your face is never sent.")
                    .font(.system(size: 13)).foregroundStyle(Luxe.soft)
                VStack(alignment: .leading, spacing: 8) {
                    Text(settings.hasAPIKey ? "Your key is saved" : "Paste your Anthropic API key")
                        .font(.system(size: 15, weight: .medium))
                    SecureField(settings.hasAPIKey ? "Paste a new key to replace it" : "sk-ant-…", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .glassCapsule(interactive: false)
                        .submitLabel(.done)
                        // Done on the keyboard saves, so the Save button hidden under the keyboard isn't needed.
                        .onSubmit { saveKey(settings) }
                        .accessibilityIdentifier("apiKeyField")
                    HStack {
                        Button("Save key") { saveKey(settings) }
                        .buttonStyle(.glassSoft)
                        .disabled(keyDraft.isEmpty)
                        .accessibilityIdentifier("saveKey")
                        if settings.hasAPIKey {
                            Button("Remove key") { settings.setAPIKey(""); note = nil }
                                .accessibilityIdentifier("removeKey")
                                .font(.system(size: 14)).foregroundStyle(Luxe.soft)
                        }
                    }
                    Text("Get a key at console.anthropic.com → API keys. You pay Anthropic directly for what you use.")
                        .font(.system(size: 12)).foregroundStyle(Luxe.faint)
                }
                Picker("Speed and quality", selection: $settings.judgeModel) {
                    ForEach(ClaudeJudge.models) { m in Text("\(m.name) · \(m.estimate)").tag(m.id) }
                }
                .pickerStyle(.menu)
                .tint(Luxe.champagne)
            }
            if settings.judgeEnabled, let issue = settings.deeperIssue {
                Label(issue, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Luxe.soft)
            }
            if let note { Text(note).font(.footnote).foregroundStyle(Luxe.champagne) }
            }
        }
    }

    private func saveKey(_ settings: Settings) {
        guard !keyDraft.isEmpty else { return }
        let saved = settings.setAPIKey(keyDraft)
        keyDraft = ""
        note = saved && settings.hasAPIKey
            ? String(localized: "Saved. It's kept safely in your phone's keychain.")
            : String(localized: "Your phone wouldn't save the key. Please try again.")
    }

    // MARK: Photos and privacy

    private func photosCard(settings: Settings) -> some View {
        @Bindable var settings = settings
        return LuxePanel(label: "Photos", symbol: "photo.stack.fill", color: Luxe.sea) {
            VStack(alignment: .leading, spacing: 12) {
            Toggle("Download photos from iCloud when needed", isOn: $settings.allowICloudDownloads)
            if settings.allowICloudDownloads {
                Toggle("Only on Wi-Fi", isOn: $settings.iCloudWiFiOnly)
            }
            Button("Show hidden photos again") {
                Task { await app.store.clearHidden(); note = String(localized: "Hidden photos are back.") }
            }
            .buttonStyle(.glassSoft)
            }
            .font(.system(size: 15))
            .tint(Luxe.gold)
        }
    }

    private var privacyCard: some View {
        LuxePanel(label: "Your privacy", symbol: "lock.shield.fill", color: Luxe.gold) {
            VStack(alignment: .leading, spacing: 12) {
                promise("Your photos are looked at on this phone.", symbol: "iphone", color: Luxe.sea)
                promise("Your face setup never leaves this phone.", symbol: "faceid", color: Luxe.emerald)
                promise("No ads, no tracking, no Eymra servers.", symbol: "hand.raised.fill", color: Luxe.coral)
                Button("Clear saved photo analysis") {
                    Task { await app.store.clearFeatures(); note = String(localized: "Cleared. The next pick will take a little longer.") }
                }
                .font(.system(size: 14)).foregroundStyle(Luxe.soft)
                .padding(.top, 2)
            }
        }
    }

    private func promise(_ text: LocalizedStringKey, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: color, size: 24, lit: false)
            Text(text).font(.system(size: 14)).foregroundStyle(Luxe.text)
        }
    }
}
