import CoreGraphics
import Foundation
import Testing
@testable import Eymra

/// Runs the real image statistics and Vision pass on fixture images.
struct FeatureExtractorTests {
    private func image(_ file: String) async throws -> CGImage {
        let set = try FixtureSet.load()
        let id = try #require(set.entries.first { $0.file == file }?.id)
        return try await FixturePhotoSource(fixtures: set).image(for: id, longEdge: 1024, allowNetwork: false)
    }

    @Test func blurredFrameIsLessSharp() async throws {
        // fixture-07 is the blurred ridge frame, fixture-05 a sharp one from the same series.
        let sharp = try #require(ImageStats.compute(try await image("fixture-05.jpg")))
        let blurred = try #require(ImageStats.compute(try await image("fixture-07.jpg")))
        #expect(blurred.sharpness < sharp.sharpness / 4)
        #expect(sharp.thumb32.count == 1024)
    }

    @Test func darkFrameHasDarkPixels() async throws {
        // fixture-39 is the darkened sunset selfie, fixture-37 the normal one.
        let dark = try #require(ImageStats.compute(try await image("fixture-39.jpg")))
        let normal = try #require(ImageStats.compute(try await image("fixture-37.jpg")))
        #expect(dark.meanLuma < normal.meanLuma / 2)
        #expect(dark.darkFraction > normal.darkFraction)
    }

    @Test func visionPassAlwaysProducesARecord() async throws {
        // Even where Vision requests fail (the Simulator cannot build some inference contexts), the photo keeps
        // its image statistics and thumbnail instead of being excluded.
        let f = try await FeatureExtractor().analyse(try await image("fixture-05.jpg"), photoID: "x")
        #expect(f.featurePrintRevision == 2)
        #expect(f.thumb32.count == 1024)
        #expect(f.sharpness > 0)
        if f.featurePrint.isEmpty {
            withKnownIssue("No feature print on this Simulator; clustering uses thumbnails") { Issue.record("no feature print") }
        }
    }
}
