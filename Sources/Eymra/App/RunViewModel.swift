import Foundation
import Observation
import UIKit
import os

nonisolated enum RangePreset: String, CaseIterable, Identifiable, Sendable {
    case today, yesterday, last3, last7, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .last3: String(localized: "Last 3 days")
        case .last7: String(localized: "Last 7 days")
        case .custom: String(localized: "Custom")
        }
    }

    /// Compact label for the chips under the day chart.
    var short: String {
        switch self {
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .last3: String(localized: "3 days")
        case .last7: String(localized: "Week")
        case .custom: String(localized: "Custom")
        }
    }
}

@MainActor @Observable
final class RunViewModel {
    enum Phase: Equatable {
        case idle
        case running(PipelineProgress)
        case finished
        case failed(String)
    }

    private static let log = Logger(subsystem: "app.eymra", category: "ui")
    let app: AppModel

    // Inputs.
    var preset: RangePreset { didSet { refreshCount() } }
    var customStart: Date { didSet { if preset == .custom { refreshCount() } } }
    var customEnd: Date { didSet { if preset == .custom { refreshCount() } } }
    var platform: PlatformPreset.ID = .instagramCarousel {
        didSet { count = PlatformPreset.preset(platform).defaultCount }
    }
    var count = PlatformPreset.preset(.instagramCarousel).defaultCount
    var mix: Mix = .balanced

    // Outputs.
    private(set) var photoCount: Int?
    /// A few photos from the chosen time, for the hero stack on Create.
    private(set) var previewIDs: [String] = []
    /// Photos taken on each of the last 7 days (oldest first), for the day chart.
    private(set) var days: [DayCount] = []

    struct DayCount: Identifiable, Equatable {
        var start: Date
        var count: Int
        var id: Date { start }
    }
    private(set) var phase: Phase = .idle
    var result: RunResult?
    var showResults = false
    /// Photos to show while working: a spread of the range, then each photo as it's looked at.
    private(set) var pool: [String] = []
    /// The final picks, once known, so the working view can gather them before the story appears.
    private(set) var finalPicks: [String] = []

