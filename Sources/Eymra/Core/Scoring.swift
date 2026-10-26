import Foundation

/// Stage 5: hard rejects, relative sub-scores, quality Q, categories and cluster winners.
nonisolated enum Scoring {
    struct Output: Sendable {
        var scores: [String: PhotoScore]
        var clusters: [Cluster]
        var excluded: [String: ExclusionTag]
    }

    /// - Parameter groups: near-duplicate member groups with the scene they belong to.
    static func score(photos: [String: PhotoRecord],
                      features: [String: FeatureRecord],
                      scenes: [Scene],
                      groups: [(sceneID: String, members: [String])],
                      primaryRatio: AspectRatio,
                      me profile: MeReference? = nil) -> Output {
        let ids = groups.flatMap(\.members).filter { features[$0] != nil && photos[$0] != nil }
        let me = profile.map { p in Identity.runReference(p, faces: ids.flatMap { features[$0]?.faces.map(\.print) ?? [] }) }
        let groupOf: [String: Int] = Dictionary(uniqueKeysWithValues: groups.enumerated().flatMap { gi, g in
            g.members.map { ($0, gi) }
        })

        // Relative ranks.
        var sharpnessRank: [String: Float] = [:]
        for scene in scenes {
            let members = scene.photoIDs.filter { features[$0] != nil }
            let ranks = percentiles(members.map { features[$0]?.sharpness ?? 0 })
            for (i, id) in members.enumerated() { sharpnessRank[id] = members.count == 1 ? 0.5 : ranks[i] }
        }
        let aestheticIDs = ids.filter { features[$0]?.aestheticScore != nil }
        let aestheticRanks = percentiles(aestheticIDs.map { features[$0]?.aestheticScore ?? 0 })
        var aestheticRank: [String: Float] = [:]
        for (i, id) in aestheticIDs.enumerated() { aestheticRank[id] = aestheticIDs.count == 1 ? 0.5 : aestheticRanks[i] }

        var scores: [String: PhotoScore] = [:]
        var excluded: [String: ExclusionTag] = [:]

        for id in ids {
            guard let f = features[id], let p = photos[id] else { continue }
            let groupSize = groupOf[id].map { groups[$0].members.count } ?? 1
            let s = sharpnessRank[id] ?? 0.5
            let t = technical(sharpnessRank: s, feature: f)
            let a = aestheticRank[id] ?? 0.5
            var fits: [AspectRatio: Float] = [:]
            for ratio in AspectRatio.allCases {
                fits[ratio] = cropFit(ratio: ratio, imageAspect: p.aspect, saliency: f.saliencyBox)
            }
            let c = composition(cropFit: fits[primaryRatio] ?? 1, saliency: f.saliencyBox)
            // Who is in it: the user's face index, or nil; withMe is nil when we can't tell.
            var meIndex: Int?
            var withMe: Bool?
            if let me, !f.faces.isEmpty, Identity.canTell(f.faces, reference: me) {
                meIndex = Identity.meFace(in: f.faces, reference: me)
                withMe = meIndex != nil
            }
            let people = f.faces.isEmpty ? nil : peopleScore(f.faces, meIndex: meIndex)
            var q: Float
            if let people {
                let w = Tuning.weightsWithFaces
                q = w.t * t + w.a * a + w.c * c + w.p * people
            } else {
                let w = Tuning.weightsNoFaces
                q = w.t * t + w.a * a + w.c * c
            }
            if p.isFavorite { q += Tuning.favoriteBonus }
            q = clamp(q)

            var tag: ExclusionTag?
            if f.isUtility || p.isScreenshot {
                tag = .screenshot
            } else if p.shortEdge < Tuning.minShortEdge {
                tag = .tooSmall
            } else if groupSize > 1 {
                if s <= Tuning.blurryPercentile && f.sharpness < Tuning.blurryMaxVariance {
                    tag = .blurry
                } else if f.darkFraction > Tuning.tooDarkFraction {
                    tag = .tooDark
                } else if f.brightFraction > Tuning.blownOutFraction {
                    tag = .blownOut
                } else if allEyesClosed(f), let gi = groupOf[id],
                          groups[gi].members.contains(where: { $0 != id && features[$0].map { !allEyesClosed($0) } ?? false }) {
                    tag = .eyesClosed
                }
            }
            if let tag { excluded[id] = tag }
            scores[id] = PhotoScore(photoID: id, technical: t, aesthetic: a, composition: c, people: people,
                                    quality: q, cropFit: fits, category: CategoryRules.category(for: f, withMe: withMe),
                                    exclusion: tag, withMe: withMe)
        }

        // Winners: highest Q among surviving members; ties on later capture, then identifier.
        var clusters: [Cluster] = []
        for (gi, group) in groups.enumerated() {
            let alive = group.members.filter { scores[$0] != nil && excluded[$0] == nil }
            let ranked = alive.sorted { lhs, rhs in
                rank(lhs, rhs, scores: scores, photos: photos)
            }
            guard let winner = ranked.first else { continue }
            clusters.append(Cluster(id: "cluster-\(gi)", sceneID: group.sceneID, memberIDs: group.members,
                                    winnerID: winner, runnerUpIDs: Array(ranked.dropFirst().prefix(3))))
        }
        return Output(scores: scores, clusters: clusters, excluded: excluded)
    }

    /// True when `a` should rank above `b`.
    static func rank(_ a: String, _ b: String, scores: [String: PhotoScore], photos: [String: PhotoRecord]) -> Bool {
        let qa = scores[a]?.quality ?? 0, qb = scores[b]?.quality ?? 0
        if qa != qb { return qa > qb }
        let da = photos[a]?.creationDate ?? .distantPast, db = photos[b]?.creationDate ?? .distantPast
        if da != db { return da > db }
        return a < b
    }

    // MARK: Sub-scores

    static func technical(sharpnessRank s: Float, feature f: FeatureRecord) -> Float {
        let e = 1 - 0.5 * clamp((f.darkFraction - 0.02) / 0.20) - 0.5 * clamp((f.brightFraction - 0.01) / 0.08)
        let h: Float = f.horizonDegrees.map { 1 - clamp(abs($0) / 10) } ?? 1
        return 0.5 * s + 0.3 * e + 0.2 * h
    }

    static func composition(cropFit: Float, saliency: NormRect?) -> Float {
        guard let box = saliency else { return 0.5 * 1 + 0.3 * 0.5 + 0.2 * 0.5 }
        let cx = box.midX, cy = box.midY
        let lines: [Float] = [1.0 / 3.0, 0.5, 2.0 / 3.0]
        let nearLine = lines.contains { abs(cx - $0) <= 0.1 } || lines.contains { abs(cy - $0) <= 0.1 }
        let placement: Float = nearLine ? 1 : 0.5
        let area = box.area
        let size: Float
        if area < 0.05 { size = area / 0.05 }
        else if area <= 0.60 { size = 1 }
        else { size = clamp((1 - area) / 0.40) }
        return 0.5 * cropFit + 0.3 * placement + 0.2 * size
    }

    /// Share of the salient box that survives the largest centred-on-subject crop to `ratio`.
    static func cropFit(ratio: AspectRatio, imageAspect: Double, saliency: NormRect?) -> Float {
        guard let box = saliency, box.area > 0, imageAspect > 0 else { return 1 }
        var w: Float = 1, h: Float = 1
        if ratio.value < imageAspect { w = Float(ratio.value / imageAspect) } else { h = Float(imageAspect / ratio.value) }
        let x = min(max(box.midX - w / 2, 0), 1 - w)
        let y = min(max(box.midY - h / 2, 0), 1 - h)
        let crop = NormRect(x: x, y: y, width: w, height: h)
        return clamp(crop.intersectionArea(box) / box.area)
    }

    /// Face quality. When we know which face is the user, theirs counts most: a friend blinking matters less
    /// than the user blinking.
    static func peopleScore(_ faces: [FaceFeature], meIndex: Int? = nil) -> Float {
        let q = faces.map { $0.captureQuality ?? 0.5 }
        let mean = q.reduce(0, +) / Float(q.count), worst = q.min() ?? 0.5
        var p: Float
        if let i = meIndex, faces.indices.contains(i) {
            p = 0.5 * q[i] + 0.25 * mean + 0.25 * worst
            if faces[i].eyesClosed { p *= 0.3 } else if faces.contains(where: \.eyesClosed) { p *= 0.6 }
            if faces[i].smiling { p += 0.1 }
        } else {
            p = 0.5 * mean + 0.5 * worst
            if faces.contains(where: \.eyesClosed) { p *= 0.3 }
            if let largest = faces.max(by: { $0.box.area < $1.box.area }), largest.smiling { p += 0.1 }
        }
        return clamp(p)
    }

    static func allEyesClosed(_ f: FeatureRecord) -> Bool {
        !f.faces.isEmpty && f.faces.allSatisfy(\.eyesClosed)
    }

    // MARK: Helpers

    /// Percentile rank of each value among all values, 0–1, ties averaged. A single value maps to 0.5.
    static func percentiles(_ values: [Float]) -> [Float] {
        guard values.count > 1 else { return values.map { _ in 0.5 } }
        let order = values.indices.sorted { values[$0] < values[$1] }
        var ranks = [Float](repeating: 0, count: values.count)
        var i = 0
        while i < order.count {
            var j = i
            while j + 1 < order.count && values[order[j + 1]] == values[order[i]] { j += 1 }
            let avg = Float(i + j) / 2
            for k in i...j { ranks[order[k]] = avg / Float(values.count - 1) }
            i = j + 1
        }
        return ranks
    }

    static func clamp(_ x: Float) -> Float { min(1, max(0, x)) }
}
