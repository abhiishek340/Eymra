import Foundation

/// Stage 8: suggested posting order.
nonisolated enum Ordering {
    struct Item: Sendable, Hashable {
        var photoID: String
        var relevance: Float
        var category: Category
        var date: Date
        var sceneID: String = ""
        var withMe: Bool? = nil
    }

    struct Story: Sendable, Hashable {
        var order: [String]
        var opener: String?
        var closer: String?
    }

    static func order(_ items: [Item], rule: OrderingRule) -> [String] {
        let chronological = items.sorted { ($0.date, $0.photoID) < ($1.date, $1.photoID) }
        let byScore = items.sorted { $0.relevance != $1.relevance ? $0.relevance > $1.relevance : $0.photoID < $1.photoID }
        switch rule {
        case .chronological:
            return chronological.map(\.photoID)
        case .bestFirst:
            return byScore.map(\.photoID)
        case .coverThenStory:
            return story(items).order
        }
    }

    /// A story: a strong opener that shows the user, the journey in time order with some rhythm,
    /// and a strong closer from late in the day (Obrador et al. 2010; "acts and scenes").
    static func story(_ items: [Item], lastSceneID: String? = nil) -> Story {
        let byScore = items.sorted { $0.relevance != $1.relevance ? $0.relevance > $1.relevance : $0.photoID < $1.photoID }
        guard items.count > 2 else { return Story(order: byScore.map(\.photoID), opener: byScore.first?.photoID, closer: nil) }

        // Opener: among the strongest third, prefer a photo of the user, then any people shot.
        let top = Array(byScore.prefix(max(2, items.count / 3)))
        let opener = top.first { $0.withMe == true && $0.category != .group }
            ?? top.first { $0.category.isMe }
            ?? top.first { $0.category.isPeople && $0.category != .friends }
            ?? byScore[0]

        // Closer: a strong wide moment (view, you with the view, or the group), helped by being late in the day.
        let last = lastSceneID ?? items.max { $0.date < $1.date }?.sceneID
        let first = items.map(\.date).min() ?? Date(), span = max(1, (items.map(\.date).max() ?? first).timeIntervalSince(first))
        let closer = byScore.filter { $0.photoID != opener.photoID }.max { a, b in
            closerValue(a, lastSceneID: last, lateness: Float(a.date.timeIntervalSince(first) / span))
                < closerValue(b, lastSceneID: last, lateness: Float(b.date.timeIntervalSince(first) / span))
        }
        var middle = items
            .filter { $0.photoID != opener.photoID && $0.photoID != closer?.photoID }
            .sorted { ($0.date, $0.photoID) < ($1.date, $1.photoID) }
        middle = rhythm(middle)
        return Story(order: [opener.photoID] + middle.map(\.photoID) + (closer.map { [$0.photoID] } ?? []),
                     opener: opener.photoID, closer: closer?.photoID)
    }

    static func closerValue(_ item: Item, lastSceneID: String?, lateness: Float = 0) -> Float {
        var v = item.relevance + Tuning.closerLateBonus * lateness
        if item.sceneID == lastSceneID && !item.sceneID.isEmpty { v += Tuning.closerLastSceneBonus }
        if item.category == .view || item.category == .meWithView || item.category == .group { v += 0.05 }
        return v
    }

    /// Avoids two shots of the same kind back to back by swapping with the next different shot from the same place,
    /// so time order across places is kept.
    static func rhythm(_ items: [Item]) -> [Item] {
        var out = items
        guard out.count > 2 else { return out }
        for i in 1..<out.count where out[i].category == out[i - 1].category {
            if let j = ((i + 1)..<out.count).first(where: { out[$0].category != out[i].category && out[$0].sceneID == out[i].sceneID }) {
                out.swapAt(i, j)
            }
        }
        return out
    }
}
