import Foundation
import os

/// Stage 6: pointwise rubric scoring in shuffled batches, a second pass for finalists, best-of calls for close clusters.
/// Any failure discards the judge's output so the on-device result stands.
nonisolated struct JudgeStage: Sendable {
    struct Output: Sendable {
        var verdicts: [String: JudgeVerdict]
        /// Cluster ID → new winner chosen by best-of calls.
        var newWinners: [String: String]
        var imagesSent: Int
        /// A story title for the set; nil when the title call failed (it never fails the stage).
        var title: String?
    }

    private static let log = Logger(subsystem: "app.eymra", category: "judge")

    let provider: any JudgeProvider
    let source: any PhotoSource
    let store: FeatureStore
    let longEdge: Int
    let allowNetwork: Bool

    func run(clusters: [Cluster], scores: [String: PhotoScore], targetCount: Int,
             progress: @Sendable (Int, Int) -> Void) async throws -> Output {
        let shortlist = Self.shortlist(clusters: clusters, scores: scores)
        guard !shortlist.isEmpty else { return Output(verdicts: [:], newWinners: [:], imagesSent: 0, title: nil) }
        let images = try await render(shortlist)
        var sent = 0

        // Call 1 – pointwise scoring, pass 1.
        var pass1 = try await scored(ids: shortlist, images: images, pass: 1, sent: &sent, progress: progress)

        // Finalists (top 2N winners by R) get a second pass in a different shuffle.
        let winners = clusters.map(\.winnerID)
        let finalists = winners
            .sorted { Self.relevance($0, scores: scores, judge: pass1) > Self.relevance($1, scores: scores, judge: pass1) }
            .prefix(targetCount * 2)
        let pass2 = try await scored(ids: Array(finalists), images: images, pass: 2, sent: &sent, progress: progress)
        for (id, second) in pass2 {
            if let first = pass1[id] { pass1[id]?.score = (first.score + second.score) / 2 }
        }

        // Call 2 – best-of inside close clusters, asked in both orders.
        var newWinners: [String: String] = [:]
        let close = clusters
            .filter { c in
                guard let runner = c.runnerUpIDs.first, let qw = scores[c.winnerID]?.quality, let qr = scores[runner]?.quality else { return false }
                return qw - qr < Tuning.judgeCloseCallMargin
            }
            .sorted { $0.size > $1.size }
            .prefix(Tuning.judgeMaxClusterCalls)
        for cluster in close {
            let ids = [cluster.winnerID] + cluster.runnerUpIDs.prefix(Tuning.judgeRunnerUpsPerCluster)
            let batch = ids.compactMap { id in images[id].map { JudgeImage(photoID: id, jpeg: $0) } }
            guard batch.count >= 2 else { continue }
            let forward = try await provider.bestOf(batch)
            let backward = try await provider.bestOf(batch.reversed())
            sent += batch.count * 2
            if forward.winnerID == backward.winnerID, forward.winnerID != cluster.winnerID {
                newWinners[cluster.id] = forward.winnerID
            }
        }

        // A title from the strongest winners (up to 8 images); a failure here keeps the simple title.
        let titleIDs = winners
            .sorted { Self.relevance($0, scores: scores, judge: pass1) > Self.relevance($1, scores: scores, judge: pass1) }
            .prefix(min(8, targetCount))
        let titleImages = titleIDs.compactMap { id in images[id].map { JudgeImage(photoID: id, jpeg: $0) } }
        let title = titleImages.isEmpty ? nil : try? await provider.title(titleImages)
        sent += titleImages.count

        let verdicts = pass1.mapValues { s in
            JudgeVerdict(photoID: s.photoID, score: s.score, category: s.category ?? scores[s.photoID]?.category ?? .other,
                         reason: s.reason, model: provider.model, promptVersion: provider.promptVersion)
        }
        return Output(verdicts: verdicts, newWinners: newWinners, imagesSent: sent, title: title)
    }

    /// Every cluster winner plus up to two runner-ups, capped: runner-ups go first, then the lowest-Q winners.
    static func shortlist(clusters: [Cluster], scores: [String: PhotoScore]) -> [String] {
        let byQ = clusters.sorted { (scores[$0.winnerID]?.quality ?? 0) > (scores[$1.winnerID]?.quality ?? 0) }
        var winners = byQ.map(\.winnerID)
        var runners = byQ.flatMap { $0.runnerUpIDs.prefix(Tuning.judgeRunnerUpsPerCluster) }
        let cap = Tuning.judgeMaxImages
        if winners.count + runners.count > cap { runners = Array(runners.prefix(max(0, cap - winners.count))) }
        if winners.count > cap { winners = Array(winners.prefix(cap)) }
        return winners + runners
    }

    static func relevance(_ id: String, scores: [String: PhotoScore], judge: [String: JudgeScore]) -> Float {
        let q = scores[id]?.quality ?? 0
        guard let j = judge[id]?.score else { return q }
        return (1 - Tuning.judgeWeight) * q + Tuning.judgeWeight * j
    }

    // MARK: Helpers

    private func render(_ ids: [String]) async throws -> [String: Data] {
        let source = source, longEdge = longEdge, allow = allowNetwork
        return try await withThrowingTaskGroup(of: (String, Data?).self) { group in
            var out: [String: Data] = [:]
            var pending = ids[...]
            func addNext() {
                guard let id = pending.popFirst() else { return }
                group.addTask {
                    let image = try? await source.image(for: id, longEdge: Double(longEdge), allowNetwork: allow)
                    return (id, image.flatMap { Renderer.jpeg($0, longEdge: longEdge, quality: Tuning.judgeJPEGQuality) })
                }
            }
            for _ in 0..<4 { addNext() }
            while let (id, data) = try await group.next() {
                if let data { out[id] = data }
                addNext()
            }
            return out
        }
    }

    /// Scores `ids` for one pass, using cached verdicts where present. Batches of ≤ 20, shuffled, ≤ 4 at once.
    private func scored(ids: [String], images: [String: Data], pass: Int, sent: inout Int,
                        progress: @Sendable (Int, Int) -> Void) async throws -> [String: JudgeScore] {
        let keyFor = { (id: String) in "\(id)|\(provider.model)|\(provider.promptVersion)|\(longEdge)|\(pass)" }
        let cached = await store.verdicts(for: ids.map(keyFor))
        var out: [String: JudgeScore] = [:]
        var todo: [String] = []
        for id in ids {
            if let c = cached[keyFor(id)] {
                out[id] = JudgeScore(photoID: id, score: c.score, category: Category(rawValue: c.category), flags: [], reason: c.reason)
            } else if images[id] != nil {
                todo.append(id)
            }
        }
        let batches = stride(from: 0, to: todo.count, by: Tuning.judgeBatchSize).map {
            Array(todo[$0..<min($0 + Tuning.judgeBatchSize, todo.count)]).shuffled()
        }
        let provider = provider
        var done = 0
        try await withThrowingTaskGroup(of: [JudgeScore].self) { group in
            var pending = batches[...]
            func addNext() {
                guard let batch = pending.popFirst() else { return }
                let payload = batch.compactMap { id in images[id].map { JudgeImage(photoID: id, jpeg: $0) } }
                group.addTask { try await provider.score(payload) }
            }
            for _ in 0..<Tuning.judgeConcurrentBatches { addNext() }
            while let result = try await group.next() {
                for s in result { out[s.photoID] = s }
                done += 1
                progress(done, batches.count)
                addNext()
            }
        }
        sent += todo.count
        var toCache: [String: CachedVerdictValue] = [:]
        for id in todo {
            if let s = out[id] { toCache[keyFor(id)] = CachedVerdictValue(score: s.score, category: s.category?.rawValue ?? "", reason: s.reason) }
        }
        await store.saveVerdicts(toCache)
        return out
    }
}
