import CoreGraphics
import CoreImage
import Foundation
import Vision
import os

/// Stage 2 on device: one decode and one packed Vision pass per photo.
nonisolated struct FeatureExtractor: FeatureExtracting {
    private static let log = Logger(subsystem: "app.eymra", category: "features")

    var featurePrintRevision: Int {
        // The Swift API exposes only revision 2 in this SDK; a future revision gets a distinct number.
        GenerateImageFeaturePrintRequest().revision == .revision2 ? 2 : 3
    }

    @concurrent
    func extract(_ record: PhotoRecord, from source: any PhotoSource, allowNetwork: Bool) async throws -> FeatureRecord {
        try Task.checkCancellation()
        let image = try await source.image(for: record.id, longEdge: Tuning.renditionLongEdge, allowNetwork: allowNetwork)
        return try await analyse(image, photoID: record.id)
    }

    func analyse(_ image: CGImage, photoID: String) async throws -> FeatureRecord {
        let handler = ImageRequestHandler(image, orientation: .up)
        // Core pack: one call so the image is prepared once.
        let print: FeaturePrintObservation?
        let faces: [FaceObservation], humans: [HumanObservation], labels: [ClassificationObservation]
        let saliency: SaliencyImageObservation?
        do {
            (print, faces, humans, saliency, labels) = try await handler.perform(
                GenerateImageFeaturePrintRequest(),
                DetectFaceRectanglesRequest(),
                DetectHumanRectanglesRequest(),
                GenerateAttentionBasedSaliencyImageRequest(),
                ClassifyImageRequest())
        } catch {
            // A pack throws as a whole. Where one request cannot build an inference context (seen on the
            // Simulator), retry each on its own so a failure costs only that signal; a missing feature print
            // falls back to thumbnail similarity in clustering.
            Self.log.info("Core pack failed, retrying requests singly: \(String(describing: error), privacy: .public)")
            print = try? await handler.perform(GenerateImageFeaturePrintRequest())
            faces = (try? await handler.perform(DetectFaceRectanglesRequest())) ?? []
            humans = (try? await handler.perform(DetectHumanRectanglesRequest())) ?? []
            saliency = try? await handler.perform(GenerateAttentionBasedSaliencyImageRequest())
            labels = (try? await handler.perform(ClassifyImageRequest())) ?? []
        }
        // Optional requests run on their own so a failure costs only that signal.
        let aesthetics = try? await handler.perform(CalculateImageAestheticsScoresRequest())
        let horizon = (try? await handler.perform(DetectHorizonRequest())) ?? nil

        var qualities: [Float?] = faces.map { _ in nil }
        if !faces.isEmpty {
            var quality = DetectFaceCaptureQualityRequest()
            quality.inputFaceObservations = faces
            if let rated = try? await handler.perform(quality), rated.count == faces.count {
                qualities = rated.map { $0.captureQuality?.score }
            }
        }
        let expressions = faces.isEmpty ? [] : Self.expressions(in: image)

        let facePrints = await FaceEmbedder.signatures(for: faces, in: image)
        let faceFeatures: [FaceFeature] = faces.enumerated().map { i, face in
            let box = Self.upperLeft(face.boundingBox.cgRect)
            let match = expressions.max { $0.box.intersectionArea(box) < $1.box.intersectionArea(box) }
            let overlaps = match.map { $0.box.intersectionArea(box) > 0 } ?? false
            return FaceFeature(box: box, captureQuality: qualities[i],
                               eyesClosed: overlaps ? (match?.eyesClosed ?? false) : false,
                               smiling: overlaps ? (match?.smiling ?? false) : false,
                               print: facePrints.indices.contains(i) ? facePrints[i] : [])
        }
        let salient = (saliency?.salientObjects ?? []).map { Self.upperLeft($0.boundingBox.cgRect) }
        let saliencyBox = salient.dropFirst().reduce(salient.first) { $0?.union($1) }
        let topLabels = labels
            .filter { $0.confidence > Tuning.labelMinConfidence }
            .sorted { $0.confidence > $1.confidence }
            .prefix(Tuning.maxLabels)
            .map { LabelScore(identifier: $0.identifier, confidence: $0.confidence) }

        guard let stats = ImageStats.compute(image) else { throw PhotoSourceError.decodeFailed }
        return FeatureRecord(
            photoID: photoID, schemaVersion: FeatureSchema.version,
            featurePrint: print.map(Self.floats) ?? [], featurePrintRevision: featurePrintRevision,
            aestheticScore: aesthetics?.overallScore, isUtility: aesthetics?.isUtility ?? false,
            faces: faceFeatures, humanBoxes: humans.map { Self.upperLeft($0.boundingBox.cgRect) },
            saliencyBox: saliencyBox, labels: Array(topLabels),
            horizonDegrees: horizon.map { Float($0.angle.converted(to: .degrees).value) },
            sharpness: stats.sharpness, darkFraction: stats.darkFraction, brightFraction: stats.brightFraction,
            meanLuma: stats.meanLuma, thumb32: stats.thumb32)
    }

    /// Feature print values as Float32, reading the element type rather than assuming a size.
    static func floats(_ print: FeaturePrintObservation) -> [Float] {
        switch print.elementType {
        case .float:
            return print.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(print.elementCount)) }
        case .double:
            return print.data.withUnsafeBytes { $0.bindMemory(to: Double.self).prefix(print.elementCount).map { Float($0) } }
        @unknown default:
            return []
        }
    }

    /// Vision rects are lower-left origin; the app stores upper-left.
    static func upperLeft(_ r: CGRect) -> NormRect {
        NormRect(x: Float(r.minX), y: Float(1 - r.maxY), width: Float(r.width), height: Float(r.height))
    }

    private struct Expression {
        var box: NormRect
        var eyesClosed: Bool
        var smiling: Bool
    }

    /// Blink and smile from Core Image (Vision has neither). CIDetector is not Sendable, so one is made per call.
    private static func expressions(in image: CGImage) -> [Expression] {
        let ci = CIImage(cgImage: image)
        guard let detector = CIDetector(ofType: CIDetectorTypeFace, context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return [] }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        return detector.features(in: ci, options: [CIDetectorEyeBlink: true, CIDetectorSmile: true])
            .compactMap { $0 as? CIFaceFeature }
            .map { f in
                let r = CGRect(x: f.bounds.minX / w, y: f.bounds.minY / h, width: f.bounds.width / w, height: f.bounds.height / h)
                return Expression(box: upperLeft(r), eyesClosed: f.leftEyeClosed && f.rightEyeClosed, smiling: f.hasSmile)
            }
    }
}
