import Foundation

/// Returns the precomputed fixture features, so pipeline tests and UI tests are deterministic on the Simulator.
nonisolated struct FakeFeatureExtractor: FeatureExtracting {
    let features: [String: FeatureRecord]
    /// Per-photo pause, so UI tests can catch the working state.
    var delay: Duration = .zero
    var featurePrintRevision: Int { 2 }

    func extract(_ record: PhotoRecord, from source: any PhotoSource, allowNetwork: Bool) async throws -> FeatureRecord {
        try Task.checkCancellation()
        if delay > .zero { try await Task.sleep(for: delay) }
        guard let f = features[record.id] else { throw PhotoSourceError.notFound }
        return f
    }
}
