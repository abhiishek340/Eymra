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

struct RunReferenceTests {
    @Test func confidentShotsFromTheRunJoinTheProfile() {
        let profile = MeReference(prints: [Make.vector(0)])
        let clearShotOfYou = Make.vector(0, offset: 0.3)        // similarity ≈ 0.96
        let friend = Make.vector(6)                              // similarity 0
        let blurryYou = Make.vector(0, offset: 1.6)              // similarity ≈ 0.53, just under "confident"
        let reference = Identity.runReference(profile, faces: [clearShotOfYou, friend, blurryYou])
        #expect(reference.prints.count == 2)
        #expect(reference.prints.contains(clearShotOfYou))
        #expect(!reference.prints.contains(friend))
        #expect(!reference.prints.contains(blurryYou))
    }
}
