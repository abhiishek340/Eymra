import Foundation

nonisolated struct PipelineProgress: Sendable, Equatable {
    enum Stage: String, Sendable, CaseIterable {
        case ingest, analyse, scenes, clusters, scoring, judge, selection, done

        var title: String {
            switch self {
            case .ingest: String(localized: "Finding photos")
            case .analyse: String(localized: "Analysing")
            case .scenes: String(localized: "Grouping into moments")
            case .clusters: String(localized: "Finding near-duplicates")
            case .scoring: String(localized: "Scoring")
            case .judge: String(localized: "AI Judge")
            case .selection: String(localized: "Choosing the set")
            case .done: String(localized: "Done")
            }
        }
    }

    var stage: Stage
    var completed: Int
    var total: Int
    /// Photos skipped because they are in iCloud and downloads are off.
    var inCloud = 0
    /// The photo just looked at (for the visual progress).
    var photoID: String?
    /// A spread of photo IDs from the range, sent once when ingest finishes, and the picks when selection finishes.
    var samples: [String] = []

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }

    var caption: String {
        total > 0 ? String(localized: "\(stage.title) \(completed) of \(total)") : stage.title
    }
}
