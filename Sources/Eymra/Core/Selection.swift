import Foundation

/// Stage 7: greedy Maximal Marginal Relevance over cluster winners with hard constraints and soft bonuses.
nonisolated enum Selection {
    struct Candidate: Sendable, Hashable {
        var photoID: String
        var sceneID: String
        var clusterID: String
        var relevance: Float
        var category: Category
        var featurePrint: [Float]
        var date: Date
        /// Whether the user is in it; nil when we can't tell.
        var withMe: Bool? = nil
        /// How much this photo's place mattered (photos taken there, normalised 0–1). 0 turns coverage off.
        var sceneWeight: Float = 0
    }

    enum Constraint: String, CaseIterable, Sendable {
        case categoryQuota, sceneCap, sameBackground

        var relaxationNote: String {
            switch self {
            case .categoryQuota: String(localized: "We used a few more of the same kind of photo to reach your number")
            case .sceneCap: String(localized: "We used a few more from one place to reach your number")
            case .sameBackground: String(localized: "We used two photos from the same spot to reach your number")
            }
        }
    }

    struct Result: Sendable {
        var selected: [String]
        var relaxed: [Constraint]
        var shortfall: Int
    }

    static func sceneCap(count: Int) -> Int {
        max(Tuning.sceneCapMinimum, Int((Double(count) * Tuning.sceneCapShare).rounded(.up)))
    }

    static func categoryCap(count: Int) -> Int {
        max(2, Int((Double(count) * Tuning.categoryCapShare).rounded(.up)))
    }

    static func select(candidates: [Candidate], count: Int, mix: Mix, locked: [String] = [],
                       prefs: UserPrefs = UserPrefs()) -> Result {
        let byID = Dictionary(candidates.map { ($0.photoID, $0) }, uniquingKeysWith: { a, _ in a })
        var selected: [Candidate] = locked.compactMap { byID[$0] }
        var remaining = candidates.filter { c in !selected.contains { $0.photoID == c.photoID } }
        var active = Set(Constraint.allCases)
        var relaxed: [Constraint] = []

        while selected.count < count && !remaining.isEmpty {
            var best: (index: Int, value: Float)?
            for (i, c) in remaining.enumerated() where violation(c, selected: selected, count: count, active: active) == nil {
                let value = marginalValue(c, selected: selected, mix: mix, prefs: prefs)
                if best == nil || value > (best?.value ?? -.infinity) { best = (i, value) }
            }
            if let best {
                selected.append(remaining.remove(at: best.index))
            } else if let next = Constraint.allCases.first(where: { active.contains($0) }) {
                active.remove(next)
                relaxed.append(next)
            } else {
                break
            }
        }
        return Result(selected: selected.map(\.photoID), relaxed: relaxed, shortfall: max(0, count - selected.count))
    }

    static func marginalValue(_ c: Candidate, selected: [Candidate], mix: Mix, prefs: UserPrefs = UserPrefs()) -> Float {
        let maxSim = selected.map { similarity(c, $0) }.max() ?? 0
        var value = Tuning.mmrLambda * c.relevance - (1 - Tuning.mmrLambda) * maxSim
        if !selected.contains(where: { $0.category == c.category }) { value += Tuning.newCategoryBonus }
        switch mix {
        case .moreOfMe where c.category.isPeople && c.category != .friends: value += Tuning.mixBonus
        case .moreScenery where c.category == .view || c.category == .meWithView: value += Tuning.mixBonus
        default: break
        }
        // Coverage: the first photo from a place tells a new part of the story; bigger places matter more.
        if c.sceneWeight > 0, !selected.contains(where: { $0.sceneID == c.sceneID }) {
            value += Tuning.coverageBonus * c.sceneWeight
        }
        value += personal(c, selected: selected, prefs: prefs)
        return value
    }

    /// Steers the set toward the share of "you" photos the user asked for, and how they feel about group shots.
    /// Does nothing when we can't tell who is in the photo.
    static func personal(_ c: Candidate, selected: [Candidate], prefs: UserPrefs) -> Float {
        guard let withMe = c.withMe else { return 0 }
        var value: Float = 0
        let known = selected.filter { $0.withMe != nil }
        let share = known.isEmpty ? 0 : Float(known.filter { $0.withMe == true }.count) / Float(known.count)
        if withMe && share < prefs.meShareTarget { value += Tuning.meShareBonus }
        if !withMe {
            // Photos of friends without the user: how much that costs depends on what the user posts.
            var penalty: Float = switch prefs.groups {
            case .rarely: Tuning.friendsOnlyPenaltyRarely
            case .sometimes: prefs.style == .meAndFriends ? 0 : Tuning.friendsOnlyPenaltySometimes
            case .love: 0
            }
            if prefs.style == .mostlyMe { penalty = max(penalty, Tuning.friendsOnlyPenaltyRarely) }
            value -= penalty
        }
        if withMe && c.category == .group {
            switch prefs.groups {
            case .love: value += Tuning.groupLoveBonus
            case .rarely: value -= Tuning.groupRarelyPenalty
            case .sometimes: break
            }
        }
        return value
    }

    static func similarity(_ a: Candidate, _ b: Candidate) -> Float {
        guard let d = VectorMath.distance(a.featurePrint, b.featurePrint) else { return 0 }
        return VectorMath.similarity(fromDistance: d)
    }

    static func sharesBackground(_ a: Candidate, _ b: Candidate) -> Bool {
        guard a.clusterID != b.clusterID, let d = VectorMath.distance(a.featurePrint, b.featurePrint) else { return false }
        return d < Tuning.sameBackgroundDistance
    }

    /// The first active constraint `c` breaks against the current selection, if any.
    static func violation(_ c: Candidate, selected: [Candidate], count: Int, active: Set<Constraint>) -> Constraint? {
        if active.contains(.sameBackground), selected.contains(where: { sharesBackground(c, $0) }) { return .sameBackground }
        if active.contains(.sceneCap), selected.filter({ $0.sceneID == c.sceneID }).count >= sceneCap(count: count) { return .sceneCap }
        if active.contains(.categoryQuota), selected.filter({ $0.category == c.category }).count >= categoryCap(count: count) {
            return .categoryQuota
        }
        return nil
    }

    /// Tags for candidates that did not make the cut. `ordered` is the final posting order (pick k = index + 1).
    static func exclusionTags(candidates: [Candidate], ordered: [String], count: Int) -> [String: ExclusionTag] {
        let byID = Dictionary(candidates.map { ($0.photoID, $0) }, uniquingKeysWith: { a, _ in a })
        let picks = ordered.compactMap { byID[$0] }
        let ranked = candidates.sorted { $0.relevance > $1.relevance }
        var tags: [String: ExclusionTag] = [:]
        for (rank, c) in ranked.enumerated() where !ordered.contains(c.photoID) {
            if let k = picks.firstIndex(where: { sharesBackground(c, $0) }) {
                tags[c.photoID] = .sameBackground(asPick: k + 1)
            } else if picks.filter({ $0.sceneID == c.sceneID }).count >= sceneCap(count: count),
                      let k = picks.firstIndex(where: { $0.sceneID == c.sceneID }) {
                tags[c.photoID] = .sceneCap(pick: k + 1)
            } else if picks.filter({ $0.category == c.category }).count >= categoryCap(count: count) {
                tags[c.photoID] = .categoryQuota
            } else {
                tags[c.photoID] = .belowCut(rank: rank + 1)
            }
        }
        return tags
    }
}
