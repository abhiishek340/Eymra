import Foundation
@testable import Eymra

/// Builders for synthetic inputs.
enum Make {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func photo(_ id: String, at seconds: TimeInterval, location: GeoPoint? = nil, favorite: Bool = false,
                      width: Int = 3024, height: Int = 4032, screenshot: Bool = false) -> PhotoRecord {
        PhotoRecord(id: id, creationDate: t0.addingTimeInterval(seconds), modificationDate: nil, location: location,
                    isFavorite: favorite, pixelWidth: width, pixelHeight: height, isScreenshot: screenshot,
                    burstIdentifier: nil)
    }

    static func feature(_ id: String, print: [Float] = [], faces: Int = 0, faceArea: Float = 0.1,
                        sharpness: Float = 300, aesthetic: Float? = 0.2, labels: [(String, Float)] = [],
                        saliency: NormRect? = NormRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
                        eyesClosed: Bool = false, dark: Float = 0.01, bright: Float = 0.005, utility: Bool = false,
                        quality: Float? = 0.6, thumb: [UInt8] = []) -> FeatureRecord {
        let side = faceArea.squareRoot()
        return FeatureRecord(
            photoID: id, schemaVersion: FeatureSchema.version, featurePrint: print, featurePrintRevision: 2,
            aestheticScore: aesthetic, isUtility: utility,
            faces: (0..<faces).map { i in
                FaceFeature(box: NormRect(x: 0.05 + Float(i) * 0.2, y: 0.3, width: side, height: side),
                            captureQuality: quality, eyesClosed: eyesClosed, smiling: false)
            },
            humanBoxes: [], saliencyBox: saliency,
            labels: labels.map { LabelScore(identifier: $0.0, confidence: $0.1) },
            horizonDegrees: nil, sharpness: sharpness, darkFraction: dark, brightFraction: bright,
            meanLuma: 120, thumb32: thumb)
    }

    /// Unit vector along `axis` with a small offset on axis+1, dimension 16.
    static func vector(_ axis: Int, offset: Float = 0, dim: Int = 16) -> [Float] {
        var v = [Float](repeating: 0, count: dim)
        v[axis % dim] = 1
        v[(axis + 1) % dim] = offset
        let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return v.map { $0 / n }
    }

    static func candidate(_ id: String, scene: String = "s", cluster: String? = nil, r: Float, category: Eymra.Category = .view,
                          print: [Float], at seconds: TimeInterval = 0) -> Selection.Candidate {
        Selection.Candidate(photoID: id, sceneID: scene, clusterID: cluster ?? "c-\(id)", relevance: r, category: category,
                            featurePrint: print, date: t0.addingTimeInterval(seconds))
    }
}
