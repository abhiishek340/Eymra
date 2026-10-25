import Foundation

/// Stage 8: suggested posting order.
nonisolated enum Ordering {
    struct Item: Sendable, Hashable {
        var photoID: String
        var relevance: Float
        var category: Category
        var date: Date
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
            guard items.count > 2 else { return byScore.map(\.photoID) }
            // Cover: the strongest people shot (or the strongest shot), closer: the strongest of the rest.
            let cover = byScore.first { $0.category.isPeople } ?? byScore[0]
            let closer = byScore.first { $0.photoID != cover.photoID }
            let middle = chronological.filter { $0.photoID != cover.photoID && $0.photoID != closer?.photoID }
            return [cover.photoID] + middle.map(\.photoID) + (closer.map { [$0.photoID] } ?? [])
        }
    }
}
