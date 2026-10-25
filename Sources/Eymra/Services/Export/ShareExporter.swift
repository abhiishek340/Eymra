import Foundation

/// Renders picks to temporary metadata-free JPEG files for the share sheet, in posting order.
nonisolated enum ShareExporter {
    static func files(for photoIDs: [String], source: any PhotoSource, longEdge: Int = 2048) async throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("eymra-share", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (i, id) in photoIDs.enumerated() {
            try Task.checkCancellation()
            let image = try await source.image(for: id, longEdge: Double(longEdge), allowNetwork: true)
            guard let data = Renderer.jpeg(image, longEdge: longEdge, quality: 0.9) else { continue }
            let url = dir.appendingPathComponent(String(format: "eymra-%02d.jpg", i + 1))
            try data.write(to: url)
            urls.append(url)
        }
        return urls
    }
}
