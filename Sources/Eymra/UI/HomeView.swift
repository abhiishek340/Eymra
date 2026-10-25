import PhotosUI
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var vm: RunViewModel
    @State private var showSettings = false

    init(app: AppModel) {
        _vm = State(initialValue: RunViewModel(app: app))
    }

    var body: some View {
        @Bindable var vm = vm
        NavigationStack {
            Form {
                if app.access == .limited {
                    Section {
                        Label("Eymra can only see the photos you selected, so picks may miss your best shots.",
                              systemImage: "exclamationmark.triangle")
                            .font(.callout)
                        Button("Allow access to all photos") { app.openSystemSettings() }
                    }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RangePreset.allCases) { preset in
                                Button(preset.title) { vm.preset = preset }
                                    .buttonStyle(.bordered)
                                    .tint(vm.preset == preset ? .accentColor : .secondary)
                                    .accessibilityAddTraits(vm.preset == preset ? .isSelected : [])
                                    .accessibilityIdentifier("range-\(preset.rawValue)")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if vm.preset == .custom {
                        DatePicker("From", selection: $vm.customStart, in: ...Date())
                        DatePicker("To", selection: $vm.customEnd, in: ...Date())
                    }
                    rangeCaption
                } header: {
                    Text("When")
                }

                Section {
                    Picker("Platform", selection: $vm.platform) {
                        ForEach(PlatformPreset.all) { p in
                            Label(p.name, systemImage: p.symbol).tag(p.id)
                        }
                    }
                    .accessibilityIdentifier("platformPicker")
                    Stepper(value: $vm.count, in: 1...vm.platformPreset.maxCount) {
                        LabeledContent("Pick", value: "\(vm.count)")
                    }
                    .accessibilityIdentifier("countStepper")
                    Picker("Mix", selection: $vm.mix) {
                        Text("More of me").tag(Mix.moreOfMe)
                        Text("Balanced").tag(Mix.balanced)
                        Text("More scenery").tag(Mix.moreScenery)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Posting to")
                } footer: {
                    Text("Crops favour \(vm.platformPreset.primaryRatio.label). Up to \(vm.platformPreset.maxCount) photos.")
                }

                Section {
                    Button { showSettings = true } label: {
                        LabeledContent {
                            Text(app.settings.judgeEnabled ? (app.settings.hasAPIKey || app.isUITesting ? String(localized: "On") : String(localized: "On, needs key")) : String(localized: "Off"))
                        } label: {
                            Label("AI Judge", systemImage: "sparkles")
                        }
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text(app.settings.judgeEnabled
                         ? "Small, metadata-free thumbnails of the shortlist are sent to Claude for a second opinion."
                         : "Everything runs on this iPhone. Nothing leaves it.")
                }

                if let result = vm.result, !vm.showResults {
                    Section {
                        Button("Show last result (\(result.picks.count) picks)") { vm.showResults = true }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    vm.run()
                } label: {
                    Label("Find my keepers", systemImage: "wand.and.stars")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(vm.photoCount == 0)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
                .accessibilityIdentifier("runButton")
            }
            .navigationTitle("Eymra")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("settingsButton")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(isPresented: Binding(get: { vm.isRunning }, set: { if !$0 { vm.cancel() } })) {
                RunProgressView(vm: vm)
            }
            .navigationDestination(isPresented: $vm.showResults) {
                ResultsView(vm: vm)
            }
            .alert("Run failed", isPresented: Binding(get: { if case .failed = vm.phase { true } else { false } },
                                                      set: { if !$0 { vm.cancel() } })) {
                Button("OK", role: .cancel) {}
            } message: {
                if case .failed(let message) = vm.phase { Text(message) }
            }
        }
        .task { vm.refreshCount() }
        .onChange(of: app.access) { vm.refreshCount() }
    }

    @ViewBuilder private var rangeCaption: some View {
        if let n = vm.photoCount {
            Text(n == 0 ? String(localized: "No photos in this range") : String(localized: "\(n) photos in this range"))
                .font(.callout)
                .foregroundStyle(n == 0 ? .orange : .secondary)
                .accessibilityIdentifier("photoCount")
        } else {
            Text("Counting photos…").font(.callout).foregroundStyle(.secondary)
        }
    }
}
