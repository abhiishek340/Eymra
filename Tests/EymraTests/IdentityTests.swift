import Testing
@testable import Eymra

struct IdentityTests {
    private let me = MeReference(prints: [Make.vector(0, offset: 0.1), Make.vector(0, offset: -0.1), Make.vector(0, offset: 0.2)])

    @Test func thresholdAdaptsToTheUsersOwnSpread() {
        let t = Identity.threshold(for: me)
        #expect(t >= Tuning.meDistanceMin && t <= Tuning.meDistanceMax)
        #expect(Identity.threshold(for: MeReference(prints: [Make.vector(0)])) == Tuning.meDistanceDefault)
        // References far apart push the threshold to its ceiling.
        #expect(Identity.threshold(for: MeReference(prints: [Make.vector(0), Make.vector(5)])) == Tuning.meDistanceMax)
    }

    @Test func findsTheUserAmongFriends() {
        let faces = [Make.feature("g", faces: 3, facePrints: [Make.vector(4), Make.vector(0, offset: 0.05), Make.vector(8)])].first!.faces
        #expect(Identity.meFace(in: faces, reference: me, threshold: Identity.threshold(for: me)) == 1)
        #expect(Identity.canTell(faces, reference: me))
    }

    @Test func friendsOnlyIsNotMe() {
        let faces = Make.feature("f", faces: 2, facePrints: [Make.vector(4), Make.vector(8)]).faces
        #expect(Identity.meFace(in: faces, reference: me, threshold: Identity.threshold(for: me)) == nil)
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
