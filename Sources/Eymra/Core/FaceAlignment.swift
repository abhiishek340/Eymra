import Foundation

/// 5-point face alignment for the face-recognition model: a least-squares similarity transform
/// (scale, rotation, translation) that maps the eyes, nose and mouth corners onto the standard
/// 112×112 template the model was trained on.
nonisolated enum FaceAlignment {
    struct Point: Sendable, Hashable {
        var x: Double
        var y: Double
    }

    /// x' = a·x − b·y + tx,  y' = b·x + a·y + ty
    struct Similarity: Sendable, Hashable {
        var a: Double
        var b: Double
        var tx: Double
        var ty: Double

        func apply(_ p: Point) -> Point {
            Point(x: a * p.x - b * p.y + tx, y: b * p.x + a * p.y + ty)
        }

        var scale: Double { (a * a + b * b).squareRoot() }
    }

    static let size = 112.0
    /// Image-left eye, image-right eye, nose tip, image-left mouth corner, image-right mouth corner (upper-left origin).
    static let template: [Point] = [
        Point(x: 38.2946, y: 51.6963), Point(x: 73.5318, y: 51.5014), Point(x: 56.0252, y: 71.7366),
        Point(x: 41.5493, y: 92.3655), Point(x: 70.7299, y: 92.2041),
    ]

    /// Least-squares similarity transform from `source` to `target` (same count, at least 2 points).
    static func similarity(from source: [Point], to target: [Point] = template) -> Similarity? {
        guard source.count == target.count, source.count >= 2 else { return nil }
        let n = Double(source.count)
        let sx = source.map(\.x).reduce(0, +) / n, sy = source.map(\.y).reduce(0, +) / n
        let tx = target.map(\.x).reduce(0, +) / n, ty = target.map(\.y).reduce(0, +) / n
        var num1 = 0.0, num2 = 0.0, den = 0.0
        for (s, t) in zip(source, target) {
            let px = s.x - sx, py = s.y - sy, qx = t.x - tx, qy = t.y - ty
            num1 += px * qx + py * qy
            num2 += px * qy - py * qx
            den += px * px + py * py
        }
        guard den > 1e-9 else { return nil }
        let a = num1 / den, b = num2 / den
        return Similarity(a: a, b: b, tx: tx - (a * sx - b * sy), ty: ty - (b * sx + a * sy))
    }

    /// Orders raw landmark points the way the template expects: eyes and mouth corners left to right by x.
    static func ordered(eyes: [Point], nose: Point, mouthCorners: [Point]) -> [Point]? {
        guard eyes.count == 2, mouthCorners.count == 2 else { return nil }
        let e = eyes.sorted { $0.x < $1.x }, m = mouthCorners.sorted { $0.x < $1.x }
        return [e[0], e[1], nose, m[0], m[1]]
    }
}
