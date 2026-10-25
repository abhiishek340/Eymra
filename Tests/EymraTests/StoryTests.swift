import Foundation
import Testing
@testable import Eymra

struct StoryTests {
    private func item(_ id: String, _ r: Float, _ c: Eymra.Category, _ minutes: Double, scene: String, me: Bool? = nil) -> Ordering.Item {
        Ordering.Item(photoID: id, relevance: r, category: c, date: Make.t0.addingTimeInterval(minutes * 60), sceneID: scene, withMe: me)
    }

    @Test func opensWithTheUserAndClosesLate() {
        let items = [
            item("viewEarly", 0.95, .view, 0, scene: "a"),
            item("meMid", 0.85, .me, 60, scene: "b", me: true),
            item("food", 0.7, .food, 70, scene: "b"),
            item("friends", 0.65, .friends, 80, scene: "b", me: false),
            item("sunset", 0.8, .view, 300, scene: "z"),
        ]
        let story = Ordering.story(items, lastSceneID: "z")
        #expect(story.opener == "meMid")
        #expect(story.closer == "sunset")
        #expect(story.order.first == "meMid")
        #expect(story.order.last == "sunset")
        // The middle keeps time order.
        #expect(Array(story.order.dropFirst().dropLast()) == ["viewEarly", "food", "friends"])
    }

    @Test func rhythmAvoidsTwoOfAKindInARowWithinAPlace() {
        let items = [item("v1", 0.5, .view, 0, scene: "a"), item("v2", 0.5, .view, 1, scene: "a"), item("f", 0.5, .food, 2, scene: "a")]
        #expect(Ordering.rhythm(items).map(\.photoID) == ["v1", "f", "v2"])
        // Different places keep their order.
        let across = [item("v1", 0.5, .view, 0, scene: "a"), item("v2", 0.5, .view, 1, scene: "b"), item("f", 0.5, .food, 2, scene: "c")]
        #expect(Ordering.rhythm(across).map(\.photoID) == ["v1", "v2", "f"])
    }

    @Test func coverageBringsInAnUnseenPlace() {
        let a = Make.candidate("a", scene: "big", r: 0.8, print: Make.vector(0), sceneWeight: 1)
        let b = Make.candidate("b", scene: "big", r: 0.78, print: Make.vector(4), sceneWeight: 1)
        let c = Make.candidate("c", scene: "small", r: 0.72, print: Make.vector(8), sceneWeight: 0.6)
        #expect(Selection.select(candidates: [a, b, c], count: 2, mix: .balanced).selected == ["a", "c"])
    }

    @Test func mostlyMeLeansTowardTheUser() {
        let me = Make.candidate("me", scene: "a", r: 0.6, category: .me, print: Make.vector(0), withMe: true)
        let friends = Make.candidate("friends", scene: "b", r: 0.66, category: .friends, print: Make.vector(4), withMe: false)
        let mostlyMe = UserPrefs(style: .mostlyMe, groups: .rarely, story: .story)
        #expect(Selection.select(candidates: [me, friends], count: 1, mix: .balanced, prefs: mostlyMe).selected == ["me"])
        let social = UserPrefs(style: .meAndFriends, groups: .love, story: .story)
        #expect(Selection.select(candidates: [me, friends], count: 1, mix: .balanced, prefs: social).selected == ["me"])
        // Without identity, nothing personal applies: plain quality wins.
        let a = Make.candidate("me", scene: "a", r: 0.6, category: .me, print: Make.vector(0))
        let b = Make.candidate("other", scene: "b", r: 0.66, category: .group, print: Make.vector(4))
        #expect(Selection.select(candidates: [a, b], count: 1, mix: .balanced, prefs: mostlyMe).selected == ["other"])
    }

    @Test func groupLoversGetMoreGroups() {
        let group = Make.candidate("group", scene: "a", r: 0.6, category: .group, print: Make.vector(0), withMe: true)
        let solo = Make.candidate("solo", scene: "b", r: 0.62, category: .me, print: Make.vector(4), withMe: true)
        let love = UserPrefs(style: .meAndFriends, groups: .love, story: .story)
        let rarely = UserPrefs(style: .meAndFriends, groups: .rarely, story: .story)
        #expect(Selection.select(candidates: [group, solo], count: 1, mix: .balanced, prefs: love).selected == ["group"])
        #expect(Selection.select(candidates: [group, solo], count: 1, mix: .balanced, prefs: rarely).selected == ["solo"])
    }

    @Test func plainLanguageTitles() {
        let day = DateInterval(start: Make.t0, duration: 3600 * 8)
        #expect(Explanations.storyTitle(range: day, sceneCount: 3).hasPrefix("Your "))
        // Counted in calendar days: Friday 10:00 to Sunday 15:00 is 3 days.
        let friday = Calendar.current.startOfDay(for: Make.t0).addingTimeInterval(10 * 3600)
        let trip = DateInterval(start: friday, end: friday.addingTimeInterval(2 * 86_400 + 5 * 3600))
        #expect(Explanations.storyTitle(range: trip, sceneCount: 4) == "Your 3 days, 4 places")
    }
}
