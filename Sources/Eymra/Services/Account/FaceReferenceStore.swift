import CoreGraphics
import Foundation
import os
import ImageIO
import UniformTypeIdentifiers

/// The user's face crops and prints, kept only on this phone (Application Support, excluded from backups).
nonisolated enum FaceReferenceStore {
    static var directory: URL {
        if let test = testDirectory.withLock({ $0 }) { return test }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Eymra/Face", isDirectory: true)
    }

    /// UI tests run inside the real app on a real phone, so they must never read, change or delete the owner's
    /// face scan: they use a fresh temporary folder instead.
    private static let testDirectory = OSAllocatedUnfairLock<URL?>(initialState: nil)

    static func useTemporaryDirectoryForTests() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EymraUITests-Face", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        testDirectory.withLock { $0 = url }
    }

    private static var referenceFile: URL { directory.appendingPathComponent("reference.json") }
    /// Length of a face signature from the bundled model.
    static let signatureLength = 128

    static func load() -> MeReference? {
        loadRaw()
    }

    private static func loadRaw() -> MeReference? {
        guard let data = try? Data(contentsOf: referenceFile),
              let reference = try? JSONDecoder().decode(MeReference.self, from: data),
              !reference.prints.isEmpty else { return nil }
        return reference
    }

    /// Saves face crops (as small JPEGs for the profile screen) and their prints. Replaces what was there.
    static func save(crops: [CGImage], prints: [[Float]]) throws {
        let kept = loadRaw()
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        for (i, crop) in crops.enumerated() {
            if let data = Renderer.jpeg(crop, longEdge: 300, quality: 0.85) {
                try data.write(to: directory.appendingPathComponent(String(format: "face-%02d.jpg", i)))
            }
        }
        let usable = prints.filter { !$0.isEmpty }
        // Keep "This is me" and "Not me" answers across rescans.
        let previous = kept
        try write(MeReference(prints: usable, version: MeReference.currentVersion,
                              confirmed: previous?.confirmed ?? [], notMe: previous?.notMe ?? []))
    }

    /// Adds your "This is me" and "Not me" answers.
    static func addAnswers(confirmed: [[Float]], notMe: [[Float]]) throws {
        guard var reference = load() else { return }
        reference.confirmed += confirmed.filter { !$0.isEmpty }
        reference.notMe += notMe.filter { !$0.isEmpty }
        try write(reference)
    }

    private static func write(_ reference: MeReference) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(reference).write(to: referenceFile)
    }

    static func faceImageURLs() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static var hasFaces: Bool { !faceImageURLs().isEmpty }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
