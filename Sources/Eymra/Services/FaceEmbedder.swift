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

    /// Signatures for the faces found in a photo, largest first up to the limit.
    ///
    /// Find, then zoom: faces are found on the small rendition, but each one is read from a square crop around it,
    /// taken from a sharper copy of the photo when the face is small (`zoom` fetches it), and enlarged before Vision
    /// looks for the eyes, nose and mouth. Tiny faces in group and scenic shots get enough pixels to be recognised.
    static func signatures(for faces: [FaceObservation], in image: CGImage, limit: Int = Tuning.maxFacePrints,
                           zoom: (@Sendable () async -> CGImage?)? = nil) async -> [[Float]] {
        guard !faces.isEmpty else { return [] }
        let boxes = faces.map { FeatureExtractor.upperLeft($0.boundingBox.cgRect) }
        let order = boxes.indices.sorted { boxes[$0].width > boxes[$1].width }.prefix(limit)
        let smallest = order.map { CGFloat(boxes[$0].width) * CGFloat(image.width) }.min() ?? 0
        var source = image
        if smallest < Tuning.zoomBelowPixels, let zoom, let sharper = await zoom(), sharper.width > image.width {
            source = sharper
        }
        var out = faces.map { _ in [Float]() }
        for i in order {
            let facePixels = CGFloat(boxes[i].width) * CGFloat(source.width)
            guard facePixels >= Tuning.minFacePixels,
                  let crop = zoomedCrop(source, face: boxes[i]),
                  let signature = await signatureOfCentralFace(in: crop) else { continue }
            out[i] = signature
        }
        return out
    }

    /// The user's face in a photo or camera frame: the largest face, its crop for display, and its signature.
    static func largestFace(in image: CGImage) async -> (crop: CGImage, signature: [Float])? {
        let handler = ImageRequestHandler(image, orientation: .up)
        guard let faces = try? await handler.perform(DetectFaceRectanglesRequest()),
              let face = faces.max(by: { $0.boundingBox.cgRect.width < $1.boundingBox.cgRect.width }) else { return nil }
        let box = FeatureExtractor.upperLeft(face.boundingBox.cgRect)
        guard let display = crop(image, face: box) else { return nil }
        let signature = await zoomedCrop(image, face: box).asyncMap { await signatureOfCentralFace(in: $0) } ?? nil
        return (display, signature ?? [])
    }

    /// A square around the face (2.2× its size), enlarged so the face is at least ~180 px wide.
    static func zoomedCrop(_ image: CGImage, face box: NormRect) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let side = CGFloat(max(box.width * Float(w), box.height * Float(h))) * 2.2
        let rect = CGRect(x: CGFloat(box.midX) * w - side / 2, y: CGFloat(box.midY) * h - side / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        guard rect.width >= 16, rect.height >= 16, let cut = image.cropping(to: rect) else { return nil }
        let target = max(CGFloat(cut.width), 400)
        guard target > CGFloat(cut.width) else { return cut }
        let scale = target / CGFloat(cut.width)
        let tw = Int(target), th = Int(CGFloat(cut.height) * scale)
        guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return cut }
        ctx.interpolationQuality = .high
        ctx.draw(cut, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage() ?? cut
    }

    /// Finds the face nearest the centre of a face crop, its landmarks, and its signature.
    static func signatureOfCentralFace(in crop: CGImage) async -> [Float]? {
        let handler = ImageRequestHandler(crop, orientation: .up)
        guard let faces = try? await handler.perform(DetectFaceRectanglesRequest()), !faces.isEmpty else { return nil }
        let centre = CGPoint(x: 0.5, y: 0.5)
        let face = faces.min { a, b in
            hypot(a.boundingBox.cgRect.midX - centre.x, a.boundingBox.cgRect.midY - centre.y)
                < hypot(b.boundingBox.cgRect.midX - centre.x, b.boundingBox.cgRect.midY - centre.y)
        }
        guard let face else { return nil }
        var request = DetectFaceLandmarksRequest()
        request.inputFaceObservations = [face]
        guard let landmarked = try? await handler.perform(request).first,
              let points = fivePoints(landmarked, imageSize: CGSize(width: crop.width, height: crop.height)) else { return nil }
        return await FaceRecognizer.shared.signature(of: crop, landmarks: points)
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
    /// The mirror trick: the face and its mirror image are both read and averaged, which steadies turned faces.
    func signature(of image: CGImage, landmarks: [FaceAlignment.Point]) -> [Float]? {
        guard let transform = FaceAlignment.similarity(from: landmarks),
              let buffer = Self.alignedBuffer(image, transform),
              let plain = embed(buffer) else { return nil }
        var values = plain
        if let mirrored = Self.alignedBuffer(image, transform, mirrored: true), let other = embed(mirrored) {
            values = zip(plain, other).map { $0 + $1 }
        }
        let norm = values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return nil }
        return values.map { $0 / norm }
    }

    private func embed(_ buffer: CVPixelBuffer) -> [Float]? {
        guard let first = loadedModel() else { return nil }
        let output: FaceEmbeddingOutput
        do {
            output = try first.prediction(face: buffer)
        } catch {
            Self.log.error("Face model prediction failed, retrying on CPU: \(error.localizedDescription, privacy: .public)")
            guard let cpu = loadedModel(cpuOnly: true), let retry = try? cpu.prediction(face: buffer) else { return nil }
            output = retry
        }
        let array = output.embedding
        return (0..<array.count).map { Float(truncating: array[$0]) }
    }

    /// Draws the image through the similarity transform into a 112×112 BGRA pixel buffer.
    static func alignedBuffer(_ image: CGImage, _ t: FaceAlignment.Similarity, mirrored: Bool = false) -> CVPixelBuffer? {
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
        let mirror = mirrored ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: s, ty: 0) : .identity
        ctx.concatenate(toUpperLeft.concatenating(align).concatenating(mirror).concatenating(toBottomLeft))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: h))
        return buffer
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let value = self else { return nil }
        return await transform(value)
    }
}
