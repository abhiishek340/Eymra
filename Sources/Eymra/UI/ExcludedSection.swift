import SwiftUI

/// "Other photos": everything that didn't make it, each with the reason why.
struct ExcludedSection: View {
    @Bindable var vm: RunViewModel
    let result: RunResult
    @State private var expanded = false
    @State private var whyNot: String?

    private let columns = [GridItem(.adaptive(minimum: 78), spacing: 8)]

    private var ids: [String] {
        result.excluded.keys.sorted { a, b in
            let ra = result.scores[a]?.quality ?? -1, rb = result.scores[b]?.quality ?? -1
            return ra != rb ? ra > rb : a < b
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.smooth(duration: 0.5)) { expanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Other photos (\(result.excluded.count))").font(.system(size: 19, weight: .semibold, design: .serif))
                        Text("Tap any photo to see why it wasn't picked").font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("excludedSection")
            if expanded {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(ids, id: \.self) { id in
                        Button { whyNot = id } label: {
                            PhotoThumbnail(photoID: id, longEdge: 220)
                                .frame(height: 78)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(result.excluded[id].map(Explanations.whyNot) ?? "")
                    }
                }
            }
        }
        .padding(18)
        .glassCard()
        .sheet(item: Binding(get: { whyNot.map(IdentifiedID.init) }, set: { whyNot = $0?.id })) { item in
            WhyNotSheet(vm: vm, photoID: item.id, tag: result.excluded[item.id])
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(36)
                .presentationBackground(.ultraThinMaterial)
        }
    }
}

struct IdentifiedID: Identifiable { let id: String }

struct WhyNotSheet: View {
    @Bindable var vm: RunViewModel
    let photoID: String
    let tag: ExclusionTag?
    @Environment(\.dismiss) private var dismiss

    private var canSwap: Bool {
        guard let tag, vm.result?.scores[photoID] != nil else { return false }
        switch tag {
        case .screenshot, .animated, .tooSmall, .inCloud, .analysisFailed, .hidden: return false
        default: return true
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                PhotoThumbnail(photoID: photoID, longEdge: 900)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text("Why it wasn't picked").font(.system(size: 13, weight: .medium)).textCase(.uppercase).foregroundStyle(Theme.inkSoft)
                Text(tag.map(Explanations.whyNot) ?? String(localized: "Not picked"))
                    .font(Theme.title(22))
                    .revealOnAppear(delay: 0.2)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("whyNotReason")
                if canSwap {
                    Button {
                        vm.swapIn(photoID)
                        dismiss()
                    } label: {
                        Label("Use this one instead", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.glassPrimary)
                    .accessibilityIdentifier("swapIn")
                }
                Button("Close") { dismiss() }
                    .buttonStyle(.glassSoft)
                    .accessibilityIdentifier("whyNotClose")
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .foregroundStyle(Theme.ink)
    }
}
