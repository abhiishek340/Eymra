import CoreGraphics
import Foundation
import ImageIO

/// The bundled 40-photo fixture set, used under -uiTesting and by the end-to-end test.
nonisolated struct FixtureSet: Sendable {
    struct Entry: Codable, Sendable {
        var id: String
        var file: String
        var creationDate: Date
        var modificationDate: Date?
        var location: GeoPoint?
        var isFavorite: Bool
        var pixelWidth: Int
        var pixelHeight: Int
        var isScreenshot: Bool
        var isAnimated: Bool
        var burstIdentifier: String?
        var moment: String
        var kind: String
    }

    private struct File: Codable {
        var photos: [Entry]
        var features: [FeatureRecord]
        var meReference: MeReference?
    }

    var entries: [Entry]
    var features: [String: FeatureRecord]
    var directory: URL
    /// Reference face prints of the fixture set's "you".
    var meReference: MeReference?

    /// Loads Fixtures/features.json. When `rebaseTo` is set, dates shift so the newest photo is one hour before it.
    static func load(bundle: Bundle = .main, rebaseTo now: Date? = nil) throws -> FixtureSet {
        guard let dir = bundle.url(forResource: "Fixtures", withExtension: nil) else { throw PhotoSourceError.notFound }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(File.self, from: Data(contentsOf: dir.appendingPathComponent("features.json")))
        var entries = file.photos
        if let now, let newest = entries.map(\.creationDate).max() {
            let shift = now.addingTimeInterval(-3600).timeIntervalSince(newest)
            for i in entries.indices { entries[i].creationDate.addTimeInterval(shift) }
        }
        return FixtureSet(entries: entries, features: Dictionary(uniqueKeysWithValues: file.features.map { ($0.photoID, $0) }),
                          directory: dir, meReference: file.meReference)
    }

    func record(_ e: Entry) -> PhotoRecord {
        PhotoRecord(id: e.id, creationDate: e.creationDate, modificationDate: e.modificationDate, location: e.location,
                    isFavorite: e.isFavorite, pixelWidth: e.pixelWidth, pixelHeight: e.pixelHeight,
                    isScreenshot: e.isScreenshot, isAnimated: e.isAnimated, burstIdentifier: e.burstIdentifier)
    }
}

nonisolated struct FixturePhotoSource: PhotoSource {
    let fixtures: FixtureSet

    func authorizationStatus() -> LibraryAccess { .full }
    func requestAuthorization() async -> LibraryAccess { .full }

    func count(in range: DateInterval) async -> Int {
        fixtures.entries.filter { range.contains($0.creationDate) }.count
    }

    func records(in range: DateInterval) async throws -> [PhotoRecord] {
        fixtures.entries
            .filter { range.contains($0.creationDate) }
            .sorted { $0.creationDate < $1.creationDate }
            .map(fixtures.record)
    }

    func image(for id: String, longEdge: Double, allowNetwork: Bool) async throws -> CGImage {
        guard let entry = fixtures.entries.first(where: { $0.id == id }) else { throw PhotoSourceError.notFound }
        let url = fixtures.directory.appendingPathComponent(entry.file)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw PhotoSourceError.decodeFailed }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: longEdge]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw PhotoSourceError.decodeFailed }
        return image
    }
}
