import Foundation
import Testing
@testable import Eymra

struct FeatureStoreTests {
    private func store() throws -> FeatureStore {
        FeatureStore(modelContainer: try FeatureStore.makeContainer(inMemory: true))
    }

    @Test func featuresRoundTrip() async throws {
        let s = try store()
        var f = Make.feature("a", print: [0.25, -0.5, 1], faces: 2, labels: [("sky", 0.7)], thumb: [1, 2, 3])
        f.horizonDegrees = 3
        await s.save([f])
        let back = await s.features(for: ["a", "missing"])
        #expect(back.count == 1)
        #expect(back["a"] == f)
    }

    @Test func fetchesMoreThanOneChunk() async throws {
        let s = try store()
        let records = (0..<450).map { Make.feature("p\($0)", print: [Float($0)]) }
        await s.save(records)
        let back = await s.features(for: records.map(\.photoID))
        #expect(back.count == 450)
        #expect(back["p449"]?.featurePrint == [449])
    }

    @Test func stalenessRules() throws {
        let s = try store()
        let photo = Make.photo("a", at: 0)
        let fresh = Make.feature("a")
        #expect(s.isStale(nil, analysedAt: nil, photo: photo, revision: 2))
        #expect(!s.isStale(fresh, analysedAt: Date(), photo: photo, revision: 2))
        #expect(s.isStale(fresh, analysedAt: Date(), photo: photo, revision: 3))
        var old = fresh
        old.schemaVersion = FeatureSchema.version - 1
        #expect(s.isStale(old, analysedAt: Date(), photo: photo, revision: 2))
        var edited = photo
        edited.modificationDate = Date().addingTimeInterval(60)
        #expect(s.isStale(fresh, analysedAt: Date(), photo: edited, revision: 2))
    }

    @Test func hidesPersistAndClear() async throws {
        let s = try store()
        await s.setHidden("x", true)
        await s.setHidden("y", true)
        await s.setHidden("y", false)
        #expect(await s.hiddenIDs() == ["x"])
        await s.clearHidden()
        #expect(await s.hiddenIDs().isEmpty)
    }

    @Test func keepsTheNewestTwentyRuns() async throws {
        let s = try store()
        let config = RunConfig(range: DateInterval(start: Make.t0, duration: 60), platform: .x, count: 4, mix: .balanced, judgeEnabled: false)
        for i in 0..<25 {
            let run = RunResult(id: UUID(), createdAt: Make.t0.addingTimeInterval(Double(i)), config: config, picks: [],
                                candidates: ["c\(i)"], scenes: [], clusters: [], excluded: [:], scores: [:], stats: RunStats(),
                                setRatio: .square)
            await s.saveRun(run)
        }
        #expect(await s.latestRun()?.candidates == ["c24"])
        #expect(await s.latestRun(matching: config)?.candidates == ["c24"])
    }

    @Test func verdictsRoundTrip() async throws {
        let s = try store()
        await s.saveVerdicts(["a|m|1|756|1": CachedVerdictValue(score: 0.7, category: "view", reason: "Nice")])
        let back = await s.verdicts(for: ["a|m|1|756|1", "b|m|1|756|1"])
        #expect(back.count == 1)
        #expect(back["a|m|1|756|1"]?.reason == "Nice")
    }
}
