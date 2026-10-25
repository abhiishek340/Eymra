import Foundation

/// Returns the precomputed fixture features, so pipeline tests and UI tests are deterministic on the Simulator.
nonisolated struct FakeFeatureExtractor: FeatureExtracting {
    let features: [String: FeatureRecord]
    var featurePrintRevision: Int { 2 }

    func extract(_ record: PhotoRecord, from source: any PhotoSource, allowNetwork: Bool) async throws -> FeatureRecord {
        try Task.checkCancellation()
        guard let f = features[record.id] else { throw PhotoSourceError.notFound }
        return f
    }
}
