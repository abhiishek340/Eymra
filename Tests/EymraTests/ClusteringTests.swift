import Foundation
import Testing
@testable import Eymra

struct ClusteringTests {
    private func run(_ photos: [PhotoRecord], _ features: [String: FeatureRecord]) -> [[String]] {
        let scene = Segmentation.makeScene(index: 0, members: photos, features: features)
        return Clustering.clusters(in: scene, photos: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) }), features: features)
    }

    @Test func nearIdenticalShotsCluster() {
        let photos = (0..<5).map { Make.photo("p\($0)", at: Double($0) * 3) }
        var features: [String: FeatureRecord] = [:]
        for i in 0..<5 { features["p\(i)"] = Make.feature("p\(i)", print: Make.vector(0, offset: Float(i) * 0.02), faces: 1) }
        #expect(run(photos, features) == [["p0", "p1", "p2", "p3", "p4"]])
    }

    @Test func differentShotsStayApart() {
        let photos = (0..<3).map { Make.photo("p\($0)", at: Double($0) * 3) }
        let features = Dictionary(uniqueKeysWithValues: (0..<3).map { ("p\($0)", Make.feature("p\($0)", print: Make.vector($0 * 3))) })
        #expect(run(photos, features).count == 3)
    }

    @Test func faceCountChangeSplitsTheMoment() {
        let photos = [Make.photo("solo", at: 0), Make.photo("pair", at: 5)]
        let features = ["solo": Make.feature("solo", print: Make.vector(0), faces: 1),
                        "pair": Make.feature("pair", print: Make.vector(0, offset: 0.01), faces: 2)]
        #expect(run(photos, features).count == 2)
    }

    @Test func groupsToleratePlusMinusOneFace() {
        #expect(Clustering.facesAgree(3, 4))
        #expect(Clustering.facesAgree(5, 5))
        #expect(!Clustering.facesAgree(2, 3))
        #expect(!Clustering.facesAgree(3, 5))
    }

    @Test func slowPanDoesNotChainForever() {
        // Each step is 0.3 from the previous, so neighbours join, but the anchor check stops the chain.
        let n = 8
        let photos = (0..<n).map { Make.photo("p\($0)", at: Double($0) * 2) }
        var features: [String: FeatureRecord] = [:]
        for i in 0..<n {
            let angle = Float(i) * 0.3
            features["p\(i)"] = Make.feature("p\(i)", print: [cos(angle), sin(angle)])
        }
        let clusters = run(photos, features)
        #expect(clusters.count > 1)
        #expect(clusters.allSatisfy { $0.count < n })
    }

    @Test func lookbackStopsAfterTenMinutes() {
        let photos = [Make.photo("a", at: 0), Make.photo("b", at: 11 * 60)]
        let features = ["a": Make.feature("a", print: Make.vector(0)), "b": Make.feature("b", print: Make.vector(0))]
        #expect(run(photos, features).count == 2)
    }

    @Test func thumbnailFallbackWhenNoFeaturePrint() {
        let thumb = [UInt8](repeating: 100, count: 1024)
        let close = thumb.map { $0 &+ 5 }
        let photos = [Make.photo("a", at: 0), Make.photo("b", at: 20), Make.photo("c", at: 120)]
        let features = ["a": Make.feature("a", thumb: thumb), "b": Make.feature("b", thumb: close), "c": Make.feature("c", thumb: close)]
        // b joins a (RMS ≈ 0.02, 20 s apart); c is too late for the thumbnail rule.
        #expect(run(photos, features) == [["a", "b"], ["c"]])
    }

    @Test func unionFindTracksFirstMember() {
        var uf = UnionFind(count: 4)
        uf.union(3, 2)
        uf.union(2, 1)
        #expect(uf.firstMember(of: 3) == 1)
        #expect(uf.find(3) == uf.find(1))
        #expect(uf.find(0) != uf.find(1))
    }
}

struct SamePeopleTests {
    private let you = Make.vector(0, offset: 0.05)
    private let youAgain = Make.vector(0, offset: 0.12)
    private let friend = Make.vector(6)

    private func run(_ a: [Float], _ b: [Float]) -> [[String]] {
        // Same spot (same feature print), one face each, 5 seconds apart.
        let photos = [Make.photo("a", at: 0), Make.photo("b", at: 5)]
        let features = ["a": Make.feature("a", print: Make.vector(3), faces: 1, facePrints: [a]),
                        "b": Make.feature("b", print: Make.vector(3, offset: 0.02), faces: 1, facePrints: [b])]
        let scene = Segmentation.makeScene(index: 0, members: photos, features: features)
        return Clustering.clusters(in: scene, photos: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) }), features: features)
    }

    @Test func youAndYourFriendAtTheSameSpotAreDifferentMoments() {
        #expect(run(you, friend).count == 2)
    }

    @Test func twoPosesOfYouAreOneMoment() {
        #expect(run(you, youAgain) == [["a", "b"]])
    }

    @Test func facesWithoutSignaturesDoNotSplit() {
        #expect(run([], []) == [["a", "b"]])
        #expect(run(you, []) == [["a", "b"]])
    }

    @Test func pairsMustBeTheSamePair() {
        let pairA = [FaceFeature(box: NormRect(x: 0, y: 0, width: 0.1, height: 0.1), captureQuality: 0.6, eyesClosed: false, smiling: false, print: you),
                     FaceFeature(box: NormRect(x: 0.5, y: 0, width: 0.1, height: 0.1), captureQuality: 0.6, eyesClosed: false, smiling: false, print: friend)]
        var pairB = pairA
        pairB[1].print = Make.vector(9)
        #expect(Clustering.samePeople(pairA, pairA))
        #expect(!Clustering.samePeople(pairA, pairB))
    }
}