    /// Which of the three Create states to show.
    enum Screen: Equatable { case setup, working, story }
    var screen: Screen {
        if isRunning { return .working }
        return showResults && result != nil ? .story : .setup
    }
    var toast: String?
    private var task: Task<Void, Never>?
    private var countTask: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        mix = app.account.prefs.defaultMix
        let now = Date()
        preset = app.isUITesting ? .last3 : .today
        customEnd = now
        // Default custom start: last Sunday 8 PM, the user's own example.
        let cal = Calendar.current
        var start = cal.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
        while cal.component(.weekday, from: start) != 1 || start > now {
            start = cal.date(byAdding: .day, value: -1, to: start) ?? start
        }
        customStart = start
    }

    var platformPreset: PlatformPreset { PlatformPreset.preset(platform) }

    var range: DateInterval {
        let now = Date(), cal = Calendar.current
        let today = cal.startOfDay(for: now)
        switch preset {
        case .today: return DateInterval(start: today, end: now)
        case .yesterday:
            let start = cal.date(byAdding: .day, value: -1, to: today) ?? today
            return DateInterval(start: start, end: today.addingTimeInterval(-0.001))
        case .last3: return DateInterval(start: now.addingTimeInterval(-3 * 86_400), end: now)
        case .last7: return DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
        case .custom: return DateInterval(start: min(customStart, customEnd), end: max(customStart, customEnd))
        }
    }

    var isRunning: Bool { if case .running = phase { true } else { false } }

    func refreshCount() {
        guard app.access.isUsable else { photoCount = nil; return }
        countTask?.cancel()
        let source = app.source, range = range
        countTask = Task {
            let n = await source.count(in: range)
            guard !Task.isCancelled else { return }
            photoCount = n
            // A spread of up to 5 photos for the hero.
            let records = (try? await source.records(in: range)) ?? []
            guard !Task.isCancelled else { return }
            let step = max(1, records.count / 5)
            previewIDs = Array(stride(from: 0, to: records.count, by: step).map { records[$0].id }.suffix(5))
        }
        if days.isEmpty { refreshDays() }
    }

    func refreshDays() {
        let source = app.source, cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        Task {
            var out: [DayCount] = []
            for back in (0..<7).reversed() {
                guard let start = cal.date(byAdding: .day, value: -back, to: today),
                      let end = cal.date(byAdding: .day, value: 1, to: start) else { continue }
                out.append(DayCount(start: start, count: await source.count(in: DateInterval(start: start, end: min(end, Date())))))
            }
            days = out
        }
    }

    /// Picks one day from the chart.
    func selectDay(_ day: DayCount) {
        let cal = Calendar.current
        if cal.isDateInToday(day.start) { preset = .today; return }
        if cal.isDateInYesterday(day.start) { preset = .yesterday; return }
        customStart = day.start
        customEnd = cal.date(byAdding: .day, value: 1, to: day.start)?.addingTimeInterval(-1) ?? day.start
        preset = .custom
    }

    /// Whether a day falls inside the chosen time.
    func isSelected(_ day: DayCount) -> Bool {
        let r = range
        return day.start < r.end && day.start.addingTimeInterval(86_400) > r.start
    }

    // MARK: Running

    func run(locked: [String] = []) {
        task?.cancel()
        let config = RunConfig(range: range, platform: platform, count: count, mix: mix,
                               judgeEnabled: app.settings.judgeEnabled, prefs: app.account.prefs)
        let options = CurationPipeline.Options(allowNetwork: app.settings.allowNetworkNow,
                                               judgeLongEdge: app.settings.judgeLongEdge, locked: locked,
                                               me: app.account.meReference)
        let pipeline = app.makePipeline()
        pool = []
        finalPicks = []
        phase = .running(PipelineProgress(stage: .ingest, completed: 0, total: 0))
        let (stream, continuation) = AsyncStream<PipelineProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        task = Task {
            let listener = Task { @MainActor in
                for await p in stream where self.isRunning {
                    self.absorb(p)
                    self.phase = .running(p)
                }
            }
            defer { listener.cancel() }
            do {
                let result = try await pipeline.run(config, options: options, progress: continuation)
                continuation.finish()
                guard !Task.isCancelled else { return }
                // Let the picks gather on screen for a moment before the story blooms in.
                self.finalPicks = result.picks.map(\.photoID)
                self.app.settings.deeperIssue = result.config.judgeEnabled ? result.stats.judgeNote : nil
                try? await Task.sleep(for: .milliseconds(1400))
                guard !Task.isCancelled else { return }
                self.result = result
                self.showResults = true
                self.phase = .finished
            } catch is CancellationError {
                continuation.finish()
                self.phase = .idle
            } catch {
                continuation.finish()
                Self.log.error("Run failed: \(String(describing: error), privacy: .public)")
                self.phase = .failed(String(localized: "Something went wrong: \(error.localizedDescription)"))
            }
        }
    }

    /// Opens a saved run from the Stories tab.
    func open(_ run: RunResult) {
        result = run
        showResults = true
    }

    private func absorb(_ p: PipelineProgress) {
        if p.stage == .ingest, !p.samples.isEmpty { pool = p.samples }
        if let id = p.photoID, !pool.contains(id) {
            pool.append(id)
            if pool.count > 28 { pool.removeFirst(pool.count - 28) }
        }
        if p.stage == .selection, !p.samples.isEmpty { finalPicks = p.samples }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    /// Re-runs the same configuration keeping locked picks.
    func rerun() {
        run(locked: result?.picks.filter(\.isLocked).map(\.photoID) ?? [])
    }

    // MARK: Editing the set

    func toggleLock(_ photoID: String) {
        guard var r = result, let i = r.picks.firstIndex(where: { $0.photoID == photoID }) else { return }
        r.picks[i].isLocked.toggle()
        result = r
    }

    /// Replaces the pick at `photoID` with `replacement` (a runner-up or any excluded photo).
    func swap(_ photoID: String, with replacement: String) {
        guard var r = result, let i = r.picks.firstIndex(where: { $0.photoID == photoID }),
              let score = r.scores[replacement] else { return }
        let old = r.picks[i]
        let cluster = r.cluster(containing: replacement)
        r.picks[i] = Pick(photoID: replacement, position: old.position, reason: String(localized: "Your pick"),
                          category: score.category, clusterSize: cluster?.size ?? 1, score: score, judge: nil, isLocked: true)
        r.excluded[replacement] = nil
        r.excluded[photoID] = .belowCut(rank: r.candidates.firstIndex(of: photoID).map { $0 + 1 } ?? 0)
        result = r
    }

    /// Swaps an excluded photo into the set: replaces the pick its tag points at, else the last unlocked pick.
    func swapIn(_ photoID: String) {
        guard let r = result else { return }
        var target: String?
        switch r.excluded[photoID] {
        case .nearDuplicate(let k?), .sameBackground(let k), .sceneCap(let k):
            target = r.picks.first { $0.position == k }?.photoID
        default: break
        }
        if target == nil { target = r.picks.last { !$0.isLocked }?.photoID }
        if let target { swap(target, with: photoID) }
    }

    /// Faces in the candidates that might be you, best first (the ones worth asking about).
    var unsureFaces: [UnsureFace] {
        guard let r = result else { return [] }
        let ranked = r.picks.map(\.photoID) + r.candidates
        var seen = Set<String>()
        return ranked.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return r.scores[id]?.unsureFace
        }
        .prefix(12)
        .map { $0 }
    }

    /// Include confident picks so a false positive can be corrected, not just borderline matches.
    var reviewFaces: [UnsureFace] {
        guard let r = result else { return [] }
        let ranked = unsureFaces + r.picks.compactMap { $0.score.matchedFace }
        var seen = Set<String>()
        return ranked.filter { seen.insert($0.photoID).inserted }
    }

    /// Saves "Is this you?" answers and picks again with them.
    func answerFaces(me: [UnsureFace], notMe: [UnsureFace]) {
        guard !me.isEmpty || !notMe.isEmpty else { return }
        app.account.answer(confirmed: me.map(\.print), notMe: notMe.map(\.print))
        toast = String(localized: "Got it. Eymra will remember.")
        rerun()
    }

    /// Hides a photo for good and re-runs, keeping locks.
    func hide(_ photoID: String) {
        Task {
            await app.store.setHidden(photoID, true)
            if var r = result {
                r.picks.removeAll { $0.photoID == photoID }
                result = r
            }
            rerun()
        }
    }

    // MARK: Export

    func saveAlbum() async {
        guard let r = result else { return }
        do {
            let title = AlbumExporter.albumTitle(range: r.config.range, platform: PlatformPreset.preset(r.config.platform))
            _ = try await AlbumExporter.save(photoIDs: r.picks.map(\.photoID), title: title)
            toast = String(localized: "Saved to your Photos in “\(title)”")
        } catch {
            toast = String(localized: "Could not save the album")
        }
    }

    func shareFiles() async -> [URL] {
        guard let r = result else { return [] }
        do {
            return try await ShareExporter.files(for: r.picks.map(\.photoID), source: app.source)
        } catch {
            toast = String(localized: "Could not prepare photos to share")
            return []
        }
    }

    func copyForStories(_ photoID: String) async {
        guard let r = result else { return }
        let saliency = r.scores[photoID] == nil ? nil : await app.store.features(for: [photoID])[photoID]?.saliencyBox
        do {
            let data = try await StoriesExporter.croppedJPEG(photoID: photoID, ratio: .vertical9x16, saliency: saliency, source: app.source)
            StoriesExporter.copyToPasteboard(data)
            toast = String(localized: "Copied! Paste it into your Story")
        } catch {
            toast = String(localized: "Could not copy this photo")
        }
    }

    func openPlatformApp() {
        guard let scheme = PlatformPreset.preset(result?.config.platform ?? platform).appURL, let url = URL(string: scheme) else { return }
        UIApplication.shared.open(url) { [weak self] opened in
            if !opened { Task { @MainActor in self?.toast = String(localized: "That app isn't installed") } }
        }
    }
}
