import Foundation

/// Recognising the user among the faces in a photo, from face-crop feature prints.
///
/// There is no public face-recognition model on iOS, so this compares Vision feature prints of face crops
/// against the user's own reference prints (several head angles from the face scan). The match threshold
/// adapts to the user's references: the spread between their own angles sets the scale of "same person".
nonisolated enum Identity {
    /// Distance under which a face counts as the user.
    static func threshold(for reference: MeReference) -> Float {
        let prints = reference.prints.filter { !$0.isEmpty }
        guard prints.count >= 2 else { return Tuning.meDistanceDefault }
        var sum: Float = 0, n: Float = 0
        for i in prints.indices {
            for j in prints.indices where j > i {
                if let d = VectorMath.distance(prints[i], prints[j]) { sum += d; n += 1 }
            }
        }
        guard n > 0 else { return Tuning.meDistanceDefault }
        return min(Tuning.meDistanceMax, max(Tuning.meDistanceMin, sum / n * Tuning.meSpreadFactor))
    }

    /// Closest distance from a face print to any reference print.
    static func distance(_ face: [Float], to reference: MeReference) -> Float? {
        reference.prints.compactMap { VectorMath.distance(face, $0) }.min()
    }

    /// Which face in the photo is the user, if any: the closest face under the threshold (at most one per photo).
    /// Returns nil for "not in the photo" and also when no face has a print; use `canTell` to tell these apart.
    static func meFace(in faces: [FaceFeature], reference: MeReference, threshold: Float) -> Int? {
        var best: (index: Int, distance: Float)?
        for (i, face) in faces.enumerated() {
            guard let d = distance(face.print, to: reference), d < threshold else { continue }
            if best == nil || d < (best?.distance ?? .infinity) { best = (i, d) }
        }
        return best?.index
    }

    /// True when at least one face in the photo can be compared with the user.
    static func canTell(_ faces: [FaceFeature], reference: MeReference) -> Bool {
        faces.contains { face in reference.prints.contains { VectorMath.distance(face.print, $0) != nil } }
    }
}
