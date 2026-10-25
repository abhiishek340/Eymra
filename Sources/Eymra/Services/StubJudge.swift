import Foundation

/// Offline judge for tests and -uiTesting: deterministic scores derived from the image bytes.
nonisolated struct StubJudge: JudgeProvider {
    var model = "stub"
    var promptVersion = JudgePrompt.version
    var failure: JudgeError?

    func score(_ images: [JudgeImage]) async throws -> [JudgeScore] {
        if let failure { throw failure }
        return images.map { image in
            let hash = image.jpeg.prefix(4096).reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFF }
            return JudgeScore(photoID: image.photoID, score: 0.4 + Float(hash % 50) / 100, category: nil,
                              flags: [], reason: String(localized: "Looks good to post"))
        }
    }

    func bestOf(_ images: [JudgeImage]) async throws -> BestOfAnswer {
        if let failure { throw failure }
        guard let first = images.first else { throw JudgeError.badResponse("empty") }
        return BestOfAnswer(winnerID: first.photoID, runnerUpID: images.dropFirst().first?.photoID, reason: "")
    }
}
