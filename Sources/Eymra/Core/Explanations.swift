import Foundation

/// Short, friendly reasons for picks and "Why not?" text for photos that didn't make it. Plain words only.
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
                return s.withMe == true
                    ? String(localized: "You look your best in this one, out of \(c.clusterSize) tries")
                    : String(localized: "Best faces out of \(c.clusterSize) almost-same shots")
            }
            if s.technical == strongest {
                return String(localized: "The sharpest of \(c.clusterSize) almost-same shots")
            }
            return String(localized: "The best-looking of \(c.clusterSize) almost-same shots")
        }
        let unique = c.categoryCountInSet == 1
        switch s.category {
        case .me: return String(localized: "A great one of you · \(c.sceneLabel)")
        case .meWithView: return String(localized: "You and the view · \(c.sceneLabel)")
        case .group: return unique ? String(localized: "You with your people") : String(localized: "Everyone together · \(c.sceneLabel)")
        case .friends: return String(localized: "Your friends · \(c.sceneLabel)")
        case .someone: return String(localized: "A people shot · \(c.sceneLabel)")
        case .view: return unique ? String(localized: "The big view of the day") : String(localized: "A beautiful view · \(c.sceneLabel)")
        case .food: return String(localized: "The food moment")
        case .detail: return String(localized: "A small detail that adds to the story")
        case .other: return String(localized: "Stands out · \(c.sceneLabel)")
        }
    }

    static func whyNot(_ tag: ExclusionTag) -> String {
        switch tag {
        case .screenshot: String(localized: "This is a screenshot or a document")
        case .animated: String(localized: "This is a moving image")
        case .tooSmall: String(localized: "This photo is too small")
        case .blurry: String(localized: "A bit blurry, and there's a sharper one")
        case .tooDark: String(localized: "Too dark")
        case .blownOut: String(localized: "Too bright, parts are washed out")
        case .eyesClosed: String(localized: "Eyes closed, and there's one with eyes open")
        case .inCloud: String(localized: "Still in iCloud, not on your phone yet")
        case .analysisFailed: String(localized: "We couldn't read this photo")
        case .nearDuplicate(let k?): String(localized: "Almost the same as photo \(k)")
        case .nearDuplicate(nil): String(localized: "Almost the same as another photo")
        case .sameBackground(let k): String(localized: "Same spot as photo \(k)")
        case .sceneCap: String(localized: "We already have enough from this place")
        case .belowCut(let rank): String(localized: "Good, but it came #\(rank) and just missed out")
        case .hidden: String(localized: "You hid this one")
        case .categoryQuota: String(localized: "We already have enough of this kind of photo")
        case .identityUnconfirmed: String(localized: "Me only picks photos where we're sure it's you")
        }
    }

    static func categoryName(_ c: Category) -> String {
        switch c {
        case .me: String(localized: "You")
        case .meWithView: String(localized: "You + view")
        case .group: String(localized: "Group")
        case .friends: String(localized: "Friends")
        case .someone: String(localized: "Someone")
        case .view: String(localized: "View")
        case .food: String(localized: "Food")
        case .detail: String(localized: "Detail")
        case .other: String(localized: "Moment")
        }
    }

    static func roleName(_ role: StoryRole) -> String {
        switch role {
        case .opener: String(localized: "Opens your story")
        case .closer: String(localized: "Ends your story")
        }
    }

    /// A simple title when Claude isn't helping, e.g. "Your Saturday" or "Your 3 days away".
    static func storyTitle(range: DateInterval, sceneCount: Int) -> String {
        let calendar = Calendar.current
        let days = (calendar.dateComponents([.day], from: calendar.startOfDay(for: range.start),
                                            to: calendar.startOfDay(for: range.end)).day ?? 0) + 1
        if days <= 1 {
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return String(localized: "Your \(f.string(from: range.start))")
        }
        return sceneCount > 1 ? String(localized: "Your \(days) days, \(sceneCount) places") : String(localized: "Your \(days) days")
    }
}
