import Foundation
import os

/// Runs the eight stages. Stages 1–5 and 7–8 are on-device and deterministic; stage 6 is the optional judge.
actor CurationPipeline {
    struct Options: Sendable {
        var allowNetwork = true
        var judgeLongEdge = 756
        /// Photo IDs locked by the user in the run being re-run; they stay in the set.
        var locked: [String] = []
        /// The user's face prints, so photos with them in can be told apart from photos of friends.
        var me: MeReference?
    }

    private static let log = Logger(subsystem: "app.eymra", category: "pipeline")

    let source: any PhotoSource
    let extractor: any FeatureExtracting
    let store: FeatureStore
    let judge: (any JudgeProvider)?

    init(source: any PhotoSource, extractor: any FeatureExtracting, store: FeatureStore, judge: (any JudgeProvider)?) {
        self.source = source
        self.extractor = extractor
        self.store = store
        self.judge = judge
    }

    func run(_ config: RunConfig, options: Options = Options(),
             progress: AsyncStream<PipelineProgress>.Continuation? = nil) async throws -> RunResult {
        let preset = PlatformPreset.preset(config.platform)
        var stats = RunStats()
        var excluded: [String: ExclusionTag] = [:]
        var timer = StageTimer()
        @Sendable func report(_ stage: PipelineProgress.Stage, _ done: Int, _ total: Int, inCloud: Int = 0) {
            progress?.yield(PipelineProgress(stage: stage, completed: done, total: total, inCloud: inCloud))
        }

        // Stage 1 – ingest and filter.
        report(.ingest, 0, 0)
        timer.begin(.ingest)
        let all = try await source.records(in: config.range)
        let hidden = await store.hiddenIDs()
        var photos: [PhotoRecord] = []
        var bursts = Set<String>()
        for r in all {
            if r.isScreenshot { excluded[r.id] = .screenshot }
            else if r.isAnimated { excluded[r.id] = .animated }
            else if r.shortEdge < Tuning.minShortEdge { excluded[r.id] = .tooSmall }
            else if hidden.contains(r.id) { excluded[r.id] = .hidden }
            else if let burst = r.burstIdentifier, !bursts.insert(burst).inserted { continue }
            else { photos.append(r) }
        }
        stats.photoCount = all.count
        timer.end()
        try Task.checkCancellation()

        // Stage 2 – features (cached).
        timer.begin(.analyse)
        let features = try await analyse(photos, options: options, excluded: &excluded) { done, total, cloud in
            report(.analyse, done, total, inCloud: cloud)
        }
        timer.end()
        let analysed = photos.filter { features[$0.id] != nil }
        let photoByID = Dictionary(uniqueKeysWithValues: analysed.map { ($0.id, $0) })
        try Task.checkCancellation()

        // Stage 3 – scenes.
        report(.scenes, 0, 0)
        timer.begin(.scenes)
        let scenes = Segmentation.segment(photos: analysed, features: features)
        timer.end()

        // Stage 4 – near-duplicate clusters.
        report(.clusters, 0, scenes.count)
        timer.begin(.clusters)
        let groups: [(sceneID: String, members: [String])] = scenes.flatMap { scene in
            Clustering.clusters(in: scene, photos: photoByID, features: features).map { (scene.id, $0) }
        }
        timer.end()
        try Task.checkCancellation()

        // Stage 5 – scoring and winners.
        report(.scoring, 0, analysed.count)
        timer.begin(.scoring)
        var scored = Scoring.score(photos: photoByID, features: features, scenes: scenes, groups: groups,
                                   primaryRatio: preset.primaryRatio, me: options.me)
        if options.me != nil {
            if scored.scores.values.contains(where: { $0.withMe == true }) {
                stats.recognisedMe = true
            } else {
                // Set up but never found: treat everyone the same rather than calling every face "friends".
                scored = Scoring.score(photos: photoByID, features: features, scenes: scenes, groups: groups,
                                       primaryRatio: preset.primaryRatio, me: nil)
                stats.meNote = String(localized: "We couldn't spot you in these photos, so we treated everyone the same.")
            }
        }
        timer.end()
        report(.scoring, analysed.count, analysed.count)
        var scores = scored.scores
        var clusters = scored.clusters
        excluded.merge(scored.excluded) { a, _ in a }

        // Locks: a locked runner-up becomes its cluster's winner for this run.
        let locked = options.locked.filter { scores[$0] != nil && excluded[$0] == nil }
        for id in locked {
            if let i = clusters.firstIndex(where: { $0.memberIDs.contains(id) }), clusters[i].winnerID != id {
                Self.promote(id, in: &clusters[i])
            }
        }

        // Stage 6 – AI Judge (optional; any failure keeps the on-device result).
        var verdicts: [String: JudgeVerdict] = [:]
        var storyTitle: String?
        if config.judgeEnabled {
            if let judge {
                report(.judge, 0, 0)
                let stage = JudgeStage(provider: judge, source: source, store: store, longEdge: options.judgeLongEdge,
                                       allowNetwork: options.allowNetwork)
                do {
                    timer.begin(.judge)
                    defer { timer.end() }
                    let out = try await stage.run(clusters: clusters, scores: scores, targetCount: config.count) { done, total in
                        report(.judge, done, total)
                    }
                    verdicts = out.verdicts
                    for (clusterID, winner) in out.newWinners where !locked.contains(where: { clusters.first { $0.id == clusterID }?.memberIDs.contains($0) ?? false }) {
                        if let i = clusters.firstIndex(where: { $0.id == clusterID }) { Self.promote(winner, in: &clusters[i]) }
                    }
                    for (id, v) in verdicts {
                        // Claude can't know who the user is; keep "friends" when we know the user isn't in it.
                        let withMe = scores[id]?.withMe
                        if withMe == false && v.category.isPeople { scores[id]?.category = .friends }
                        else if withMe == true && v.category == .group { scores[id]?.category = .group }
                        else { scores[id]?.category = v.category }
                    }
                    if let title = out.title, !title.isEmpty { storyTitle = title }
                    stats.judgeUsed = !verdicts.isEmpty
                    stats.judgeImagesSent = out.imagesSent
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    Self.log.error("Judge failed: \(String(describing: error), privacy: .public)")
                    stats.judgeNote = Self.judgeNote(error)
                }
            } else {
                stats.judgeNote = String(localized: "AI Judge is on but has no API key; used on-device picks.")
            }
        }
        try Task.checkCancellation()

        // Stage 7 – diversity-aware selection.
        report(.selection, 0, 0)
        let sceneSizes = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, Float($0.photoIDs.count)) })
        let biggestScene = sceneSizes.values.max() ?? 1
        let candidates: [Selection.Candidate] = clusters.compactMap { c in
            guard let s = scores[c.winnerID], let p = photoByID[c.winnerID] else { return nil }
            let q = s.quality
            let r = verdicts[c.winnerID].map { (1 - Tuning.judgeWeight) * q + Tuning.judgeWeight * $0.score } ?? q
            return Selection.Candidate(photoID: c.winnerID, sceneID: c.sceneID, clusterID: c.id, relevance: r,
                                       category: s.category, featurePrint: features[c.winnerID]?.featurePrint ?? [],
                                       date: p.creationDate, withMe: s.withMe,
                                       sceneWeight: ((sceneSizes[c.sceneID] ?? 1) / biggestScene).squareRoot())
        }.sorted { $0.relevance != $1.relevance ? $0.relevance > $1.relevance : $0.photoID < $1.photoID }
        let count = min(config.count, preset.maxCount)
        timer.begin(.selection)
        let selection = Selection.select(candidates: candidates, count: count, mix: config.mix, locked: locked,
                                         prefs: config.prefs)
        timer.end()

        // Stage 8 – ordering, reasons, exclusion tags.
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.photoID, $0) })
        let items = selection.selected.compactMap { byID[$0] }.map {
            Ordering.Item(photoID: $0.photoID, relevance: $0.relevance, category: $0.category, date: $0.date,
                          sceneID: $0.sceneID, withMe: $0.withMe)
        }
        var ordered: [String]
        var roles: [String: StoryRole] = [:]
        if preset.ordering == .coverThenStory && config.prefs.story == .story {
            let story = Ordering.story(items, lastSceneID: scenes.last?.id)
            ordered = story.order
            if let o = story.opener { roles[o] = .opener }
            if let c = story.closer { roles[c] = .closer }
        } else {
            ordered = Ordering.order(items, rule: preset.ordering == .coverThenStory ? .bestFirst : preset.ordering)
        }
        let sceneLabel = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, $0.label) })
        let pickedCategories = ordered.compactMap { scores[$0]?.category }
        var picks: [Pick] = []
        for (i, id) in ordered.enumerated() {
            guard let s = scores[id], let c = byID[id], let cluster = clusters.first(where: { $0.id == c.clusterID }) else { continue }
            let reason = Explanations.reason(.init(score: s, clusterSize: cluster.size, sceneLabel: sceneLabel[c.sceneID] ?? "",
                                                   categoryCountInSet: pickedCategories.filter { $0 == s.category }.count,
                                                   judge: verdicts[id]))
            picks.append(Pick(photoID: id, position: i + 1, reason: reason, category: s.category, clusterSize: cluster.size,
                              score: s, judge: verdicts[id], isLocked: locked.contains(id), role: roles[id]))
        }
        let position = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1, $0 + 1) })
        for cluster in clusters {
            for member in cluster.memberIDs where member != cluster.winnerID && excluded[member] == nil {
                excluded[member] = .nearDuplicate(ofPick: position[cluster.winnerID])
            }
        }
        excluded.merge(Selection.exclusionTags(candidates: candidates, ordered: ordered, count: count)) { a, _ in a }
        for id in selection.selected where excluded[id] != nil { excluded[id] = nil }

        stats.stageDurations = timer.durations
        stats.excludedCount = excluded.count
        stats.sceneCount = scenes.count
        stats.clusterCount = clusters.count
        stats.candidateCount = candidates.count
        stats.shortfall = selection.shortfall
        stats.relaxations = selection.relaxed.map(\.relaxationNote)
        report(.done, 1, 1)

        let result = RunResult(id: UUID(), createdAt: Date(), config: config, picks: picks,
                               candidates: candidates.map(\.photoID), scenes: scenes, clusters: clusters,
                               excluded: excluded, scores: scores, stats: stats, setRatio: preset.primaryRatio,
                               title: storyTitle ?? Explanations.storyTitle(range: Self.span(of: scenes) ?? config.range,
                                                                            sceneCount: scenes.count))
        await store.saveRun(result)
        Self.log.info("Run: \(stats.photoCount) photos, \(scenes.count) scenes, \(clusters.count) clusters, \(picks.count) picks")
        return result
    }

    // MARK: Stage 2

    private func analyse(_ photos: [PhotoRecord], options: Options, excluded: inout [String: ExclusionTag],
                         progress: (Int, Int, Int) -> Void) async throws -> [String: FeatureRecord] {
        let ids = photos.map(\.id)
        var features = await store.features(for: ids)
        let analysedAt = await store.analysedDates(for: ids)
        let revision = extractor.featurePrintRevision
        let todo = photos.filter { store.isStale(features[$0.id], analysedAt: analysedAt[$0.id], photo: $0, revision: revision) }
        for p in todo { features[p.id] = nil }
        let total = photos.count
        var done = total - todo.count
        var inCloud = 0
        progress(done, total, inCloud)
        guard !todo.isEmpty else { return features }

        let source = source, extractor = extractor, allow = options.allowNetwork
        var pendingSave: [FeatureRecord] = []
        var modDates: [String: Date] = [:]
        for p in todo { if let m = p.modificationDate { modDates[p.id] = m } }

        try await withThrowingTaskGroup(of: (String, Result<FeatureRecord, any Error>).self) { group in
            var pending = todo[...]
            func addNext() {
                guard let record = pending.popFirst() else { return }
                group.addTask {
                    do { return (record.id, .success(try await extractor.extract(record, from: source, allowNetwork: allow))) }
                    catch { return (record.id, .failure(error)) }
                }
            }
            for _ in 0..<Tuning.maxConcurrentAnalyses { addNext() }
            while let (id, result) = try await group.next() {
                switch result {
                case .success(let f):
                    features[id] = f
                    pendingSave.append(f)
                case .failure(let error):
                    if error is CancellationError { throw error }
                    if case PhotoSourceError.inCloud = error {
                        excluded[id] = .inCloud
                        inCloud += 1
                    } else {
                        excluded[id] = .analysisFailed
                        Self.log.error("Analysis failed for a photo: \(String(describing: error), privacy: .public)")
                    }
                }
                done += 1
                progress(done, total, inCloud)
                if pendingSave.count >= 25 {
                    await store.save(pendingSave, modificationDates: modDates)
                    pendingSave.removeAll()
                }
                if Task.isCancelled { throw CancellationError() }
                addNext()
            }
        }
        await store.save(pendingSave, modificationDates: modDates)
        return features
    }

    // MARK: Helpers

    /// When the photos were actually taken (first to last), for the story title.
    static func span(of scenes: [Scene]) -> DateInterval? {
        guard let start = scenes.map(\.start).min(), let end = scenes.map(\.end).max(), end >= start else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func promote(_ id: String, in cluster: inout Cluster) {
        let old = cluster.winnerID
        cluster.winnerID = id
        cluster.runnerUpIDs.removeAll { $0 == id }
        cluster.runnerUpIDs.insert(old, at: 0)
        cluster.runnerUpIDs = Array(cluster.runnerUpIDs.prefix(3))
    }

    static func judgeNote(_ error: any Error) -> String {
        switch error {
        case JudgeError.missingKey: String(localized: "AI Judge needs an API key in Settings; used on-device picks.")
        case JudgeError.offline: String(localized: "Offline, so AI Judge was skipped; used on-device picks.")
        case JudgeError.http(let status, let message): String(localized: "AI Judge error \(status): \(message). Used on-device picks.")
        default: String(localized: "AI Judge failed; used on-device picks.")
        }
    }
}

/// Wall-clock duration per stage plus an os_signpost interval, so Instruments shows where time goes.
nonisolated struct StageTimer {
    private static let signposter = OSSignposter(subsystem: "app.eymra", category: .pointsOfInterest)
    private(set) var durations: [String: TimeInterval] = [:]
    private var current: (stage: PipelineProgress.Stage, start: ContinuousClock.Instant, state: OSSignpostIntervalState)?

    mutating func begin(_ stage: PipelineProgress.Stage) {
        end()
        let state = Self.signposter.beginInterval("stage", id: Self.signposter.makeSignpostID(), "\(stage.rawValue)")
        current = (stage, ContinuousClock.now, state)
    }

    mutating func end() {
        guard let c = current else { return }
        Self.signposter.endInterval("stage", c.state)
        let d = c.start.duration(to: .now)
        durations[c.stage.rawValue] = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        current = nil
    }
}
