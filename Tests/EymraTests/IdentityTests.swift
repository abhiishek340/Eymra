import Testing
@testable import Eymra

struct IdentityTests {
    private let me = MeReference(prints: [Make.vector(0, offset: 0.1), Make.vector(0, offset: -0.1), Make.vector(0, offset: 0.2)])

    @Test func similarityIsCosineOfUnitVectors() {
        #expect(Identity.similarity(Make.vector(0), Make.vector(0)).map { abs($0 - 1) < 1e-5 } == true)
        #expect(Identity.similarity(Make.vector(0), Make.vector(4)) == 0)
        #expect(Identity.similarity([], Make.vector(0)) == nil)
        #expect(Identity.similarity(Make.vector(0, dim: 8), Make.vector(0, dim: 16)) == nil)
    }

    @Test func findsTheUserAmongFriends() {
        let faces = [Make.feature("g", faces: 3, facePrints: [Make.vector(4), Make.vector(0, offset: 0.05), Make.vector(8)])].first!.faces
        #expect(Identity.meFace(in: faces, reference: me) == 1)
        #expect(Identity.canTell(faces, reference: me))
    }

    @Test func friendsOnlyIsNotMe() {
        let faces = Make.feature("f", faces: 2, facePrints: [Make.vector(4), Make.vector(8)]).faces
        #expect(Identity.meFace(in: faces, reference: me) == nil)
        #expect(Identity.canTell(faces, reference: me))
    }

    @Test func noPrintsMeansWeCantTell() {
        let faces = Make.feature("x", faces: 2).faces
        #expect(!Identity.canTell(faces, reference: me))
    }

    @Test func oneReadableFriendDoesNotIdentifyTheWholeGroup() {
        let p = Make.photo("partial", at: 0)
        let f = Make.feature(p.id, faces: 2, facePrints: [Make.vector(6), []])
        let scene = Segmentation.makeScene(index: 0, members: [p], features: [p.id: f])
        let out = Scoring.score(photos: [p.id: p], features: [p.id: f], scenes: [scene],
                                groups: [(scene.id, [p.id])], primaryRatio: .portrait4x5, me: me)
        #expect(out.scores[p.id]?.withMe == nil)
        #expect(out.scores[p.id]?.category == .someone)
    }

    @Test func addingAnotherPhotoCannotPromoteAnUncertainIdentity() {
        let profile = MeReference(prints: [Make.vector(0)])
        let target = Make.vector(0, offset: 2) // uncertain versus enrolled profile
        let bridge = Make.vector(0, offset: 1.2) // admitted by the old run expansion
        let photos = [Make.photo("target", at: 0), Make.photo("bridge", at: 1)]
        let features = ["target": Make.feature("target", faces: 1, facePrints: [target]),
                        "bridge": Make.feature("bridge", faces: 1, facePrints: [bridge])]
        let scene = Segmentation.makeScene(index: 0, members: photos, features: features)
        let out = Scoring.score(photos: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) }), features: features,
                                scenes: [scene], groups: [(scene.id, ["target"]), (scene.id, ["bridge"])],
                                primaryRatio: .portrait4x5, me: profile)
        #expect(out.scores["target"]?.withMe == nil)
        #expect(out.scores["target"]?.unsureFace != nil)
    }

    @Test func scoringMarksFriendsAndFavoursTheUsersFace() {
        let photos = [Make.photo("mine", at: 0), Make.photo("theirs", at: 1)]
        let features = ["mine": Make.feature("mine", faces: 1, facePrints: [Make.vector(0, offset: 0.05)]),
                        "theirs": Make.feature("theirs", faces: 1, facePrints: [Make.vector(6)])]
        let scene = Segmentation.makeScene(index: 0, members: photos, features: features)
        let out = Scoring.score(photos: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) }), features: features,
                                scenes: [scene], groups: [(scene.id, ["mine"]), (scene.id, ["theirs"])],
                                primaryRatio: .portrait4x5, me: me)
        #expect(out.scores["mine"]?.withMe == true)
        #expect(out.scores["mine"]?.category == .me)
        #expect(out.scores["mine"]?.matchedFace?.photoID == "mine")
        #expect(out.scores["theirs"]?.matchedFace == nil)
        #expect(out.scores["theirs"]?.withMe == false)
        #expect(out.scores["theirs"]?.category == .friends)
    }

    @Test func myBlinkMattersMoreThanAFriendsBlink() {
        let box = NormRect(x: 0, y: 0, width: 0.2, height: 0.2)
        let iBlink = [FaceFeature(box: box, captureQuality: 0.8, eyesClosed: true, smiling: false),
                      FaceFeature(box: box, captureQuality: 0.8, eyesClosed: false, smiling: false)]
        let theyBlink = [FaceFeature(box: box, captureQuality: 0.8, eyesClosed: false, smiling: false),
                         FaceFeature(box: box, captureQuality: 0.8, eyesClosed: true, smiling: false)]
        #expect(Scoring.peopleScore(iBlink, meIndex: 0) < Scoring.peopleScore(theyBlink, meIndex: 0))
    }
}

struct VerdictTests {
    private let you = MeReference(prints: [Make.vector(0)])

    @Test func sureUnsureAndNot() {
        #expect(Identity.verdict(Make.vector(0, offset: 0.3), reference: you)?.0 == .me)          // ≈ 0.96
        #expect(Identity.verdict(Make.vector(0, offset: 2.0), reference: you)?.0 == .maybe)       // ≈ 0.45
        #expect(Identity.verdict(Make.vector(6), reference: you)?.0 == .notMe)                     // 0
    }

    @Test func notMeAnswersWin() {
        let lookAlike = Make.vector(0, offset: 1.2)                                                 // ≈ 0.64, "sure"
        #expect(Identity.verdict(lookAlike, reference: you)?.0 == .me)
        var answered = you
        answered.notMe = [lookAlike]
        #expect(Identity.verdict(lookAlike, reference: answered)?.0 == .notMe)
        // Still you when the face is closer to you than to the "Not me" answer.
        #expect(Identity.verdict(Make.vector(0, offset: 0.1), reference: answered)?.0 == .me)
    }

    @Test func thisIsMeAnswersCount() {
        let turnedAway = Make.vector(0, offset: 2.0)
        var answered = you
        answered.confirmed = [turnedAway]
        #expect(Identity.verdict(turnedAway, reference: answered)?.0 == .me)
    }

    @Test func malformedSignaturesCannotEstablishIdentity() {
        #expect(Identity.similarity([0, 0], [1, 0]) == nil)
        #expect(Identity.similarity([.nan, 0], [1, 0]) == nil)
        #expect(Identity.similarity([.infinity, 0], [1, 0]) == nil)
        #expect(Identity.similarity([2, 0], [3, 0]) == 1)
    }
}
