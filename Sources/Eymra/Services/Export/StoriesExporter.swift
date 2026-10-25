import Foundation
import UIKit
import UniformTypeIdentifiers

/// Copies one pick, pre-cropped to a ratio, to the pasteboard for Stories.
nonisolated enum StoriesExporter {
    static func croppedJPEG(photoID: String, ratio: AspectRatio, saliency: NormRect?, source: any PhotoSource) async throws -> Data {
        let image = try await source.image(for: photoID, longEdge: 2048, allowNetwork: true)
        guard let cropped = Renderer.crop(image, ratio: ratio, saliency: saliency),
              let data = Renderer.jpeg(cropped, longEdge: 2048, quality: 0.92) else {
            throw PhotoSourceError.decodeFailed
        }
        return data
    }

    @MainActor
    static func copyToPasteboard(_ jpeg: Data) {
        UIPasteboard.general.setData(jpeg, forPasteboardType: UTType.jpeg.identifier)
    }
}
