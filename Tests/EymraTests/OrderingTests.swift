import Foundation
import Testing
@testable import Eymra

struct OrderingTests {
    private let items = [
        Ordering.Item(photoID: "view", relevance: 0.95, category: .view, date: Make.t0),
        Ordering.Item(photoID: "me", relevance: 0.8, category: .me, date: Make.t0.addingTimeInterval(100)),
        Ordering.Item(photoID: "food", relevance: 0.7, category: .food, date: Make.t0.addingTimeInterval(200)),
        Ordering.Item(photoID: "group", relevance: 0.6, category: .group, date: Make.t0.addingTimeInterval(300)),
    ]

    @Test func chronological() {
        #expect(Ordering.order(items.reversed(), rule: .chronological) == ["view", "me", "food", "group"])
    }

    @Test func bestFirst() {
        #expect(Ordering.order(items, rule: .bestFirst) == ["view", "me", "food", "group"])
    }

    @Test func coverIsTheBestPeopleShotAndCloserTheBestOfTheRest() {
        #expect(Ordering.order(items, rule: .coverThenStory) == ["me", "food", "group", "view"])
    }
}
