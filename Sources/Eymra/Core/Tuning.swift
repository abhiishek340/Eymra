import Foundation

/// Every threshold and weight the pipeline uses. Change values here, record the reason in DECISIONS.md.
nonisolated enum Tuning {
    // MARK: Stage 2 – feature extraction
    /// Photos analysed at once. 3 on devices with more than 6 GB of RAM, else 2.
    static var maxConcurrentAnalyses: Int {
        ProcessInfo.processInfo.physicalMemory > 6 * 1024 * 1024 * 1024 ? 3 : 2
    }
    static let renditionLongEdge: Double = 1024
    static let sharpnessLongEdge = 512
    static let labelMinConfidence: Float = 0.1
    static let maxLabels = 10

    // MARK: Stage 1 – ingest
    static let minShortEdge = 800

    // MARK: Stage 3 – scenes
    static let sceneWindow = 10                       // d in the PhotoTOC rule
    static let sceneGapFactor = 17.0                  // log 17 offset
    static let sceneMinGap: TimeInterval = 3 * 60     // never cut under this (Rule A only)
    static let sceneMaxGap: TimeInterval = 90 * 60    // always cut over this
    static let sceneDistanceMeters = 400.0            // Rule B, range 200–800
    static let sceneMaxAccuracyMeters = 100.0

    // MARK: Stage 4 – clusters
    static let duplicateDistance: Float = 0.5
    static let clusterAnchorDistance: Float = 0.65
    static let clusterLookback = 20
    static let clusterLookbackSeconds: TimeInterval = 10 * 60
    /// needsCalibration: fallback when a feature print is missing.
    static let thumbDuplicateRMS: Float = 0.06
    static let thumbDuplicateSeconds: TimeInterval = 60

    // MARK: Stage 5 – scoring
    static let blurryPercentile: Float = 0.05
    static let blurryMaxVariance: Float = 20
    static let tooDarkFraction: Float = 0.60
    static let blownOutFraction: Float = 0.30
    static let weightsWithFaces = (t: Float(0.35), a: Float(0.30), c: Float(0.15), p: Float(0.20))
    static let weightsNoFaces = (t: Float(0.45), a: Float(0.35), c: Float(0.20))
    static let favoriteBonus: Float = 0.10
    static let categoryLabelConfidence: Float = 0.3
    static let meFaceArea: Float = 0.04
    static let meHumanArea: Float = 0.25
    static let detailSaliencyArea: Float = 0.25

    // MARK: Recognising the user (SFace signatures, cosine similarity)
    /// Faces per photo that get a signature, largest first.
    static let maxFacePrints = 6
    static let faceCropMargin: Float = 0.25
    /// Faces narrower than this (pixels, in the 1024 px rendition) are too small to recognise reliably.
    static let minFacePixels: Double = 40
    /// Same person at or above this cosine. LFW with 5-point alignment: different people's 99th percentile is 0.30,
    /// the published threshold 0.363; 0.40 trades a little recall for no false matches.
    static let meSimilarity: Float = 0.40
    /// Two shots only count as the same moment if their faces are the same people: each face needs a match in the
    /// other shot at or above this. Lower than meSimilarity, because the same person across a burst of poses can
    /// drift a little; different people sit below 0.30 (LFW 99th percentile).
    static let samePersonSimilarity: Float = 0.32
    /// During face setup, angles that don't look like the straight-on capture (below this) are dropped.
    static let enrolConsistency: Float = 0.35

    // MARK: Personal preferences
    static let meShareMostlyMe: Float = 0.6
    static let meShareFriends: Float = 0.5
    static let meShareMix: Float = 0.4
    static let meSharePlaces: Float = 0.2
    /// Bonus when the set has fewer photos of the user than they asked for.
    static let meShareBonus: Float = 0.12
    /// Penalty for photos of friends without the user, by how much the user likes group shots.
    static let friendsOnlyPenaltyRarely: Float = 0.15
    static let friendsOnlyPenaltySometimes: Float = 0.06
    static let groupLoveBonus: Float = 0.06
    static let groupRarelyPenalty: Float = 0.06

    // MARK: Story
    /// Bonus for the first pick from a place, scaled by how many photos were taken there (sqrt).
    static let coverageBonus: Float = 0.10
    /// Closer preference: a strong shot from the last place, and from late in the day (scaled by time 0–1).
    static let closerLastSceneBonus: Float = 0.05
    static let closerLateBonus: Float = 0.20

    // MARK: Stage 6 – AI Judge
    static let judgeBatchSize = 20
    static let judgeMaxImages = 120
    static let judgeConcurrentBatches = 4
    static let judgeRunnerUpsPerCluster = 2
    static let judgeCloseCallMargin: Float = 0.08
    static let judgeMaxClusterCalls = 15
    static let judgeJPEGQuality: Double = 0.75

    // MARK: Stage 7 – selection
    /// MMR trade-off: 1 = pure relevance, 0 = pure diversity.
    static let mmrLambda: Float = 0.7
    /// Two winners from different clusters closer than this share a background.
    static let sameBackgroundDistance: Float = 0.75
    /// Share of the target count one scene may take (at least 2 picks).
    static let sceneCapShare = 0.34
    static let sceneCapMinimum = 2
    /// Share of the target count one category may take (at least 2 picks).
    static let categoryCapShare = 0.4
    static let newCategoryBonus: Float = 0.08
    static let mixBonus: Float = 0.10
    /// Weight of the judge score J in R when the judge ran.
    static let judgeWeight: Float = 0.5
}
