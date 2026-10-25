import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Eymra

/// What the judge receives must carry pixels only: no GPS, EXIF dates or camera data.
struct PrivacyTests {
    private func fixtureImage() throws -> (CGImage, CFDictionary?) {
        let set = try FixtureSet.load()
        let url = set.directory.appendingPathComponent(try #require(set.entries.first?.file))
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return (try #require(CGImageSourceCreateImageAtIndex(src, 0, nil)), CGImageSourceCopyPropertiesAtIndex(src, 0, nil))
    }

    @Test func fixtureHasMetadataToStrip() throws {
        let (_, props) = try fixtureImage()
        let dict = try #require(props as? [CFString: Any])
        #expect(dict[kCGImagePropertyGPSDictionary] != nil)
        #expect(dict[kCGImagePropertyExifDictionary] != nil)
    }

    @Test func rendererStripsAllMetadata() throws {
        let (image, _) = try fixtureImage()
        let jpeg = try #require(Renderer.jpeg(image, longEdge: 756, quality: 0.75))
        let src = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        #expect(props[kCGImagePropertyTIFFDictionary] == nil)
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] == nil)
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        #expect(max(w, h) == 756)
    }

    @Test func cropMatchesRatio() throws {
        let (image, _) = try fixtureImage()
        let cropped = try #require(Renderer.crop(image, ratio: .vertical9x16, saliency: nil))
        #expect(abs(Double(cropped.width) / Double(cropped.height) - 9.0 / 16.0) < 0.01)
    }

    @Test func judgeRequestCarriesNoIdentifiers() throws {
        let judge = ClaudeJudge(model: "m", apiKey: "k")
        let body = judge.requestBody(images: [JudgeImage(photoID: "SECRET-LOCAL-ID", jpeg: Data([0xFF]))],
                                     instruction: "x", schema: [:], maxTokens: 10)
        let text = String(data: try JSONSerialization.data(withJSONObject: body), encoding: .utf8) ?? ""
        #expect(!text.contains("SECRET-LOCAL-ID"))
    }
}
