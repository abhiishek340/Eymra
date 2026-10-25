import Foundation
import Testing
@testable import Eymra

/// End to end over the bundled 40-photo fixture set with precomputed features (deterministic on the Simulator).
struct PipelineFixtureTests {
    actor Counter {
        var count = 0
        func bump() { count += 1 }
    }

    struct CountingExtractor: FeatureExtracting {
        let inner: FakeFeatureExtractor
        let counter: Counter
        var delay: Duration = .zero
        var featurePrintRevision: Int { inner.featurePrintRevision }
        func extract(_ record: PhotoRecord, from source: any PhotoSource, allowNetwork: Bool) async throws -> FeatureRecord {
            await counter.bump()
            if delay > .zero { try await Task.sleep(for: delay) }
            return try await inner.extract(record, from: source, allowNetwork: allowNetwork)
        }
    }

    struct Env {
        let fixtures: FixtureSet
        let pipeline: CurationPipeline
        let counter: Counter
        let config: RunConfig

        struct Missing: Error {}

        func id(kind: String, moment: String? = nil, nth: Int = 0) -> String? {
            fixtures.entries.filter { $0.kind == kind && (moment == nil || $0.moment == moment) }.dropFirst(nth).first?.id
        }

        func must(kind: String, moment: String? = nil, nth: Int = 0) throws -> String {
            guard let id = id(kind: kind, moment: moment, nth: nth) else { throw Missing() }
            return id
        }
    }

    private func env(judge: (any JudgeProvider)? = nil, judgeEnabled: Bool = false, count: Int = 10,
                     platform: PlatformPreset.ID = .instagramCarousel, delay: Duration = .zero) throws -> Env {
        let fixtures = try FixtureSet.load()
        let counter = Counter()
        let store = FeatureStore(modelContainer: try FeatureStore.makeContainer(inMemory: true))
        let extractor = CountingExtractor(inner: FakeFeatureExtractor(features: fixtures.features), counter: counter, delay: delay)
        let pipeline = CurationPipeline(source: FixturePhotoSource(fixtures: fixtures), extractor: extractor, store: store, judge: judge)
        let dates = fixtures.entries.map(\.creationDate)
        let range = DateInterval(start: (dates.min() ?? Date()).addingTimeInterval(-60), end: (dates.max() ?? Date()).addingTimeInterval(60))
        return Env(fixtures: fixtures, pipeline: pipeline, counter: counter,
                   config: RunConfig(range: range, platform: platform, count: count, mix: .balanced, judgeEnabled: judgeEnabled))
    }

    @Test func picksTenDistinctMomentsWithVariety() async throws {
        let e = try env()
        let r = try await e.pipeline.run(e.config)
        #expect(r.stats.photoCount == 40)
        #expect(r.stats.sceneCount == 5)
        #expect(r.picks.count == 10)
        #expect(r.picks.map(\.position) == Array(1...10))

        // One per moment: no two picks share a cluster or a fixture moment.
        let clusterOf = { (id: String) in r.cluster(containing: id)?.id }
        #expect(Set(r.picks.compactMap { clusterOf($0.photoID) }).count == 10)
        let momentOf = Dictionary(uniqueKeysWithValues: e.fixtures.entries.map { ($0.id, $0.moment) })
        #expect(Set(r.picks.compactMap { momentOf[$0.photoID] }).count == 10)

        // Variety on purpose.
        #expect(Set(r.picks.map(\.category)).count >= 4)
        #expect(r.picks.filter { $0.category == .me }.count <= Selection.categoryCap(count: 10))

        // Every pick explains itself; big clusters say "best of".
        #expect(r.picks.allSatisfy { !$0.reason.isEmpty })
        let ridge = try #require(r.cluster(containing: try e.must(kind: "me", moment: "ridgePose")))
        #expect(ridge.size == 8)
    }

    @Test func hardRejectsAreTagged() async throws {
        let e = try env()
        let r = try await e.pipeline.run(e.config)
        #expect(r.excluded[try e.must(kind: "screenshot")] == .screenshot)
        #expect(r.excluded[try e.must(kind: "receipt")] == .screenshot)
        #expect(r.excluded[try e.must(kind: "me", moment: "ridgePose", nth: 2)] == .blurry)
        #expect(r.excluded[try e.must(kind: "me", moment: "ridgePose", nth: 5)] == .eyesClosed)
        #expect(r.excluded[try e.must(kind: "me", moment: "sunsetMe", nth: 2)] == .tooDark)
        #expect(r.excluded[try e.must(kind: "view", moment: "sunsetView", nth: 1)] == .blownOut)
        // Everything that is not a pick has a reason.
        let picked = Set(r.picks.map(\.photoID))
        for entry in e.fixtures.entries where !picked.contains(entry.id) {
            #expect(r.excluded[entry.id] != nil, "\(entry.id) has no exclusion tag")
        }
    }

    @Test func bestFrameWinsThePosingSeries() async throws {
        let e = try env()
        let r = try await e.pipeline.run(e.config)
        let ridge = try #require(r.cluster(containing: try e.must(kind: "me", moment: "ridgePose")))
        #expect(ridge.winnerID == e.id(kind: "me", moment: "ridgePose", nth: 6))
    }

    @Test func sameBackgroundPosesAreNotBothPicked() async throws {
        let e = try env()
        let r = try await e.pipeline.run(e.config)
        let a = try e.must(kind: "me", moment: "lakeMeA"), b = try e.must(kind: "me", moment: "lakeMeB")
        #expect(r.cluster(containing: a)?.id != r.cluster(containing: b)?.id)
        let picked = Set(r.picks.map(\.photoID))
        #expect(!(picked.contains(a) && picked.contains(b)))
    }

