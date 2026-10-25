import CoreGraphics
import Foundation

nonisolated enum LibraryAccess: Sendable, Equatable {
    case notDetermined, denied, limited, full

    var isUsable: Bool { self == .limited || self == .full }
}

nonisolated enum PhotoSourceError: Error, Sendable {
    case notFound
    case inCloud
    case decodeFailed
}

/// Read access to the photo library (PhotoKit in the app, bundled fixtures under -uiTesting and in tests).
nonisolated protocol PhotoSource: Sendable {
    func authorizationStatus() -> LibraryAccess
    func requestAuthorization() async -> LibraryAccess
    func count(in range: DateInterval) async -> Int
    /// Every image in the range, oldest first, one representative per burst.
    func records(in range: DateInterval) async throws -> [PhotoRecord]
    /// A rendition with the given long edge, `.up` orientation.
    func image(for id: String, longEdge: Double, allowNetwork: Bool) async throws -> CGImage
}

/// Stage 2: per-photo feature extraction.
nonisolated protocol FeatureExtracting: Sendable {
    /// Revision of the feature print this extractor produces; cache entries with another revision are re-analysed.
    var featurePrintRevision: Int { get }
    func extract(_ record: PhotoRecord, from source: any PhotoSource, allowNetwork: Bool) async throws -> FeatureRecord
}

/// One image sent to the judge: metadata-free JPEG bytes.
nonisolated struct JudgeImage: Sendable, Hashable {
    var photoID: String
    var jpeg: Data
}

/// Pointwise rubric answer for one image, already mapped to a 0–1 score.
nonisolated struct JudgeScore: Sendable, Hashable {
    var photoID: String
    var score: Float
    /// nil when the provider gave no category; the heuristic one is kept.
    var category: Category?
    var flags: [String]
    var reason: String
}

nonisolated struct BestOfAnswer: Sendable, Hashable {
    var winnerID: String
    var runnerUpID: String?
    var reason: String
}

nonisolated enum JudgeError: Error, Sendable, Equatable {
    case missingKey
    case offline
    case http(status: Int, message: String)
    case badResponse(String)
}

/// Stage 6: the optional cloud judge. ClaudeJudge in v1; OpenAI and Gemini later.
nonisolated protocol JudgeProvider: Sendable {
    var model: String { get }
    var promptVersion: Int { get }
    /// Scores each image on its own. Images arrive already shuffled.
    func score(_ images: [JudgeImage]) async throws -> [JudgeScore]
    /// Picks the one to post among near-identical shots.
    func bestOf(_ images: [JudgeImage]) async throws -> BestOfAnswer
}
