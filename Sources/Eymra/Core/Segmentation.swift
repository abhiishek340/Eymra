import Foundation

/// Stage 3: split a time-ordered list of photos into scenes using time gaps (PhotoTOC) and location jumps.
nonisolated enum Segmentation {
    /// Returns the indices `n` after which a scene boundary is cut (between photo n and n+1).
    static func boundaries(dates: [Date], locations: [GeoPoint?]) -> Set<Int> {
        let count = dates.count
        guard count > 1 else { return [] }
        let gaps = (0..<(count - 1)).map { max(1, dates[$0 + 1].timeIntervalSince(dates[$0])) }
        let logs = gaps.map { log($0) }
        let d = Tuning.sceneWindow
        var cuts = Set<Int>()
        for n in gaps.indices {
            // Rule A – adaptive time gap, with floors.
            let gap = gaps[n]
            if gap > Tuning.sceneMaxGap {
                cuts.insert(n)
            } else if gap >= Tuning.sceneMinGap {
                let lo = max(0, n - d), hi = min(gaps.count - 1, n + d)
                let mean = logs[lo...hi].reduce(0, +) / Double(hi - lo + 1)
                if logs[n] >= log(Tuning.sceneGapFactor) + mean { cuts.insert(n) }
            }
            // Rule B – location jump, evaluated on its own.
            if let a = locations[n], let b = locations[n + 1],
               a.horizontalAccuracy < Tuning.sceneMaxAccuracyMeters,
               b.horizontalAccuracy < Tuning.sceneMaxAccuracyMeters,
               haversine(a, b) > Tuning.sceneDistanceMeters {
                cuts.insert(n)
            }
        }
        return cuts
    }

    static func segment(photos: [PhotoRecord], features: [String: FeatureRecord]) -> [Scene] {
        let sorted = photos.sorted { ($0.creationDate, $0.id) < ($1.creationDate, $1.id) }
        guard !sorted.isEmpty else { return [] }
        let cuts = boundaries(dates: sorted.map(\.creationDate), locations: sorted.map(\.location))
        var scenes: [Scene] = []
        var current: [PhotoRecord] = []
        for (n, photo) in sorted.enumerated() {
            current.append(photo)
            if cuts.contains(n) || n == sorted.count - 1 {
                scenes.append(makeScene(index: scenes.count, members: current, features: features))
                current = []
            }
        }
        return scenes
    }

    static func makeScene(index: Int, members: [PhotoRecord], features: [String: FeatureRecord]) -> Scene {
        let located = members.compactMap(\.location)
        var centroid: GeoPoint?
        if !located.isEmpty {
            centroid = GeoPoint(latitude: median(located.map(\.latitude)),
                                longitude: median(located.map(\.longitude)),
                                horizontalAccuracy: median(located.map(\.horizontalAccuracy)))
        }
        let prints = members.compactMap { features[$0.id]?.featurePrint }.filter { !$0.isEmpty }
        return Scene(id: "scene-\(index)", photoIDs: members.map(\.id),
                     start: members.first?.creationDate ?? .distantPast,
                     end: members.last?.creationDate ?? .distantPast,
                     centroid: centroid, placeName: nil, meanPrint: VectorMath.mean(prints))
    }

    static func haversine(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let r = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

nonisolated enum VectorMath {
    /// Euclidean distance between two feature prints; nil when either is missing or the sizes differ.
    static func distance(_ a: [Float], _ b: [Float]) -> Float? {
        guard !a.isEmpty, a.count == b.count else { return nil }
        var sum: Float = 0
        for i in a.indices {
            let d = a[i] - b[i]
            sum += d * d
        }
        return sum.squareRoot()
    }

    /// RMS difference between two 32×32 luma thumbnails, scaled to 0–1.
    static func thumbRMS(_ a: [UInt8], _ b: [UInt8]) -> Float? {
        guard !a.isEmpty, a.count == b.count else { return nil }
        var sum: Float = 0
        for i in a.indices {
            let d = (Float(a[i]) - Float(b[i])) / 255
            sum += d * d
        }
        return (sum / Float(a.count)).squareRoot()
    }

    static func mean(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        let same = vectors.filter { $0.count == first.count }
        var out = [Float](repeating: 0, count: first.count)
        for v in same { for i in v.indices { out[i] += v[i] } }
        return out.map { $0 / Float(same.count) }
    }

    /// Similarity in 0–1 derived from a 0–2 distance.
    static func similarity(fromDistance d: Float) -> Float {
        min(1, max(0, 1 - d / 2))
    }
}