    @Test func secondRunUsesTheCache() async throws {
        let e = try env()
        _ = try await e.pipeline.run(e.config)
        let first = await e.counter.count
        let r2 = try await e.pipeline.run(e.config)
        #expect(first == 39)           // the screenshot is filtered before analysis
        #expect(await e.counter.count == first)
        #expect(r2.picks.count == 10)
    }

    @Test func platformCountsAndOrdering() async throws {
        let x = try env(count: 4, platform: .x)
        let rx = try await x.pipeline.run(x.config)
        #expect(rx.picks.count == 4)
        #expect(rx.setRatio == .landscape16x9)
        let reels = try env(count: 8, platform: .reels)
        let rr = try await reels.pipeline.run(reels.config)
        let dates = rr.picks.compactMap { p in reels.fixtures.entries.first { $0.id == p.photoID }?.creationDate }
        #expect(dates == dates.sorted())
    }

    @Test func locksSurviveAReRun() async throws {
        let e = try env()
        let r = try await e.pipeline.run(e.config)
        // Lock a runner-up of the posing series: it must come back as a pick.
        let ridge = try #require(r.cluster(containing: try e.must(kind: "me", moment: "ridgePose")))
        let runner = try #require(ridge.runnerUpIDs.first)
        let r2 = try await e.pipeline.run(e.config, options: .init(locked: [runner]))
        #expect(r2.picks.contains { $0.photoID == runner && $0.isLocked })
    }

    @Test func judgeIsUsedWhenItWorks() async throws {
        let e = try env(judge: StubJudge(), judgeEnabled: true)
        let r = try await e.pipeline.run(e.config)
        #expect(r.stats.judgeUsed)
        #expect(r.stats.judgeImagesSent > 0)
        #expect(r.picks.count == 10)
        #expect(r.picks.allSatisfy { $0.judge != nil })
    }

    @Test func judgeFailureFallsBackToOnDevice() async throws {
        let e = try env(judge: StubJudge(failure: .http(status: 401, message: "invalid x-api-key")), judgeEnabled: true)
        let r = try await e.pipeline.run(e.config)
        #expect(!r.stats.judgeUsed)
        #expect(r.stats.judgeNote?.contains("key didn't work") == true)
        #expect(r.picks.count == 10)
    }

    @Test func cancellationStopsTheRun() async throws {
        let e = try env(delay: .milliseconds(50))
        let pipeline = e.pipeline, config = e.config
        let task = Task { try await pipeline.run(config) }
        try await Task.sleep(for: .milliseconds(120))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func recognisesTheUserAndTheirFriend() async throws {
        let e = try env()
        let r = try await e.pipeline.run(e.config, options: .init(me: e.fixtures.meReference))
        #expect(r.stats.recognisedMe)
        let friend = try e.must(kind: "meWithView", moment: "townFriend")
        #expect(r.scores[friend]?.withMe == false)
        #expect(r.scores[friend]?.category == .friends)
        let selfie = try e.must(kind: "me", moment: "cafeSelfie")
        #expect(r.scores[selfie]?.withMe == true)
        let group = try e.must(kind: "group", moment: "lakeGroup")
        #expect(r.scores[group]?.withMe == true)
        #expect(r.picks.count == 10)
    }

    @Test func storyHasAnOpenerAndACloser() async throws {
        let e = try env()
        let r = try await e.pipeline.run(e.config, options: .init(me: e.fixtures.meReference))
        #expect(r.picks.first?.role == .opener)
        #expect(r.picks.last?.role == .closer)
        #expect(r.picks.first.map { r.scores[$0.photoID]?.withMe == true } == true)
        #expect(!r.title.isEmpty)
    }

    @Test func mostlyMeShowsMoreOfTheUser() async throws {
        let e = try env()
        var places = e.config
        places.prefs = UserPrefs(style: .places, groups: .rarely, story: .story)
        var mostlyMe = e.config
        mostlyMe.prefs = UserPrefs(style: .mostlyMe, groups: .sometimes, story: .story)
        let rp = try await e.pipeline.run(places, options: .init(me: e.fixtures.meReference))
        let rm = try await e.pipeline.run(mostlyMe, options: .init(me: e.fixtures.meReference))
        let count = { (r: RunResult) in r.picks.filter { r.scores[$0.photoID]?.withMe == true }.count }
        #expect(count(rm) >= count(rp))
        // Friends-only photos are left out for someone who mostly posts themselves.
        #expect(!rm.picks.contains { $0.category == .friends })
    }

    @Test func faceSetUpButNeverFoundTreatsEveryoneTheSame() async throws {
        let e = try env()
        let stranger = MeReference(prints: [Make.vector(31, dim: 32)])
        let r = try await e.pipeline.run(e.config, options: .init(me: stranger))
        #expect(!r.stats.recognisedMe)
        #expect(r.stats.meNote != nil)
        #expect(!r.picks.contains { $0.category == .friends })
    }

    @Test func judgeTitleIsUsed() async throws {
        let e = try env(judge: StubJudge(), judgeEnabled: true)
        let r = try await e.pipeline.run(e.config)
        #expect(r.title == "A golden day out")
    }

    @Test func progressIsReported() async throws {
        let e = try env()
        let (stream, continuation) = AsyncStream<PipelineProgress>.makeStream()
        _ = try await e.pipeline.run(e.config, progress: continuation)
        continuation.finish()
        var stages: [PipelineProgress.Stage] = []
        for await p in stream where stages.last != p.stage { stages.append(p.stage) }
        #expect(stages.first == .ingest)
        #expect(stages.last == .done)
        #expect(stages.contains(.analyse))
    }
}
