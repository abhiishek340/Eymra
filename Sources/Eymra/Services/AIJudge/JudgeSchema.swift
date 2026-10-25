import Foundation

/// JSON schemas sent as structured-output formats, and parsing of the answers into scores.
nonisolated enum JudgeSchema {
    static let levels = ["bad", "poor", "fair", "good", "excellent"]
    static let categories = ["me", "me_with_view", "group", "view", "food", "detail", "other"]
    static let flags = ["eyes_closed", "blurry", "distracting_background", "awkward_expression", "cut_off", "photobomb"]
    static let ratedFields = ["sharpness", "exposure", "composition", "subject", "moment", "post_worthiness"]

    static var scoreSchema: [String: Any] {
        var itemProps: [String: Any] = [
            "image": ["type": "integer"],
            "category": ["type": "string", "enum": categories],
            "flags": ["type": "array", "items": ["type": "string", "enum": flags]],
            "reason": ["type": "string"],
        ]
        for field in ratedFields { itemProps[field] = ["$ref": "#/$defs/level"] }
        return [
            "type": "object", "additionalProperties": false, "required": ["photos"],
            "$defs": ["level": ["type": "string", "enum": levels]],
            "properties": ["photos": ["type": "array", "items": [
                "type": "object", "additionalProperties": false,
                "required": ["image", "category"] + ratedFields + ["flags", "reason"],
                "properties": itemProps,
            ]]],
        ]
    }

    static var bestOfSchema: [String: Any] {
        [
            "type": "object", "additionalProperties": false, "required": ["winner", "runner_up", "reason"],
            "properties": [
                "winner": ["type": "integer"],
                "runner_up": ["anyOf": [["type": "integer"], ["type": "null"]]],
                "reason": ["type": "string"],
            ],
        ]
    }

    // MARK: Decoding

    struct ScoreEntry: Decodable, Sendable {
        var image: Int
        var category: String
        var sharpness: String
        var exposure: String
        var composition: String
        var subject: String
        var moment: String
        var post_worthiness: String
        var flags: [String]
        var reason: String
    }

    struct ScoreAnswer: Decodable, Sendable { var photos: [ScoreEntry] }

    struct BestOf: Decodable, Sendable {
        var winner: Int
        var runner_up: Int?
        var reason: String
    }

    /// Level → 0, 0.25, 0.5, 0.75, 1 (case-insensitive); unknown words count as fair.
    static func level(_ word: String) -> Float {
        guard let i = levels.firstIndex(of: word.lowercased()) else { return 0.5 }
        return Float(i) * 0.25
    }

    static func category(_ word: String) -> Category? {
        Category(rawValue: word.lowercased())
    }

    /// J = mean of the six levels, −0.25 for blurry, −0.15 for each of the other negative flags, clamped 0–1.
    static func score(_ e: ScoreEntry) -> Float {
        let values = [e.sharpness, e.exposure, e.composition, e.subject, e.moment, e.post_worthiness].map(level)
        var j = values.reduce(0, +) / Float(values.count)
        let flags = Set(e.flags.map { $0.lowercased() })
        if flags.contains("blurry") { j -= 0.25 }
        for f in ["eyes_closed", "awkward_expression", "cut_off", "photobomb"] where flags.contains(f) { j -= 0.15 }
        return min(1, max(0, j))
    }

    /// Maps "Image k" answers back to photo IDs (1-based, in the order sent). Unknown indices are dropped.
    static func parseScores(_ json: Data, sent: [String]) throws -> [JudgeScore] {
        let answer = try JSONDecoder().decode(ScoreAnswer.self, from: json)
        return answer.photos.compactMap { e in
            guard (1...sent.count).contains(e.image) else { return nil }
            return JudgeScore(photoID: sent[e.image - 1], score: score(e), category: category(e.category),
                              flags: e.flags, reason: e.reason)
        }
    }

    static func parseBestOf(_ json: Data, sent: [String]) throws -> BestOfAnswer {
        let answer = try JSONDecoder().decode(BestOf.self, from: json)
        guard (1...sent.count).contains(answer.winner) else { throw JudgeError.badResponse("winner out of range") }
        let runner = answer.runner_up.flatMap { (1...sent.count).contains($0) ? sent[$0 - 1] : nil }
        return BestOfAnswer(winnerID: sent[answer.winner - 1], runnerUpID: runner, reason: answer.reason)
    }
}
