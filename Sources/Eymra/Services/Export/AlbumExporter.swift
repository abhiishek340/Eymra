import Foundation
import Photos
import os

/// Saves picks, in posting order, to a new album "Eymra – <range> · <platform>".
nonisolated enum AlbumExporter {
    enum Failure: Error { case notAuthorized, missingAssets }

    static func albumTitle(range: DateInterval, platform: PlatformPreset) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM HH:mm"
        return "Eymra – \(f.string(from: range.start))–\(f.string(from: range.end)) · \(platform.name)"
    }

    /// Returns the album's local identifier.
    static func save(photoIDs: [String], title: String) async throws -> String {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { throw Failure.notAuthorized }
        let albumID = OSAllocatedUnfairLock(initialState: "")
        try await PHPhotoLibrary.shared().performChanges {
            // Fetched inside the change block so only Sendable identifiers cross into it.
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: photoIDs, options: nil)
            var byID: [String: PHAsset] = [:]
            fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
            let ordered = photoIDs.compactMap { byID[$0] }
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            request.addAssets(ordered as NSArray)
            let id = request.placeholderForCreatedAssetCollection.localIdentifier
            albumID.withLock { $0 = id }
        }
        let id = albumID.withLock { $0 }
        guard !id.isEmpty else { throw Failure.missingAssets }
        return id
    }
}
