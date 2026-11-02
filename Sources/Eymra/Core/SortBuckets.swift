import Foundation

/// The piles the working screen sorts a finished run into, like photos dealt into folders on a desk.
/// Every photo in the run lands in exactly one.
nonisolated enum SortBucket: String, CaseIterable, Sendable, Hashable {
    case you, people, places, food, details, same, aside

    /// Where one photo goes. Duplicates and rejects first, then by kind of shot.
    static func of(_ photoID: String, in result: RunResult) -> SortBucket {
        if let tag = result.excluded[photoID] {
            if case .nearDuplicate = tag { return .same }
            if tag.isHardReject { return .aside }
        }
        switch result.scores[photoID]?.category {
        case .me, .meWithView: return .you
        case .group, .friends, .someone: return .people
        case .view: return .places
        case .food: return .food
        case .detail, .other: return .details
        case nil: return .aside
        }
    }

    /// How many photos landed in each pile, in display order, empty piles left out.
    static func counts(in result: RunResult) -> [(bucket: SortBucket, count: Int)] {
        let ids = Set(result.scores.keys).union(result.excluded.keys)
        var tally: [SortBucket: Int] = [:]
        for id in ids { tally[of(id, in: result), default: 0] += 1 }
        return allCases.compactMap { b in tally[b].map { (b, $0) } }
    }
}
