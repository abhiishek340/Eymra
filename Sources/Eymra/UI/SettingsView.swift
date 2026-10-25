import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var keyDraft = ""
    @State private var cleared: String?

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $settings.judgeEnabled) {
                        Label("AI Judge", systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("judgeToggle")
                    if settings.judgeEnabled {
                        Picker("Model", selection: $settings.judgeModel) {
                            ForEach(ClaudeJudge.models) { m in
                                Text("\(m.name) · \(m.estimate)").tag(m.id)
                            }
                        }
                        Picker("Image size", selection: $settings.judgeLongEdge) {
                            ForEach(Settings.longEdgeOptions, id: \.self) { Text("\($0) px").tag($0) }
                        }
                        SecureField(settings.hasAPIKey ? "API key saved – paste to replace" : "Anthropic API key", text: $keyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("apiKeyField")
                        HStack {
                            Button("Save key") {
                                settings.setAPIKey(keyDraft)
                                keyDraft = ""
                            }
                            .disabled(keyDraft.isEmpty)
                            Spacer()
                            if settings.hasAPIKey {
                                Button("Remove key", role: .destructive) { settings.setAPIKey("") }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("AI Judge")
                } footer: {
                    Text("When on, 30–80 shortlisted photos are shrunk, stripped of location and all other metadata, and sent to Anthropic with your own key for scores and reasons. Costs per 60-photo run are estimates. When off, offline, or on any error, picks come from this iPhone only.")
                }

                Section {
                    Toggle("Download from iCloud when needed", isOn: $settings.allowICloudDownloads)
                    if settings.allowICloudDownloads {
                        Toggle("Only on Wi-Fi", isOn: $settings.iCloudWiFiOnly)
                    }
                } header: {
                    Text("iCloud Photos")
                }

                Section {
                    Button("Show hidden photos again") {
                        Task { await app.store.clearHidden(); cleared = String(localized: "Hidden photos cleared") }
                    }
                    Button("Clear analysis cache", role: .destructive) {
                        Task { await app.store.clearFeatures(); cleared = String(localized: "Cache cleared") }
                    }
                    if let cleared { Text(cleared).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Eymra has no account, no server and no analytics. Analysis results are stored only on this iPhone.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("settingsDone")
                }
            }
        }
    }
}
