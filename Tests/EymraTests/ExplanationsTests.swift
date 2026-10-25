import Testing
@testable import Eymra

struct ExplanationsTests {
    private func score(t: Float, a: Float, p: Float? = nil, category: Eymra.Category = .view) -> PhotoScore {
        PhotoScore(photoID: "x", technical: t, aesthetic: a, composition: 0.5, people: p, quality: 0.7, cropFit: [:],
                   category: category, exclusion: nil)
    }

    @Test func clusterReasonNamesTheSize() {
        let r = Explanations.reason(.init(score: score(t: 0.9, a: 0.5), clusterSize: 12, sceneLabel: "10:12–10:40",
                                          categoryCountInSet: 1, judge: nil))
        #expect(r.contains("12"))
        #expect(r.lowercased().contains("sharpest"))
    }

    @Test func onlyViewIsCalledOut() {
        let r = Explanations.reason(.init(score: score(t: 0.5, a: 0.5), clusterSize: 1, sceneLabel: "the ridge",
                                          categoryCountInSet: 1, judge: nil))
        #expect(r.contains("Only wide view"))
    }

    @Test func judgeReasonWins() {
        let v = JudgeVerdict(photoID: "x", score: 0.9, category: .view, reason: "Gorgeous light on the lake", model: "m", promptVersion: 1)
        let r = Explanations.reason(.init(score: score(t: 0.5, a: 0.5), clusterSize: 4, sceneLabel: "", categoryCountInSet: 1, judge: v))
        #expect(r == "Gorgeous light on the lake")
    }

    @Test func everyTagHasText() {
        let tags: [ExclusionTag] = [.screenshot, .animated, .tooSmall, .blurry, .tooDark, .blownOut, .eyesClosed, .inCloud,
                                    .analysisFailed, .nearDuplicate(ofPick: 2), .nearDuplicate(ofPick: nil),
                                    .sameBackground(asPick: 1), .sceneCap(pick: 3), .belowCut(rank: 7), .hidden, .categoryQuota]
        for tag in tags { #expect(!Explanations.whyNot(tag).isEmpty) }
        #expect(Explanations.whyNot(.nearDuplicate(ofPick: 2)).contains("2"))
    }
}
