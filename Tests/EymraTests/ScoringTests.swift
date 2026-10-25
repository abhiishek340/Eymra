import Foundation
import Testing
@testable import Eymra

struct ScoringTests {
    private func score(_ photos: [PhotoRecord], _ features: [String: FeatureRecord], groups: [[String]]) -> Scoring.Output {
        let scene = Segmentation.makeScene(index: 0, members: photos, features: features)
        return Scoring.score(photos: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) }), features: features,
                             scenes: [scene], groups: groups.map { (scene.id, $0) }, primaryRatio: .portrait4x5)
    }

    @Test func percentilesAverageTies() {
        #expect(Scoring.percentiles([3, 1, 2]) == [1, 0, 0.5])
        #expect(Scoring.percentiles([5, 5, 1]) == [0.75, 0.75, 0])
        #expect(Scoring.percentiles([7]) == [0.5])
    }

    @Test func sharperShotWinsTheCluster() {
        let photos = (0..<3).map { Make.photo("p\($0)", at: Double($0)) }
        let features = ["p0": Make.feature("p0", sharpness: 100), "p1": Make.feature("p1", sharpness: 900),
                        "p2": Make.feature("p2", sharpness: 400)]
        let out = score(photos, features, groups: [["p0", "p1", "p2"]])
        #expect(out.clusters.first?.winnerID == "p1")
        #expect(out.clusters.first?.runnerUpIDs == ["p2", "p0"])
    }

    @Test func blurryRejectedOnlyWhenItHasSiblings() {
        let photos = (0..<3).map { Make.photo("p\($0)", at: Double($0)) }
        let features = ["p0": Make.feature("p0", sharpness: 5), "p1": Make.feature("p1", sharpness: 900),
                        "p2": Make.feature("p2", sharpness: 10)]
        let out = score(photos, features, groups: [["p0", "p1"], ["p2"]])
        #expect(out.excluded["p0"] == .blurry)
        #expect(out.excluded["p2"] == nil)        // alone in its cluster: kept
    }

    @Test func darkAndBlownOutRejects() {
        let photos = (0..<3).map { Make.photo("p\($0)", at: Double($0)) }
        let features = ["p0": Make.feature("p0", dark: 0.7), "p1": Make.feature("p1"), "p2": Make.feature("p2", bright: 0.5)]
        let out = score(photos, features, groups: [["p0", "p1", "p2"]])
        #expect(out.excluded["p0"] == .tooDark)
        #expect(out.excluded["p2"] == .blownOut)
    }

    @Test func eyesClosedRejectedWhenASiblingHasThemOpen() {
        let photos = (0..<2).map { Make.photo("p\($0)", at: Double($0)) }
        let features = ["p0": Make.feature("p0", faces: 1, eyesClosed: true), "p1": Make.feature("p1", faces: 1)]
        let out = score(photos, features, groups: [["p0", "p1"]])
        #expect(out.excluded["p0"] == .eyesClosed)
        #expect(out.clusters.first?.winnerID == "p1")
    }

    @Test func utilityAndSmallAreRejected() {
        let photos = [Make.photo("doc", at: 0), Make.photo("tiny", at: 1, width: 640, height: 480)]
        let features = ["doc": Make.feature("doc", utility: true), "tiny": Make.feature("tiny")]
        let out = score(photos, features, groups: [["doc"], ["tiny"]])
        #expect(out.excluded["doc"] == .screenshot)
        #expect(out.excluded["tiny"] == .tooSmall)
        #expect(out.clusters.isEmpty)
    }

    @Test func favoriteGetsABoost() {
        let photos = [Make.photo("a", at: 0), Make.photo("b", at: 1, favorite: true)]
        let features = ["a": Make.feature("a"), "b": Make.feature("b")]
        let out = score(photos, features, groups: [["a"], ["b"]])
        let qa = out.scores["a"]?.quality ?? 0, qb = out.scores["b"]?.quality ?? 0
        #expect(abs(qb - qa - Tuning.favoriteBonus) < 0.001)
    }

    @Test func tieBreaksOnLaterCaptureThenIdentifier() {
        let photos = [Make.photo("a", at: 0), Make.photo("b", at: 5)]
        let features = ["a": Make.feature("a"), "b": Make.feature("b")]
        let out = score(photos, features, groups: [["a", "b"]])
        #expect(out.clusters.first?.winnerID == "b")
    }

    @Test func peopleScorePenalisesClosedEyesAndRewardsSmiles() {
        let box = NormRect(x: 0, y: 0, width: 0.3, height: 0.3)
        let open = [FaceFeature(box: box, captureQuality: 0.8, eyesClosed: false, smiling: false)]
        let closed = [FaceFeature(box: box, captureQuality: 0.8, eyesClosed: true, smiling: false)]
        let smile = [FaceFeature(box: box, captureQuality: 0.8, eyesClosed: false, smiling: true)]
        #expect(abs(Scoring.peopleScore(open) - 0.8) < 0.001)
        #expect(abs(Scoring.peopleScore(closed) - 0.24) < 0.001)
        #expect(abs(Scoring.peopleScore(smile) - 0.9) < 0.001)
    }

    @Test func cropFitMeasuresHowMuchSubjectSurvives() {
        // A subject on the far left of a wide image loses part of itself in a 9:16 crop centred on it… but not all.
        let leftEdge = NormRect(x: 0, y: 0.3, width: 0.4, height: 0.4)
        let fit = Scoring.cropFit(ratio: .vertical9x16, imageAspect: 16.0 / 9.0, saliency: leftEdge)
        #expect(fit > 0.7 && fit < 1)
        #expect(Scoring.cropFit(ratio: .square, imageAspect: 1, saliency: leftEdge) == 1)
        #expect(Scoring.cropFit(ratio: .square, imageAspect: 1.5, saliency: nil) == 1)
    }

    @Test func compositionWithoutSaliencyIsNeutral() {
        #expect(abs(Scoring.composition(cropFit: 1, saliency: nil) - 0.75) < 0.001)
    }
}
