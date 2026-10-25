import Testing
@testable import Eymra

struct SelectionTests {
    @Test func picksTheBestWhenEverythingIsDistinct() {
        let c = (0..<6).map { Make.candidate("p\($0)", scene: "s\($0)", r: Float($0) / 10, print: Make.vector($0 * 2)) }
        let result = Selection.select(candidates: c, count: 3, mix: .balanced)
        #expect(Set(result.selected) == ["p5", "p4", "p3"])
        #expect(result.shortfall == 0)
    }

    @Test func sameBackgroundIsBlocked() {
        let c = [Make.candidate("a", scene: "s1", r: 0.9, print: Make.vector(0)),
                 Make.candidate("b", scene: "s1", r: 0.85, print: Make.vector(0, offset: 0.3)),   // same backdrop, other cluster
                 Make.candidate("c", scene: "s2", r: 0.5, print: Make.vector(6))]
        let result = Selection.select(candidates: c, count: 2, mix: .balanced)
        #expect(result.selected == ["a", "c"])
        let tags = Selection.exclusionTags(candidates: c, ordered: result.selected, count: 2)
        #expect(tags["b"] == .sameBackground(asPick: 1))
    }

    @Test func sceneCapSpreadsPicksAcrossPlaces() {
        var c = (0..<6).map { Make.candidate("a\($0)", scene: "beach", r: 0.9 - Float($0) * 0.01, print: Make.vector($0 * 2)) }
        c += (0..<3).map { Make.candidate("b\($0)", scene: "town", r: 0.5, print: Make.vector(13 + $0, dim: 16)) }
        let result = Selection.select(candidates: c, count: 6, mix: .balanced)
        let beach = result.selected.filter { $0.hasPrefix("a") }.count
        #expect(beach <= Selection.sceneCap(count: 6))
        #expect(result.selected.count == 6)
    }

    @Test func varietyBeatsTenSelfies() {
        var c = (0..<8).map { Make.candidate("me\($0)", scene: "s\($0)", r: 0.8, category: .me, print: Make.vector($0 * 2)) }
        c.append(Make.candidate("view", scene: "v", r: 0.6, category: .view, print: Make.vector(1)))
        c.append(Make.candidate("food", scene: "f", r: 0.55, category: .food, print: Make.vector(3)))
        let result = Selection.select(candidates: c, count: 5, mix: .balanced)
        #expect(result.selected.contains("view"))
        #expect(result.selected.contains("food"))
        // Two selfies fill the quota; once view and food are in, the quota relaxes for the last slot.
        #expect(result.selected.filter { $0.hasPrefix("me") }.count == 3)
        #expect(result.relaxed == [.categoryQuota])
    }

    @Test func mixShiftsTheBalance() {
        let c = [Make.candidate("me", scene: "a", r: 0.6, category: .me, print: Make.vector(0)),
                 Make.candidate("view", scene: "b", r: 0.62, category: .view, print: Make.vector(4))]
        #expect(Selection.select(candidates: c, count: 1, mix: .moreOfMe).selected == ["me"])
        #expect(Selection.select(candidates: c, count: 1, mix: .moreScenery).selected == ["view"])
    }

    @Test func relaxesWhenTheCountCannotBeMetAndReportsIt() {
        let c = (0..<4).map { Make.candidate("p\($0)", scene: "one", r: 0.9, category: .view, print: Make.vector($0 * 3)) }
        let result = Selection.select(candidates: c, count: 4, mix: .balanced)
        #expect(result.selected.count == 4)
        #expect(!result.relaxed.isEmpty)
    }

    @Test func shortfallWhenTooFewCandidates() {
        let c = [Make.candidate("only", r: 0.9, print: Make.vector(0))]
        #expect(Selection.select(candidates: c, count: 5, mix: .balanced).shortfall == 4)
    }

    @Test func lockedPicksStay() {
        let c = (0..<5).map { Make.candidate("p\($0)", scene: "s\($0)", r: Float($0) / 10, print: Make.vector($0 * 2)) }
        let result = Selection.select(candidates: c, count: 2, mix: .balanced, locked: ["p0"])
        #expect(result.selected.contains("p0"))
        #expect(result.selected.contains("p4"))
    }

    @Test func belowCutTagsCarryRank() {
        let c = (0..<3).map { Make.candidate("p\($0)", scene: "s\($0)", r: 1 - Float($0) / 10, category: Eymra.Category.allCases[$0], print: Make.vector($0 * 4)) }
        let tags = Selection.exclusionTags(candidates: c, ordered: ["p0"], count: 1)
        #expect(tags["p1"] == .belowCut(rank: 2) || tags["p1"] == .sceneCap(pick: 1) || tags["p1"] == .categoryQuota)
        #expect(tags["p0"] == nil)
    }
}
