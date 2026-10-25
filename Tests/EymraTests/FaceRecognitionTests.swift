import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Eymra

private final class BundleToken {}

/// Where the real-face pairs are: EYMRA_FACE_PAIRS, else the local test folder bundled into the test target.
private func facePairsURL() -> URL? {
    if let path = ProcessInfo.processInfo.environment["EYMRA_FACE_PAIRS"] { return URL(fileURLWithPath: path) }
    return Bundle(for: BundleToken.self).url(forResource: "LocalFaces", withExtension: nil)?.appendingPathComponent("pairs.json")
}

private func imageURL(_ name: String, relativeTo pairs: URL) -> URL {
    name.hasPrefix("/") ? URL(fileURLWithPath: name) : pairs.deletingLastPathComponent().appendingPathComponent(name)
}

struct FaceRecognitionTests {
    @Test func similarityTransformRecoversAKnownTransform() throws {
        // Rotate 10°, scale 2, shift (5, -3): the fit must recover it exactly from noise-free points.
        let angle = 10.0 * .pi / 180, s = 2.0
        let truth = FaceAlignment.Similarity(a: s * cos(angle), b: s * sin(angle), tx: 5, ty: -3)
        let source = [FaceAlignment.Point(x: 1, y: 2), .init(x: 4, y: 1), .init(x: 3, y: 5), .init(x: 0, y: 7), .init(x: 6, y: 6)]
        let fit = try #require(FaceAlignment.similarity(from: source, to: source.map(truth.apply)))
        #expect(abs(fit.a - truth.a) < 1e-9 && abs(fit.b - truth.b) < 1e-9)
        #expect(abs(fit.tx - truth.tx) < 1e-9 && abs(fit.ty - truth.ty) < 1e-9)
    }

    @Test func orderingIsLeftToRight() throws {
        let p = try #require(FaceAlignment.ordered(eyes: [.init(x: 70, y: 50), .init(x: 30, y: 52)], nose: .init(x: 50, y: 70),
                                                    mouthCorners: [.init(x: 68, y: 90), .init(x: 35, y: 91)]))
        #expect(p.map(\.x) == [30, 70, 50, 35, 68])
    }

    @Test func modelLoadsAndGivesAUnitSignature() async throws {
        // A plain grey square through the full path: the model must load and return 128 unit-length numbers.
        let ctx = try #require(CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        let image = try #require(ctx.makeImage())
        let points = FaceAlignment.template.map { FaceAlignment.Point(x: $0.x + 44, y: $0.y + 44) }
        let sig = try #require(await FaceRecognizer.shared.signature(of: image, landmarks: points))
        #expect(sig.count == 128)
        #expect(abs(sig.reduce(0) { $0 + $1 * $1 } - 1) < 1e-3)
    }

    @Test func referencesThatDisagreeAreDropped() {
        let me = [Make.vector(0, offset: 0.1, dim: 16), Make.vector(0, offset: -0.1, dim: 16), Make.vector(0, dim: 16)]
        let stranger = Make.vector(8, dim: 16)
        let kept = Identity.consistentReferences(me + [stranger])
        #expect(kept.count == 3)
        #expect(!kept.contains(stranger))
    }

    /// Real faces (public LFW pairs with 5 landmarks, prepared outside the repo). Set EYMRA_FACE_PAIRS to the JSON path.
    /// Checks the Swift alignment + Core ML path against the Python reference, and accuracy at the app's threshold.
    @Test func realFacePairs() async throws {
        guard let url = facePairsURL(), let data = try? Data(contentsOf: url) else { return }   // not available: nothing to check
        struct Pair: Decodable { var a: String; var b: String; var same: Int; var la: [[Double]]; var lb: [[Double]]; var pythonCos: Double }
        let pairs = try JSONDecoder().decode([String: [Pair]].self, from: data)["pairs"] ?? []
        func load(_ p: String) -> CGImage? {
            guard let src = CGImageSourceCreateWithURL(imageURL(p, relativeTo: url) as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        var correct = 0, falseMatches = 0, missed = 0, total = 0
        var drift: [Double] = []
        for pair in pairs {
            guard let ia = load(pair.a), let ib = load(pair.b) else { continue }
            let pa = pair.la.map { FaceAlignment.Point(x: $0[0], y: $0[1]) }, pb = pair.lb.map { FaceAlignment.Point(x: $0[0], y: $0[1]) }
            guard let sa = await FaceRecognizer.shared.signature(of: ia, landmarks: pa),
                  let sb = await FaceRecognizer.shared.signature(of: ib, landmarks: pb),
                  let cos = Identity.similarity(sa, sb) else { continue }
            total += 1
            drift.append(abs(Double(cos) - pair.pythonCos))
            let match = cos >= Tuning.meSimilarity
            if match == (pair.same == 1) { correct += 1 } else if match { falseMatches += 1 } else { missed += 1 }
        }
        let accuracy = Double(correct) / Double(max(1, total))
        let meanDrift = drift.reduce(0, +) / Double(max(1, drift.count))
        let summary = "pairs \(total), accuracy \(accuracy), false matches \(falseMatches), missed \(missed), mean drift \(meanDrift)"
        if ProcessInfo.processInfo.environment["EYMRA_REPORT"] == "1" { Issue.record(Comment(rawValue: "REPORT " + summary)) }
        #expect(total >= 150, Comment(rawValue: summary))
        #expect(accuracy >= 0.95, Comment(rawValue: summary))
        #expect(falseMatches == 0, Comment(rawValue: summary))
        #expect(meanDrift < 0.05, Comment(rawValue: summary))
    }

    /// The whole on-device path on real faces: Vision finds faces and landmarks, then signatures are compared.
    /// Vision can't build its face models on some Simulators; then this only records that.
    @Test func realFacePairsWithVisionLandmarks() async throws {
        guard let url = facePairsURL(), let data = try? Data(contentsOf: url) else { return }
        struct Pair: Decodable { var a: String; var b: String; var same: Int }
        let pairs = try JSONDecoder().decode([String: [Pair]].self, from: data)["pairs"] ?? []
        func signature(_ p: String) async -> [Float]? {
            guard let src = CGImageSourceCreateWithURL(imageURL(p, relativeTo: url) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
                  let face = await FaceEmbedder.largestFace(in: image), !face.signature.isEmpty else { return nil }
            return face.signature
        }
        var correct = 0, falseMatches = 0, total = 0
        for pair in pairs {
            guard let a = await signature(pair.a), let b = await signature(pair.b), let cos = Identity.similarity(a, b) else { continue }
            total += 1
            let match = cos >= Tuning.meSimilarity
            if match == (pair.same == 1) { correct += 1 } else if match { falseMatches += 1 }
        }
        if total == 0 {
            withKnownIssue("Vision face landmarks unavailable on this Simulator") { Issue.record("no faces read") }
            return
        }
        let summary = "vision pairs \(total), accuracy \(Double(correct) / Double(total)), false matches \(falseMatches)"
        if ProcessInfo.processInfo.environment["EYMRA_REPORT"] == "1" { Issue.record(Comment(rawValue: "REPORT " + summary)) }
        #expect(Double(correct) / Double(total) >= 0.93, Comment(rawValue: summary))
        #expect(falseMatches <= 1, Comment(rawValue: summary))
    }
}
