import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Vision
import os

/// Face signatures for recognising the user: Vision finds the eyes, nose and mouth, the face is aligned to the
/// model's 112×112 template, and the bundled SFace model turns it into 128 numbers (L2-normalised).
/// Faces without landmarks, or too small to read, get no signature: "can't tell" beats a wrong guess.
nonisolated enum FaceEmbedder {
    private static let log = Logger(subsystem: "app.eymra", category: "faces")

    struct Face: Sendable {
        /// Upper-left normalised box.
        var box: NormRect
        /// 128-d unit vector, or empty when the face couldn't be read.
        var signature: [Float]
    }

    /// Signatures for the given faces (Vision observations from the same image), largest first up to the limit.
    static func signatures(for faces: [FaceObservation], in image: CGImage, limit: Int = Tuning.maxFacePrints) async -> [[Float]] {
        guard !faces.isEmpty else { return [] }
        let width = Double(image.width), height = Double(image.height)
        let readable = faces.indices
            .filter { faces[$0].boundingBox.cgRect.width * width >= Tuning.minFacePixels }
            .sorted { faces[$0].boundingBox.cgRect.width > faces[$1].boundingBox.cgRect.width }
            .prefix(limit)
        guard !readable.isEmpty else { return faces.map { _ in [] } }

        var request = DetectFaceLandmarksRequest()
        request.inputFaceObservations = readable.map { faces[$0] }
        let handler = ImageRequestHandler(image, orientation: .up)
        guard let landmarked = try? await handler.perform(request) else { return faces.map { _ in [] } }

        var out = faces.map { _ in [Float]() }
        for (slot, face) in zip(readable, landmarked) {
            guard let points = fivePoints(face, imageSize: CGSize(width: width, height: height)),
                  let signature = await FaceRecognizer.shared.signature(of: image, landmarks: points) else { continue }
            out[slot] = signature
        }
        return out
    }

    /// The user's face in a photo or camera frame: the largest face, its crop for display, and its signature.
    static func largestFace(in image: CGImage) async -> (crop: CGImage, signature: [Float])? {
        let handler = ImageRequestHandler(image, orientation: .up)
        guard let faces = try? await handler.perform(DetectFaceRectanglesRequest()),
              let face = faces.max(by: { $0.boundingBox.cgRect.width < $1.boundingBox.cgRect.width }),
              let crop = crop(image, face: FeatureExtractor.upperLeft(face.boundingBox.cgRect)) else { return nil }
        let signature = await signatures(for: [face], in: image, limit: 1).first ?? []
        return (crop, signature)
    }

    /// Eyes, nose and mouth corners in image pixels (upper-left origin), ordered for the template.
    static func fivePoints(_ face: FaceObservation, imageSize: CGSize) -> [FaceAlignment.Point]? {
        guard let landmarks = face.landmarks else { return nil }
        func pts(_ region: FaceObservation.Landmarks2D.Region) -> [FaceAlignment.Point] {
            region.pointsInImageCoordinates(imageSize, origin: .upperLeft).map { FaceAlignment.Point(x: $0.x, y: $0.y) }
        }
        func centre(_ p: [FaceAlignment.Point]) -> FaceAlignment.Point? {
            guard !p.isEmpty else { return nil }
            return FaceAlignment.Point(x: p.map(\.x).reduce(0, +) / Double(p.count), y: p.map(\.y).reduce(0, +) / Double(p.count))
        }
        let leftEye = centre(pts(landmarks.leftPupil)) ?? centre(pts(landmarks.leftEye))
        let rightEye = centre(pts(landmarks.rightPupil)) ?? centre(pts(landmarks.rightEye))
        let lips = pts(landmarks.outerLips)
        guard let leftEye, let rightEye, let nose = centre(pts(landmarks.nose)),
              let mouthLeft = lips.min(by: { $0.x < $1.x }), let mouthRight = lips.max(by: { $0.x < $1.x }) else { return nil }
        return FaceAlignment.ordered(eyes: [leftEye, rightEye], nose: nose, mouthCorners: [mouthLeft, mouthRight])
    }

    /// Square crop around a face with a margin, for showing the user their face.
    static func crop(_ image: CGImage, face box: NormRect, margin: Float = Tuning.faceCropMargin) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let side = CGFloat(max(box.width * Float(w), box.height * Float(h)) * (1 + 2 * margin))
        let cx = CGFloat(box.midX) * w, cy = CGFloat(box.midY) * h
        let rect = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        guard rect.width >= 16, rect.height >= 16 else { return nil }
        return image.cropping(to: rect)
    }
}

/// Runs the bundled face model. An actor so one model instance is used one face at a time.
actor FaceRecognizer {
    static let shared = FaceRecognizer()
    private static let log = Logger(subsystem: "app.eymra", category: "faces")
    private var model: FaceEmbedding?
    private var loadFailed = false

    private func loadedModel(cpuOnly: Bool = false) -> FaceEmbedding? {
        if let model, !cpuOnly { return model }
        guard !loadFailed else { return nil }
        do {
            let config = MLModelConfiguration()
            #if targetEnvironment(simulator)
            config.computeUnits = .cpuOnly   // the Simulator has no Neural Engine and its GPU path fails for this model
            #else
            config.computeUnits = cpuOnly ? .cpuOnly : .all
            #endif
            model = try FaceEmbedding(configuration: config)
        } catch {
            loadFailed = true
            Self.log.error("Face model failed to load: \(error.localizedDescription, privacy: .public)")
        }
        return model
    }

    /// Aligns the face to 112×112 with the 5 landmarks and returns its unit-length signature.
    func signature(of image: CGImage, landmarks: [FaceAlignment.Point]) -> [Float]? {
        guard let transform = FaceAlignment.similarity(from: landmarks),
              let buffer = Self.alignedBuffer(image, transform),
              let first = loadedModel() else { return nil }
        let output: FaceEmbeddingOutput
        do {
            output = try first.prediction(face: buffer)
        } catch {
            Self.log.error("Face model prediction failed, retrying on CPU: \(error.localizedDescription, privacy: .public)")
            guard let cpu = loadedModel(cpuOnly: true), let retry = try? cpu.prediction(face: buffer) else { return nil }
            output = retry
        }
        let array = output.embedding
        var values = (0..<array.count).map { Float(truncating: array[$0]) }
        let norm = values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return nil }
        values = values.map { $0 / norm }
        return values
    }

    /// Draws the image through the similarity transform into a 112×112 BGRA pixel buffer.
    static func alignedBuffer(_ image: CGImage, _ t: FaceAlignment.Similarity) -> CVPixelBuffer? {
        let side = Int(FaceAlignment.size)
        var buffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, side, side, kCVPixelFormatType_32BGRA, attrs, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.interpolationQuality = .high
        // The transform works in upper-left pixel coordinates; Core Graphics draws bottom-left up.
        let h = CGFloat(image.height), s = CGFloat(side)
        let toUpperLeft = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        let align = CGAffineTransform(a: t.a, b: t.b, c: -t.b, d: t.a, tx: t.tx, ty: t.ty)
        let toBottomLeft = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: s)
        ctx.concatenate(toUpperLeft.concatenating(align).concatenating(toBottomLeft))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: h))
        return buffer
    }
}
