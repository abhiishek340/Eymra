import Foundation

/// One-line reasons for picks and "Why not?" text for excluded photos.
nonisolated enum Explanations {
    struct Context: Sendable {
        var score: PhotoScore
        var clusterSize: Int
        var sceneLabel: String
        /// How many picks in the final set share this category (including this one).
        var categoryCountInSet: Int
        var judge: JudgeVerdict?
    }

    static func reason(_ c: Context) -> String {
        if let judge = c.judge, !judge.reason.trimmingCharacters(in: .whitespaces).isEmpty {
            return judge.reason
        }
        let s = c.score
        if c.clusterSize > 1 {
            let strongest = max(s.technical, s.aesthetic, s.people ?? 0)
            if let p = s.people, p == strongest {
                return String(localized: "Best faces of \(c.clusterSize) similar shots")
            }
            if s.technical == strongest {
                return String(localized: "Sharpest of \(c.clusterSize) near-identical shots")
            }
            return String(localized: "Best-looking of \(c.clusterSize) similar shots")
        }
        let unique = c.categoryCountInSet == 1
        switch s.category {
        case .me: return String(localized: "Clear shot of you, \(c.sceneLabel)")
        case .meWithView: return String(localized: "You with the view, \(c.sceneLabel)")
        case .group: return unique ? String(localized: "The group shot of the set") : String(localized: "Everyone in frame, \(c.sceneLabel)")
        case .view: return unique ? String(localized: "Only wide view from \(c.sceneLabel)") : String(localized: "Clean view, \(c.sceneLabel)")
        case .food: return String(localized: "The food shot")
        case .detail: return String(localized: "A detail that adds variety")
        case .other: return String(localized: "Stands out from \(c.sceneLabel)")
        }
    }

    static func whyNot(_ tag: ExclusionTag) -> String {
        switch tag {
        case .screenshot: String(localized: "Screenshot / document")
        case .animated: String(localized: "Animated image")
        case .tooSmall: String(localized: "Too small (short edge under 800 px)")
        case .blurry: String(localized: "Blurry compared with similar shots")
        case .tooDark: String(localized: "Too dark")
        case .blownOut: String(localized: "Blown-out highlights")
        case .eyesClosed: String(localized: "Eyes closed; a similar shot has them open")
        case .inCloud: String(localized: "In iCloud, not downloaded")
        case .analysisFailed: String(localized: "Could not analyse")
        case .nearDuplicate(let k?): String(localized: "Near-duplicate of pick \(k)")
        case .nearDuplicate(nil): String(localized: "Near-duplicate, not picked")
        case .sameBackground(let k): String(localized: "Same background as pick \(k)")
        case .sceneCap(let k): String(localized: "Enough picks from this place already (see pick \(k))")
        case .belowCut(let rank): String(localized: "Ranked #\(rank), below the cut")
        case .hidden: String(localized: "Hidden by you")
        case .categoryQuota: String(localized: "Enough of this kind of shot already")
        }
    }

    static func categoryName(_ c: Category) -> String {
        switch c {
        case .me: String(localized: "Me")
        case .meWithView: String(localized: "Me + view")
        case .group: String(localized: "Group")
        case .view: String(localized: "View")
        case .food: String(localized: "Food")
        case .detail: String(localized: "Detail")
        case .other: String(localized: "Other")
        }
    }
}
