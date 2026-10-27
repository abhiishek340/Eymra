import Testing
@testable import Eymra

struct CategoryRulesTests {
    @Test func groupBeatsEverything() {
        #expect(CategoryRules.category(for: Make.feature("g", faces: 3, labels: [("food", 0.9)]), withMe: true) == .group)
    }

    @Test func bigFaceIsMe() {
        #expect(CategoryRules.category(for: Make.feature("m", faces: 1, faceArea: 0.1), withMe: true) == .me)
    }

    @Test func smallFaceOutdoorsIsMeWithView() {
        #expect(CategoryRules.category(for: Make.feature("v", faces: 1, faceArea: 0.01, labels: [("mountain", 0.6)]), withMe: true) == .meWithView)
    }

    @Test func foodViewAndDetail() {
        #expect(CategoryRules.category(for: Make.feature("f", labels: [("dessert", 0.8)])) == .food)
        #expect(CategoryRules.category(for: Make.feature("v", labels: [("sky", 0.5)])) == .view)
        #expect(CategoryRules.category(for: Make.feature("d", saliency: NormRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))) == .detail)
        #expect(CategoryRules.category(for: Make.feature("o", saliency: nil)) == .other)
    }

    @Test func lowConfidenceLabelsAreIgnored() {
        #expect(CategoryRules.category(for: Make.feature("f", labels: [("food", 0.2)], saliency: nil)) == .other)
    }

    @Test func withoutAFaceScanIdentityStaysUnknown() {
        #expect(CategoryRules.category(for: Make.feature("m", faces: 1, faceArea: 0.1)) == .someone)
        var back = Make.feature("back", labels: [("mountain", 0.9)])
        back.humanBoxes = [NormRect(x: 0.2, y: 0.1, width: 0.5, height: 0.8)]
        #expect(CategoryRules.category(for: back) == .someone)
    }

    @Test func onceYourFaceIsKnownABigFaceIsNotEnough() {
        let close = Make.feature("m", faces: 1, faceArea: 0.1)
        #expect(CategoryRules.category(for: close, withMe: true) == .me)
        #expect(CategoryRules.category(for: close, withMe: false) == .friends)
        #expect(CategoryRules.category(for: close, withMe: nil) == .someone)
    }

    @Test func photosWithoutPeopleAreNeverSomeone() {
        #expect(CategoryRules.category(for: Make.feature("f", labels: [("dessert", 0.8)]), withMe: nil) == .food)
    }

    @Test func prefixMatchingCoversSubLabels() {
        #expect(CategoryRules.matches("food_other", in: CategoryRules.foodLabels))
        #expect(CategoryRules.matches("Water_Body", in: CategoryRules.sceneryLabels))
        #expect(!CategoryRules.matches("document", in: CategoryRules.sceneryLabels))
    }
}
