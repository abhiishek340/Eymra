import SwiftUI
import UIKit

/// Small in-memory cache of decoded thumbnails, keyed by photo ID and size.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    init() { cache.countLimit = 300 }

    func image(for id: String, longEdge: Double, source: any PhotoSource) async -> UIImage? {
        let key = "\(id)|\(Int(longEdge))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let cg = try? await source.image(for: id, longEdge: longEdge, allowNetwork: true) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Fills its frame with the photo, cropped to fit.
struct PhotoThumbnail: View {
    @Environment(AppModel.self) private var app
    let photoID: String
    var longEdge: Double = 400
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .overlay {
                if let image {
                    // The flexible frame keeps the filled image from reporting a size larger than its slot,
                    // which would otherwise widen hit-testing and accessibility frames beyond the clip.
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .task(id: photoID) {
                image = await ThumbnailCache.shared.image(for: photoID, longEdge: longEdge, source: app.source)
            }
            .accessibilityHidden(true)
    }
}

struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .accentColor

    var body: some View {
        Label {
            Text(text).lineLimit(1)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.15), in: Capsule())
        .foregroundStyle(tint)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension Category {
    var symbol: String {
        switch self {
        case .me: "person.fill"
        case .meWithView: "figure.walk"
        case .group: "person.3.fill"
        case .view: "mountain.2.fill"
        case .food: "fork.knife"
        case .detail: "sparkle.magnifyingglass"
        case .other: "photo"
        }
    }
}
