import CoreGraphics
import Foundation
import Vision

/// Face crops and their feature prints, shared by photo analysis and the user's face setup.
nonisolated enum FaceEmbedder {
    /// Square crop around a face (upper-left normalised box) with a margin, clamped to the image.
    static func crop(_ image: CGImage, face box: NormRect, margin: Float = Tuning.faceCropMargin) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let side = CGFloat(max(box.width * Float(w), box.height * Float(h)) * (1 + 2 * margin))
        let cx = CGFloat(box.midX) * w, cy = CGFloat(box.midY) * h
        let rect = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        guard rect.width >= 16, rect.height >= 16 else { return nil }
        return image.cropping(to: rect)
    }

    /// Feature print of an image (a face crop), as Float32 values; nil when Vision can't run.
    static func print(of image: CGImage) async -> [Float]? {
        let handler = ImageRequestHandler(image, orientation: .up)
        guard let observation = try? await handler.perform(GenerateImageFeaturePrintRequest()) else { return nil }
        let values = FeatureExtractor.floats(observation)
        return values.isEmpty ? nil : values
    }

    /// Prints for the largest faces in a photo, in the order of `faces`. Faces beyond the limit get none.
    static func prints(for faces: [NormRect], in image: CGImage, limit: Int = Tuning.maxFacePrints) async -> [[Float]] {
        let largest = Set(faces.indices.sorted { faces[$0].area > faces[$1].area }.prefix(limit))
        var out: [[Float]] = []
        for (i, box) in faces.enumerated() {
            if largest.contains(i), let crop = crop(image, face: box), let p = await print(of: crop) {
                out.append(p)
            } else {
                out.append([])
            }
        }
        return out
    }

    /// The user's face in a photo they chose: the largest face, cropped, with its print.
    static func largestFace(in image: CGImage) async -> (crop: CGImage, print: [Float])? {
        let handler = ImageRequestHandler(image, orientation: .up)
        guard let faces = try? await handler.perform(DetectFaceRectanglesRequest()),
              let face = faces.max(by: { $0.boundingBox.cgRect.width < $1.boundingBox.cgRect.width }) else { return nil }
        let box = FeatureExtractor.upperLeft(face.boundingBox.cgRect)
        guard let crop = crop(image, face: box) else { return nil }
        return (crop, await print(of: crop) ?? [])
    }
}
