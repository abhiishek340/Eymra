import Foundation

/// Recognising the user among the faces in a photo, from face signatures (unit vectors from the face model).
/// Two signatures of the same person have a high cosine similarity; different people sit near zero.
nonisolated enum Identity {
    static func similarity(_ a: [Float], _ b: [Float]) -> Float? {
        guard !a.isEmpty, a.count == b.count else { return nil }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in a.indices {
            guard a[i].isFinite, b[i].isFinite else { return nil }
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0, normA.isFinite, normB.isFinite, dot.isFinite else { return nil }
        return max(-1, min(1, (dot / normA.squareRoot()) / normB.squareRoot()))
    }

    /// Best similarity between a face and anything that counts as you.
    static func similarity(_ face: [Float], to reference: MeReference) -> Float? {
        reference.allPrints.compactMap { similarity(face, $0) }.max()
    }

    enum Verdict: Equatable { case me, maybe, notMe }

    /// Sure, unsure or not you, for one face. "Not me" answers win when the face is closer to them than to you.
    static func verdict(_ face: [Float], reference: MeReference) -> (Verdict, Float)? {
        guard let s = similarity(face, to: reference) else { return nil }
        if let n = reference.notMe.compactMap({ similarity(face, $0) }).max(), n >= Tuning.notMeSimilarity, n >= s {
            return (.notMe, s)
        }
        if s >= Tuning.meSure { return (.me, s) }
        if s >= Tuning.meMaybe { return (.maybe, s) }
        return (.notMe, s)
    }

    /// Which face in the photo is surely you: the best sure face (at most one per photo).
    /// nil means "not you", or no face could be compared; use `canTell` to tell these apart.
    static func meFace(in faces: [FaceFeature], reference: MeReference) -> Int? {
        var best: (index: Int, similarity: Float)?
        for (i, face) in faces.enumerated() {
            guard let (v, s) = verdict(face.print, reference: reference), v == .me else { continue }
            if best == nil || s > (best?.similarity ?? -1) { best = (i, s) }
        }
        return best?.index
    }

    /// The face that might be you, when none is sure.
    static func maybeFace(in faces: [FaceFeature], reference: MeReference) -> (index: Int, similarity: Float)? {
        var best: (index: Int, similarity: Float)?
        for (i, face) in faces.enumerated() {
            guard let (v, s) = verdict(face.print, reference: reference), v == .maybe else { continue }
            if best == nil || s > (best?.similarity ?? -1) { best = (i, s) }
        }
        return best
    }

    /// True when at least one face in the photo can be compared with the user.
    static func canTell(_ faces: [FaceFeature], reference: MeReference) -> Bool {
        faces.contains { face in reference.allPrints.contains { similarity(face.print, $0) != nil } }
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
