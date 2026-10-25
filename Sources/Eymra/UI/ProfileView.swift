import SwiftUI

/// The You tab: who you are, your face, your style, Claude's help, privacy.
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
            VStack(alignment: .leading, spacing: 18) {
                profileHeader
                faceCard
                styleCard(prefs: $account.prefs)
                claudeCard(settings: settings)
                photosCard(settings: settings)
                privacyCard
                Button("Sign out") { confirmSignOut = true }
                    .buttonStyle(.glassSoft)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("signOut")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .dreamScreen()
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
        HStack(spacing: 16) {
            Group {
                if let url = app.account.profile?.pictureURL {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { initials }
                } else {
                    initials
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
            VStack(alignment: .leading, spacing: 4) {
                Text(app.account.profile?.name ?? "").font(Theme.title(26))
                if let email = app.account.profile?.email {
                    Text(email).font(.system(size: 14)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text("On this phone only").font(.system(size: 14)).foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer()
        }
        .padding(.top, 20)
    }

    private var initials: some View {
        ZStack {
            Circle().fill(.white.opacity(0.4))
            Text(String(app.account.greetingName.prefix(1))).font(Theme.title(28))
        }
    }

    // MARK: Face

    private var faceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DreamHeading(text: String(localized: "Your face"))
            if app.account.hasFace {
                HStack(spacing: -12) {
                    ForEach(app.account.faceImageURLs, id: \.self) { url in
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.3) }
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            Text(faceStatus).font(.system(size: 14)).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 10) {
                if FaceScanner.hasCamera {
                    Button(app.account.hasFace ? "Scan again" : "Scan my face") { faceFlow = .camera }.buttonStyle(.glassSoft)
                }
                Button("Choose photos") { faceFlow = .upload }.buttonStyle(.glassSoft)
            }
            if app.account.hasFace {
                Button("Remove my face") { app.account.removeFace() }
                    .font(.system(size: 14)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var faceStatus: String {
        if app.account.meReference != nil { return String(localized: "Eymra can find you in your photos, even among friends.") }
        if app.account.faceNeedsRedo { return String(localized: "Eymra got better at recognising you. Please scan your face again.") }
        if app.account.faceUnusable { return String(localized: "We saved your photos, but this device couldn't learn your face from them.") }
        return String(localized: "Not set up yet. Eymra can't tell you apart from your friends.")
    }

    // MARK: Style

    private func styleCard(prefs: Binding<UserPrefs>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DreamHeading(text: String(localized: "Your style"))
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
        .tint(Theme.ink)
        .font(.system(size: 15))
        .padding(20)
        .glassCard()
    }

    private func styleRow<P: View>(_ title: String, @ViewBuilder picker: () -> P) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.inkSoft)
            Spacer()
            picker().labelsHidden()
        }
    }

    // MARK: Claude

    private func claudeCard(settings: Settings) -> some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $settings.judgeEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deeper picks").font(.system(size: 20, weight: .semibold, design: .serif))
                    Text("An even more careful look at your best photos.").font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                }
            }
            .tint(Theme.ink.opacity(0.7))
            .accessibilityIdentifier("judgeToggle")
            if settings.judgeEnabled {
                Text("This uses your own Anthropic account. Small copies of your best photos are sent for a closer look, with location and all other details removed. Your face is never sent.")
                    .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                VStack(alignment: .leading, spacing: 8) {
                    Text(settings.hasAPIKey ? "Your key is saved" : "Paste your Anthropic API key")
                        .font(.system(size: 15, weight: .medium))
                    SecureField(settings.hasAPIKey ? "Paste a new key to replace it" : "sk-ant-…", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .glassCapsule(interactive: false)
                        .accessibilityIdentifier("apiKeyField")
                    HStack {
                        Button("Save key") {
                            settings.setAPIKey(keyDraft)
                            keyDraft = ""
                            note = settings.hasAPIKey ? String(localized: "Saved. It's kept safely in your phone's keychain.") : nil
                        }
                        .buttonStyle(.glassSoft)
                        .disabled(keyDraft.isEmpty)
                        if settings.hasAPIKey {
                            Button("Remove key") { settings.setAPIKey(""); note = nil }
                                .font(.system(size: 14)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Text("Get a key at console.anthropic.com → API keys. You pay Anthropic directly for what you use.")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                }
                Picker("Speed and quality", selection: $settings.judgeModel) {
                    ForEach(ClaudeJudge.models) { m in Text("\(m.name) · \(m.estimate)").tag(m.id) }
                }
                .pickerStyle(.menu)
                .tint(Theme.ink)
            }
            if settings.judgeEnabled, let issue = settings.deeperIssue {
                Label(issue, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.inkSoft)
            }
            if let note { Text(note).font(.footnote).foregroundStyle(Theme.inkSoft) }
        }
        .padding(20)
        .glassCard()
    }

    // MARK: Photos and privacy

    private func photosCard(settings: Settings) -> some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 12) {
            DreamHeading(text: String(localized: "Photos"))
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
        .tint(Theme.ink.opacity(0.7))
        .padding(20)
        .glassCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DreamHeading(text: String(localized: "Your privacy"))
            Label("Your photos are looked at on this phone.", systemImage: "iphone")
            Label("Your face setup never leaves this phone.", systemImage: "faceid")
            Label("No ads, no tracking, no Eymra servers.", systemImage: "hand.raised")
            Button("Clear saved photo analysis") {
                Task { await app.store.clearFeatures(); note = String(localized: "Cleared. The next pick will take a little longer.") }
            }
            .font(.system(size: 14)).foregroundStyle(Theme.inkSoft)
        }
        .font(.system(size: 14))
        .labelStyle(DreamLabelStyle())
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
