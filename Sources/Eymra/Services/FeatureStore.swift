import Foundation
import SwiftData
import os

@Model final class CachedFeatures {
    @Attribute(.unique) var localIdentifier: String
    var schemaVersion: Int
    /// Re-analyse when the asset was edited after analysedAt.
    var assetModificationDate: Date?
    var analysedAt: Date
    /// elementCount Float32 values (768 on revision 2).
    var featurePrint: Data
    var featurePrintRevision: Int
    var aestheticScore: Float?
    var isUtility: Bool
    var faces: Data
    var humanBoxes: Data
    var saliencyBox: Data?
    var labels: Data
    var horizonDegrees: Float?
    var sharpness: Float
    var darkFraction: Float
    var brightFraction: Float
    var meanLuma: Float
    /// 1,024 bytes of 0–255 luma, row-major.
    var thumb32: Data

    init(localIdentifier: String, schemaVersion: Int, assetModificationDate: Date?, analysedAt: Date,
         featurePrint: Data, featurePrintRevision: Int, aestheticScore: Float?, isUtility: Bool, faces: Data,
         humanBoxes: Data, saliencyBox: Data?, labels: Data, horizonDegrees: Float?, sharpness: Float,
         darkFraction: Float, brightFraction: Float, meanLuma: Float, thumb32: Data) {
        self.localIdentifier = localIdentifier
        self.schemaVersion = schemaVersion
        self.assetModificationDate = assetModificationDate
        self.analysedAt = analysedAt
        self.featurePrint = featurePrint
        self.featurePrintRevision = featurePrintRevision
        self.aestheticScore = aestheticScore
        self.isUtility = isUtility
        self.faces = faces
        self.humanBoxes = humanBoxes
        self.saliencyBox = saliencyBox
        self.labels = labels
        self.horizonDegrees = horizonDegrees
        self.sharpness = sharpness
        self.darkFraction = darkFraction
        self.brightFraction = brightFraction
        self.meanLuma = meanLuma
        self.thumb32 = thumb32
    }
}

@Model final class CachedJudgeVerdict {
    /// "\(photoID)|\(model)|\(promptVersion)|\(longEdge)|\(pass)"
    @Attribute(.unique) var key: String
    var score: Float
    var category: String
    var reason: String
    var createdAt: Date

    init(key: String, score: Float, category: String, reason: String, createdAt: Date) {
        self.key = key
        self.score = score
        self.category = category
        self.reason = reason
        self.createdAt = createdAt
    }
}

@Model final class SavedRun {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var config: Data
    /// JSON RunResult.
    var result: Data

    init(id: UUID, createdAt: Date, config: Data, result: Data) {
        self.id = id
        self.createdAt = createdAt
        self.config = config
        self.result = result
    }
}

@Model final class UserMarks {
    @Attribute(.unique) var localIdentifier: String
    var isHidden: Bool

    init(localIdentifier: String, isHidden: Bool) {
        self.localIdentifier = localIdentifier
        self.isHidden = isHidden
    }
}

