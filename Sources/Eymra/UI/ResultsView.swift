import SwiftUI

struct ResultsView: View {
    @Bindable var vm: RunViewModel
    @State private var selected: Pick?
    @State private var shareItems: [URL] = []
    @State private var showShare = false
    @State private var exporting = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            if let r = vm.result {
                VStack(alignment: .leading, spacing: 16) {
                    summary(r)
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(r.picks) { pick in
                            Button { selected = pick } label: { PickCard(pick: pick, ratio: r.setRatio) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("pick-\(pick.position)")
                        }
                    }
                    ExcludedSection(vm: vm, result: r)
                }
                .padding()
            }
        }
        .navigationTitle(vm.result.map { PlatformPreset.preset($0.config.platform).name } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { Task { exporting = true; await vm.saveAlbum(); exporting = false } } label: {
                        Label("Save to album", systemImage: "rectangle.stack.badge.plus")
                    }
                    .accessibilityIdentifier("saveAlbum")
                    Button {
                        Task {
                            exporting = true
                            shareItems = await vm.shareFiles()
                            exporting = false
                            showShare = !shareItems.isEmpty
                        }
                    } label: { Label("Share all…", systemImage: "square.and.arrow.up") }
                    Button { vm.openPlatformApp() } label: {
                        Label("Open \(vm.platformPreset.id == .x ? "X" : vm.platformPreset.id == .facebook ? "Facebook" : "Instagram")",
                              systemImage: "arrow.up.forward.app")
                    }
                    Divider()
                    Button { vm.rerun() } label: { Label("Re-run (keep locks)", systemImage: "arrow.clockwise") }
                } label: {
                    if exporting { ProgressView() } else { Label("Export", systemImage: "square.and.arrow.up") }
                }
                .accessibilityIdentifier("exportMenu")
            }
        }
        .sheet(item: $selected) { pick in
            PickDetailSheet(vm: vm, pickID: pick.photoID)
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        .overlay(alignment: .bottom) {
            if let toast = vm.toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { vm.toast = nil }
                    }
                    .accessibilityIdentifier("toast")
            }
        }
        .animation(.default, value: vm.toast)
    }

    @ViewBuilder private func summary(_ r: RunResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(r.picks.count) keepers")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("resultsTitle")
            Text("From \(r.stats.photoCount) photos · \(r.stats.sceneCount) places · \(r.stats.clusterCount) moments")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if r.stats.judgeUsed {
                    Chip(text: String(localized: "AI Judge used"), systemImage: "sparkles", tint: .purple)
                } else {
                    Chip(text: String(localized: "On-device"), systemImage: "iphone", tint: .green)
                }
                Chip(text: r.setRatio.label, systemImage: "crop", tint: .secondary)
            }
            if let note = r.stats.judgeNote {
                Label(note, systemImage: "info.circle").font(.footnote).foregroundStyle(.orange)
            }
            if r.stats.shortfall > 0 {
                Label("Only \(r.picks.count) distinct moments were good enough, \(r.stats.shortfall) short of \(r.config.count).",
                      systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(r.stats.relaxations, id: \.self) { note in
                Label(note, systemImage: "slider.horizontal.3").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct PickCard: View {
    let pick: Pick
    let ratio: AspectRatio

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(ratio.value, contentMode: .fit)
                .overlay { PhotoThumbnail(photoID: pick.photoID) }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    Text("\(pick.position)")
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 24, height: 24)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    if pick.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(6)
                    }
                }
            Text(pick.reason)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)
            HStack(spacing: 4) {
                Chip(text: Explanations.categoryName(pick.category), systemImage: pick.category.symbol, tint: .secondary)
                if pick.clusterSize > 1 {
                    Chip(text: String(localized: "best of \(pick.clusterSize)"))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pick \(pick.position): \(pick.reason)")
    }
}
