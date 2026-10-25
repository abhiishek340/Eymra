import Foundation

/// Recognising the user among the faces in a photo, from face signatures (unit vectors from the face model).
/// Two signatures of the same person have a high cosine similarity; different people sit near zero.
nonisolated enum Identity {
    static func similarity(_ a: [Float], _ b: [Float]) -> Float? {
        guard !a.isEmpty, a.count == b.count else { return nil }
        var dot: Float = 0
        for i in a.indices { dot += a[i] * b[i] }
        return dot
    }

    /// Best similarity between a face and any of the user's reference signatures.
    static func similarity(_ face: [Float], to reference: MeReference) -> Float? {
        reference.prints.compactMap { similarity(face, $0) }.max()
    }

    /// Which face in the photo is the user: the most similar face at or above the threshold (at most one per photo).
    /// nil means "not in the photo", or no face could be compared; use `canTell` to tell these apart.
    static func meFace(in faces: [FaceFeature], reference: MeReference, threshold: Float = Tuning.meSimilarity) -> Int? {
        var best: (index: Int, similarity: Float)?
        for (i, face) in faces.enumerated() {
            guard let s = similarity(face.print, to: reference), s >= threshold else { continue }
            if best == nil || s > (best?.similarity ?? -1) { best = (i, s) }
        }
        return best?.index
    }

    /// True when at least one face in the photo can be compared with the user.
    static func canTell(_ faces: [FaceFeature], reference: MeReference) -> Bool {
        faces.contains { face in reference.prints.contains { similarity(face.print, $0) != nil } }
    }

    /// Keeps reference signatures that agree with each other, so a stray face (someone walking past during the scan,
    /// a friend in a chosen photo) doesn't become part of "you". The anchor is the signature most similar to the rest.
    static func consistentReferences(_ prints: [[Float]], minimum: Float = Tuning.enrolConsistency) -> [[Float]] {
        let usable = prints.filter { !$0.isEmpty }
        guard usable.count > 1 else { return usable }
        let support = usable.map { a in usable.compactMap { similarity(a, $0) }.reduce(0, +) }
        guard let anchor = support.indices.max(by: { support[$0] < support[$1] }) else { return usable }
        return usable.filter { (similarity($0, usable[anchor]) ?? -1) >= minimum }
    }
}