/// The only writer of the cache. Everything crossing its boundary is a plain value type.
@ModelActor
actor FeatureStore {
    static let schema = Schema([CachedFeatures.self, CachedJudgeVerdict.self, SavedRun.self, UserMarks.self])
    private static let log = Logger(subsystem: "app.eymra", category: "store")
    private static let maxSavedRuns = 20

    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    // MARK: Features

    func features(for ids: [String]) -> [String: FeatureRecord] {
        var out: [String: FeatureRecord] = [:]
        for start in stride(from: 0, to: ids.count, by: 200) {
            let chunk = Array(ids[start..<min(start + 200, ids.count)])
            let descriptor = FetchDescriptor<CachedFeatures>(predicate: #Predicate { chunk.contains($0.localIdentifier) })
            do {
                for row in try modelContext.fetch(descriptor) {
                    if let record = Self.record(from: row) { out[row.localIdentifier] = record }
                }
            } catch {
                Self.log.error("Feature fetch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return out
    }

    /// Analysis dates for cache-staleness checks.
    func analysedDates(for ids: [String]) -> [String: Date] {
        var out: [String: Date] = [:]
        for start in stride(from: 0, to: ids.count, by: 200) {
            let chunk = Array(ids[start..<min(start + 200, ids.count)])
            let descriptor = FetchDescriptor<CachedFeatures>(predicate: #Predicate { chunk.contains($0.localIdentifier) })
            for row in (try? modelContext.fetch(descriptor)) ?? [] { out[row.localIdentifier] = row.analysedAt }
        }
        return out
    }

    func save(_ records: [FeatureRecord], modificationDates: [String: Date] = [:]) {
        guard !records.isEmpty else { return }
        let ids = records.map(\.photoID)
        let existing = (try? modelContext.fetch(FetchDescriptor<CachedFeatures>(predicate: #Predicate { ids.contains($0.localIdentifier) }))) ?? []
        for row in existing { modelContext.delete(row) }
        let now = Date()
        for r in records {
            modelContext.insert(CachedFeatures(
                localIdentifier: r.photoID, schemaVersion: r.schemaVersion,
                assetModificationDate: modificationDates[r.photoID], analysedAt: now,
                featurePrint: Self.data(r.featurePrint), featurePrintRevision: r.featurePrintRevision,
                aestheticScore: r.aestheticScore, isUtility: r.isUtility, faces: Self.json(r.faces),
                humanBoxes: Self.json(r.humanBoxes), saliencyBox: r.saliencyBox.map { Self.json($0) },
                labels: Self.json(r.labels), horizonDegrees: r.horizonDegrees, sharpness: r.sharpness,
                darkFraction: r.darkFraction, brightFraction: r.brightFraction, meanLuma: r.meanLuma,
                thumb32: Data(r.thumb32)))
        }
        do { try modelContext.save() } catch {
            Self.log.error("Feature save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// True when a cache entry must be re-analysed (spec §5 cache rules). Pure, so callable without hopping.
    nonisolated func isStale(_ record: FeatureRecord?, analysedAt: Date?, photo: PhotoRecord, revision: Int) -> Bool {
        guard let record else { return true }
        if record.schemaVersion != FeatureSchema.version { return true }
        if record.featurePrintRevision != revision { return true }
        if let modified = photo.modificationDate, let analysedAt, modified > analysedAt { return true }
        return false
    }

    // MARK: Judge verdicts

    func verdicts(for keys: [String]) -> [String: CachedVerdictValue] {
        let descriptor = FetchDescriptor<CachedJudgeVerdict>(predicate: #Predicate { keys.contains($0.key) })
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return Dictionary(rows.map { ($0.key, CachedVerdictValue(score: $0.score, category: $0.category, reason: $0.reason)) },
                          uniquingKeysWith: { a, _ in a })
    }

    func saveVerdicts(_ values: [String: CachedVerdictValue]) {
        guard !values.isEmpty else { return }
        let keys = Array(values.keys)
        let existing = (try? modelContext.fetch(FetchDescriptor<CachedJudgeVerdict>(predicate: #Predicate { keys.contains($0.key) }))) ?? []
        for row in existing { modelContext.delete(row) }
        for (key, v) in values {
            modelContext.insert(CachedJudgeVerdict(key: key, score: v.score, category: v.category, reason: v.reason, createdAt: Date()))
        }
        try? modelContext.save()
    }

    // MARK: Runs

    func saveRun(_ run: RunResult) {
        do {
            let encoder = JSONEncoder()
            modelContext.insert(SavedRun(id: run.id, createdAt: run.createdAt,
                                         config: try encoder.encode(run.config), result: try encoder.encode(run)))
            try modelContext.save()
            var all = FetchDescriptor<SavedRun>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            all.fetchOffset = Self.maxSavedRuns
            for old in try modelContext.fetch(all) { modelContext.delete(old) }
            try modelContext.save()
        } catch {
            Self.log.error("Run save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func latestRun(matching config: RunConfig) -> RunResult? {
        let descriptor = FetchDescriptor<SavedRun>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let decoder = JSONDecoder()
        for row in (try? modelContext.fetch(descriptor)) ?? [] {
            if let c = try? decoder.decode(RunConfig.self, from: row.config), c == config {
                return try? decoder.decode(RunResult.self, from: row.result)
            }
        }
        return nil
    }

    func latestRun() -> RunResult? {
        var descriptor = FetchDescriptor<SavedRun>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let row = try? modelContext.fetch(descriptor).first else { return nil }
        return try? JSONDecoder().decode(RunResult.self, from: row.result)
    }

    // MARK: Hides

    func hiddenIDs() -> Set<String> {
        let rows = (try? modelContext.fetch(FetchDescriptor<UserMarks>(predicate: #Predicate { $0.isHidden }))) ?? []
        return Set(rows.map(\.localIdentifier))
    }

    func setHidden(_ id: String, _ hidden: Bool) {
        let rows = (try? modelContext.fetch(FetchDescriptor<UserMarks>(predicate: #Predicate { $0.localIdentifier == id }))) ?? []
        if let row = rows.first { row.isHidden = hidden } else { modelContext.insert(UserMarks(localIdentifier: id, isHidden: hidden)) }
        try? modelContext.save()
    }

    func clearHidden() {
        try? modelContext.delete(model: UserMarks.self)
        try? modelContext.save()
    }

    func clearFeatures() {
        try? modelContext.delete(model: CachedFeatures.self)
        try? modelContext.delete(model: CachedJudgeVerdict.self)
        try? modelContext.save()
    }

    // MARK: Encoding

    static func data(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func floats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private static func json<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    private static func record(from row: CachedFeatures) -> FeatureRecord? {
        FeatureRecord(photoID: row.localIdentifier, schemaVersion: row.schemaVersion,
                      featurePrint: floats(row.featurePrint), featurePrintRevision: row.featurePrintRevision,
                      aestheticScore: row.aestheticScore, isUtility: row.isUtility,
                      faces: decode([FaceFeature].self, row.faces) ?? [],
                      humanBoxes: decode([NormRect].self, row.humanBoxes) ?? [],
                      saliencyBox: row.saliencyBox.flatMap { decode(NormRect.self, $0) },
                      labels: decode([LabelScore].self, row.labels) ?? [],
                      horizonDegrees: row.horizonDegrees, sharpness: row.sharpness,
                      darkFraction: row.darkFraction, brightFraction: row.brightFraction,
                      meanLuma: row.meanLuma, thumb32: [UInt8](row.thumb32))
    }
}

nonisolated struct CachedVerdictValue: Sendable, Hashable {
    var score: Float
    var category: String
    var reason: String
}
