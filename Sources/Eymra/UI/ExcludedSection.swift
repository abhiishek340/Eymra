import SwiftUI

/// "Everything else": every photo that didn't make the cut, with the rule that excluded it.
struct ExcludedSection: View {
    @Bindable var vm: RunViewModel
    let result: RunResult
    @State private var expanded = false
    @State private var whyNot: String?

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 6)]

    private var ids: [String] {
        result.excluded.keys.sorted { a, b in
            let ra = result.scores[a]?.quality ?? -1, rb = result.scores[b]?.quality ?? -1
            return ra != rb ? ra > rb : a < b
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    Button { whyNot = id } label: {
                        PhotoThumbnail(photoID: id, longEdge: 200)
                            .frame(height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .bottomLeading) {
                                Text("Why not?")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 4).padding(.vertical, 2)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(result.excluded[id].map(Explanations.whyNot) ?? "")
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Everything else (\(result.excluded.count))").font(.headline)
        }
        .accessibilityIdentifier("excludedSection")
        .sheet(item: Binding(get: { whyNot.map(IdentifiedID.init) }, set: { whyNot = $0?.id })) { item in
            WhyNotSheet(vm: vm, photoID: item.id, tag: result.excluded[item.id])
                .presentationDetents([.medium, .large])
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
        NavigationStack {
            VStack(spacing: 16) {
                PhotoThumbnail(photoID: photoID, longEdge: 800)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(tag.map(Explanations.whyNot) ?? String(localized: "Not picked"))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("whyNotReason")
                if canSwap {
                    Button {
                        vm.swapIn(photoID)
                        dismiss()
                    } label: {
                        Label("Swap into the set", systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("swapIn")
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Why not?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
