import Foundation

/// Stage 4: group near-duplicate shots of one moment inside a scene.
nonisolated enum Clustering {
    /// Returns member groups (time order) for one scene. Winners are chosen later by scoring.
    static func clusters(in scene: Scene, photos: [String: PhotoRecord], features: [String: FeatureRecord]) -> [[String]] {
        let ids = scene.photoIDs.sorted {
            let a = photos[$0]?.creationDate ?? .distantPast, b = photos[$1]?.creationDate ?? .distantPast
            return (a, $0) < (b, $1)
        }
        var uf = UnionFind(count: ids.count)
        for i in ids.indices {
            guard let pi = photos[ids[i]] else { continue }
            let lowest = max(0, i - Tuning.clusterLookback)
            for j in stride(from: i - 1, through: lowest, by: -1) {
                guard let pj = photos[ids[j]] else { continue }
                let gap = pi.creationDate.timeIntervalSince(pj.creationDate)
                if gap > Tuning.clusterLookbackSeconds { break }
                guard isDuplicate(ids[i], ids[j], gap: gap, features: features) else { continue }
                // Anchor check: stop slow pans chaining into one giant cluster.
                let anchor = ids[uf.firstMember(of: j)]
                if anchor != ids[j], let d = printDistance(ids[i], anchor, features), d >= Tuning.clusterAnchorDistance {
                    continue
                }
                uf.union(i, j)
            }
        }
        var groups: [Int: [String]] = [:]
        var order: [Int] = []
        for i in ids.indices {
            let root = uf.find(i)
            if groups[root] == nil { order.append(root) }
            groups[root, default: []].append(ids[i])
        }
        return order.compactMap { groups[$0] }
    }

    static func isDuplicate(_ a: String, _ b: String, gap: TimeInterval, features: [String: FeatureRecord]) -> Bool {
        guard let fa = features[a], let fb = features[b] else { return false }
        guard facesAgree(fa.faces.count, fb.faces.count) else { return false }
        if let d = VectorMath.distance(fa.featurePrint, fb.featurePrint) {
            return d < Tuning.duplicateDistance
        }
        if let rms = VectorMath.thumbRMS(fa.thumb32, fb.thumb32) {
            return rms < Tuning.thumbDuplicateRMS && abs(gap) < Tuning.thumbDuplicateSeconds
        }
        return false
    }

    /// Face counts agree when identical, or both at least 3 and differing by at most 1.
    static func facesAgree(_ a: Int, _ b: Int) -> Bool {
        a == b || (a >= 3 && b >= 3 && abs(a - b) <= 1)
    }

    static func printDistance(_ a: String, _ b: String, _ features: [String: FeatureRecord]) -> Float? {
        guard let fa = features[a], let fb = features[b] else { return nil }
        return VectorMath.distance(fa.featurePrint, fb.featurePrint)
    }
}

/// Union-find that remembers the earliest member (lowest index) of every set.
nonisolated struct UnionFind {
    private var parent: [Int]
    private var first: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        first = Array(0..<count)
    }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var node = x
        while parent[node] != root {
            let next = parent[node]
            parent[node] = root
            node = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let ra = find(a), rb = find(b)
        guard ra != rb else { return }
        let (keep, drop) = ra < rb ? (ra, rb) : (rb, ra)
        parent[drop] = keep
        first[keep] = min(first[keep], first[drop])
    }

    mutating func firstMember(of x: Int) -> Int {
        first[find(x)]
    }
}
