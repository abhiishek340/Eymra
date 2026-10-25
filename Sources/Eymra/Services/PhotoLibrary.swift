import Foundation
import Photos
import UIKit
import os

/// PhotoKit-backed photo source. Stateless; PhotoKit managers are thread-safe.
nonisolated struct PhotoLibrary: PhotoSource {
    private static let log = Logger(subsystem: "app.eymra", category: "ingest")

    func authorizationStatus() -> LibraryAccess {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAuthorization() async -> LibraryAccess {
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    func count(in range: DateInterval) async -> Int {
        PHAsset.fetchAssets(with: .image, options: Self.options(range)).count
    }

    func records(in range: DateInterval) async throws -> [PhotoRecord] {
        let result = PHAsset.fetchAssets(with: .image, options: Self.options(range))
        var out: [PhotoRecord] = []
        out.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            out.append(Self.record(asset))
        }
        return out
    }

    func image(for id: String, longEdge: Double, allowNetwork: Bool) async throws -> CGImage {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw PhotoSourceError.notFound
        }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat   // exactly one callback, never a degraded image
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = allowNetwork
        opts.isSynchronous = false
        let target = CGSize(width: longEdge, height: longEdge)
        let image: UIImage = try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: opts) { image, info in
                if let image {
                    continuation.resume(returning: image)
                } else if (info?[PHImageResultIsInCloudKey] as? Bool) == true {
                    continuation.resume(throwing: PhotoSourceError.inCloud)
                } else {
                    continuation.resume(throwing: PhotoSourceError.decodeFailed)
                }
            }
        }
        return try Self.upright(image)
    }

    // MARK: Helpers

    static func options(_ range: DateInterval) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@",
                                        range.start as NSDate, range.end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeAllBurstAssets = false
        return options
    }

    static func record(_ asset: PHAsset) -> PhotoRecord {
        PhotoRecord(id: asset.localIdentifier,
                    creationDate: asset.creationDate ?? .distantPast,
                    modificationDate: asset.modificationDate,
                    location: asset.location.map {
                        GeoPoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                                 horizontalAccuracy: $0.horizontalAccuracy)
                    },
                    isFavorite: asset.isFavorite,
                    pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight,
                    isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                    isAnimated: asset.playbackStyle == .imageAnimated,
                    burstIdentifier: asset.burstIdentifier)
    }

    /// PhotoKit may hand back an image with a non-up orientation; Vision and the exporters want `.up` pixels.
    static func upright(_ image: UIImage) throws -> CGImage {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let cg = rendered.cgImage else { throw PhotoSourceError.decodeFailed }
        return cg
    }

    static func map(_ status: PHAuthorizationStatus) -> LibraryAccess {
        switch status {
        case .authorized: .full
        case .limited: .limited
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}
