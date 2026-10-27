import SwiftUI
import UIKit

/// A face cut out of a photo and shown in a circle.
struct FaceCrop: View {
    @Environment(AppModel.self) private var app
    let photoID: String
    let box: NormRect
    var size: CGFloat = 64
    @State private var image: UIImage?

    var body: some View {
        Circle()
            .fill(Theme.ink.opacity(0.08))
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .task(id: photoID) {
                guard let full = await ThumbnailCache.shared.image(for: photoID, longEdge: 1400, source: app.source),
                      let cg = full.cgImage, let cut = FaceEmbedder.crop(cg, face: box, margin: 0.35) else { return }
                image = UIImage(cgImage: cut)
            }
            .accessibilityHidden(true)
    }
}

/// "Is this you?": the faces Eymra wasn't sure about, at the top of a story.
struct FaceCheckCard: View {
    let faces: [UnsureFace]
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                HStack(spacing: -14) {
                    ForEach(faces.prefix(4), id: \.photoID) { face in
                        FaceCrop(photoID: face.photoID, box: face.box, size: 40)
                            .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Is this you?").font(.system(size: 17, weight: .semibold, design: .serif))
                    Text("\(faces.count) \(faces.count == 1 ? "face" : "faces") to check")
                        .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.forward").foregroundStyle(Theme.inkSoft)
            }
            .padding(14)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 22)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.ember.opacity(0.6), lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("faceCheckCard")
    }
}

/// One tap per face: Me or Not me. Answers are remembered and used for every pick after.
struct FaceCheckSheet: View {
    let faces: [UnsureFace]
    let save: (_ me: [UnsureFace], _ notMe: [UnsureFace]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var answers: [String: Bool] = [:]

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    (Text("Is this ") + Text("you").italic().foregroundColor(Theme.ember) + Text("?"))
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                    Text("Check these matches. If Eymra picked someone else, choose Not me. Your answers are remembered.")
                        .font(.system(size: 14)).foregroundStyle(Theme.inkSoft)
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(faces, id: \.photoID) { face in
                            card(face)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 100)
            }
            .background(Theme.paper)
            .overlay(alignment: .bottom) {
                Button {
                    let me = faces.filter { answers[$0.photoID] == true }
                    let notMe = faces.filter { answers[$0.photoID] == false }
                    save(me, notMe)
                    dismiss()
                } label: {
                    Text(answers.isEmpty ? "Done" : "Save \(answers.count) \(answers.count == 1 ? "answer" : "answers")")
                }
                .buttonStyle(.glassPrimary)
                .padding(20)
                .accessibilityIdentifier("faceCheckSave")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .foregroundStyle(Theme.ink)
    }

    private func card(_ face: UnsureFace) -> some View {
        let answer = answers[face.photoID]
        return VStack(spacing: 12) {
            FaceCrop(photoID: face.photoID, box: face.box, size: 104)
                .overlay(Circle().strokeBorder(answer == true ? Theme.ember : .clear, lineWidth: 3))
                .opacity(answer == false ? 0.45 : 1)
            HStack(spacing: 6) {
                choice("Me", selected: answer == true) { answers[face.photoID] = answer == true ? nil : true }
                    .accessibilityIdentifier("faceMe")
                choice("Not me", selected: answer == false) { answers[face.photoID] = answer == false ? nil : false }
                    .accessibilityIdentifier("faceNotMe")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 24)
        .animation(Theme.Motion.snap, value: answer)
        .sensoryFeedback(.selection, trigger: answer)
    }

    private func choice(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Theme.onInk : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.ink.opacity(0.07))))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}
