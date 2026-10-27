import Foundation

// MARK: - Small shared types

/// Normalised rectangle, 0–1 on both axes, origin at the upper-left of the image.
nonisolated struct NormRect: Codable, Sendable, Hashable {
    var x: Float
    var y: Float
    var width: Float
    var height: Float

    var area: Float { max(0, width) * max(0, height) }
    var midX: Float { x + width / 2 }
    var midY: Float { y + height / 2 }

    func union(_ other: NormRect) -> NormRect {
        let minX = min(x, other.x), minY = min(y, other.y)
        let maxX = max(x + width, other.x + other.width), maxY = max(y + height, other.y + other.height)
        return NormRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func intersectionArea(_ other: NormRect) -> Float {
        let w = min(x + width, other.x + other.width) - max(x, other.x)
        let h = min(y + height, other.y + other.height) - max(y, other.y)
        return max(0, w) * max(0, h)
    }
}

nonisolated struct GeoPoint: Codable, Sendable, Hashable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
}

nonisolated struct LabelScore: Codable, Sendable, Hashable {
    var identifier: String
    var confidence: Float
}

nonisolated enum AspectRatio: String, Codable, Sendable, Hashable, CaseIterable {
    case square, portrait4x5, portrait3x4, vertical9x16, landscape16x9, landscape191x1

    /// Width divided by height.
    var value: Double {
        switch self {
        case .square: 1
        case .portrait4x5: 4.0 / 5.0
        case .portrait3x4: 3.0 / 4.0
        case .vertical9x16: 9.0 / 16.0
        case .landscape16x9: 16.0 / 9.0
        case .landscape191x1: 1.91
        }
    }

    var label: String {
        switch self {
        case .square: "1:1"
        case .portrait4x5: "4:5"
        case .portrait3x4: "3:4"
        case .vertical9x16: "9:16"
        case .landscape16x9: "16:9"
        case .landscape191x1: "1.91:1"
        }
    }
}

nonisolated enum Mix: String, Codable, Sendable, Hashable, CaseIterable {
    case moreOfMe, balanced, moreScenery
}

nonisolated enum Category: String, Codable, Sendable, Hashable, CaseIterable {
    case me
    case meWithView = "me_with_view"
    case group
    /// People, but not the user (only known once the user's face is set up).
    case friends
    /// People, and the user's face is set up, but Eymra isn't sure whether one of them is the user.
    case someone
    case view, food, detail, other

    var isPeople: Bool { self == .me || self == .meWithView || self == .group || self == .friends || self == .someone }
    /// Shots the user is in (as far as categories alone can tell).
    var isMe: Bool { self == .me || self == .meWithView }
}

// MARK: - The user

/// What the user told us in onboarding.
nonisolated enum PostingStyle: String, Codable, Sendable, Hashable, CaseIterable {
    case mostlyMe, meAndFriends, mix, places
}

nonisolated enum GroupTaste: String, Codable, Sendable, Hashable, CaseIterable {
    case love, sometimes, rarely
}

nonisolated enum StoryStyle: String, Codable, Sendable, Hashable, CaseIterable {
    case story, bestFirst
}

nonisolated struct UserPrefs: Codable, Sendable, Hashable {
    var style: PostingStyle = .mix
    var groups: GroupTaste = .sometimes
    var story: StoryStyle = .story

    /// The per-run Mix control starts from this.
    var defaultMix: Mix {
        switch style {
        case .mostlyMe: .moreOfMe
        case .places: .moreScenery
        case .meAndFriends, .mix: .balanced
        }
    }

    /// Share of the set that should show the user, when we can recognise them.
    var meShareTarget: Float {
        switch style {
        case .mostlyMe: Tuning.meShareMostlyMe
        case .meAndFriends: Tuning.meShareFriends
        case .mix: Tuning.meShareMix
        case .places: Tuning.meSharePlaces
        }
    }
}

/// Face prints of the user from the face scan or chosen photos. Stays on the phone.
nonisolated struct MeReference: Codable, Sendable, Hashable {
    var prints: [[Float]]
    /// How the prints were made; older ones are re-made from the saved face crops.
    var version: Int? = nil
    /// Faces you said were you ("This is me"), kept apart from the scan so a rescan can keep them.
    var confirmed: [[Float]] = []
    /// Faces you said were not you ("Not me").
    var notMe: [[Float]] = []

    /// Everything that counts as you: the scan plus what you confirmed.
    var allPrints: [[Float]] { prints + confirmed }

    init(prints: [[Float]], version: Int? = nil, confirmed: [[Float]] = [], notMe: [[Float]] = []) {
        self.prints = prints
        self.version = version
        self.confirmed = confirmed
        self.notMe = notMe
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prints = try c.decode([[Float]].self, forKey: .prints)
        version = try c.decodeIfPresent(Int.self, forKey: .version)
        confirmed = try c.decodeIfPresent([[Float]].self, forKey: .confirmed) ?? []
        notMe = try c.decodeIfPresent([[Float]].self, forKey: .notMe) ?? []
    }

    /// 2: zoomed, re-detected face crops with the mirror trick.
    static let currentVersion = 2
}

nonisolated enum ExclusionTag: Codable, Sendable, Hashable {
    case screenshot
    case animated
    case tooSmall
    case blurry
    case tooDark
    case blownOut
    case eyesClosed
    case inCloud
    case analysisFailed
    case nearDuplicate(ofPick: Int?)
    case sameBackground(asPick: Int)
    case sceneCap(pick: Int)
    case belowCut(rank: Int)
    case hidden
    case categoryQuota

    /// True for tags decided before selection (the photo never competed for a slot).
    var isHardReject: Bool {
        switch self {
        case .nearDuplicate, .sameBackground, .sceneCap, .belowCut, .categoryQuota: false
        default: true
        }
    }
}

// MARK: - Per-photo inputs

nonisolated struct PhotoRecord: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var creationDate: Date
    var modificationDate: Date?
    var location: GeoPoint?
    var isFavorite: Bool
    var pixelWidth: Int
    var pixelHeight: Int
    var isScreenshot: Bool
    var isAnimated: Bool = false
    var burstIdentifier: String?

    var shortEdge: Int { min(pixelWidth, pixelHeight) }
    var aspect: Double { pixelHeight > 0 ? Double(pixelWidth) / Double(pixelHeight) : 1 }
}

nonisolated struct FaceFeature: Codable, Sendable, Hashable {
    var box: NormRect
    var captureQuality: Float?
    var eyesClosed: Bool
    var smiling: Bool
    /// Face signature (128-d unit vector from the face model), used to recognise the user. Empty when unreadable.
    var print: [Float] = []

    init(box: NormRect, captureQuality: Float?, eyesClosed: Bool, smiling: Bool, print: [Float] = []) {
        self.box = box
        self.captureQuality = captureQuality
        self.eyesClosed = eyesClosed
        self.smiling = smiling
        self.print = print
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        box = try c.decode(NormRect.self, forKey: .box)
        captureQuality = try c.decodeIfPresent(Float.self, forKey: .captureQuality)
        eyesClosed = try c.decode(Bool.self, forKey: .eyesClosed)
        smiling = try c.decode(Bool.self, forKey: .smiling)
        print = try c.decodeIfPresent([Float].self, forKey: .print) ?? []
    }
}

nonisolated enum FeatureSchema {
    /// Bump whenever stage 2 changes what it stores.
    static let version = 4
}

nonisolated struct FeatureRecord: Codable, Sendable, Hashable {
    var photoID: String
    var schemaVersion: Int
    var featurePrint: [Float]
    var featurePrintRevision: Int
    var aestheticScore: Float?
    var isUtility: Bool
    var faces: [FaceFeature]
    var humanBoxes: [NormRect]
    var saliencyBox: NormRect?
    var labels: [LabelScore]
    var horizonDegrees: Float?
    var sharpness: Float
    var darkFraction: Float
    var brightFraction: Float
    var meanLuma: Float
    var thumb32: [UInt8]
}

// MARK: - Pipeline outputs

nonisolated struct Scene: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var photoIDs: [String]
    var start: Date
    var end: Date
    var centroid: GeoPoint?
    var placeName: String?
    var meanPrint: [Float]

    /// Short label for the UI: the hour range, e.g. "10:12–10:40".
    var label: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let a = f.string(from: start), b = f.string(from: end)
        return a == b ? a : "\(a)–\(b)"
    }
}

nonisolated struct Cluster: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var sceneID: String
    var memberIDs: [String]
    var winnerID: String
    var runnerUpIDs: [String]

    var size: Int { memberIDs.count }
}

nonisolated struct PhotoScore: Codable, Sendable, Hashable {
    var photoID: String
    var technical: Float
    var aesthetic: Float
    var composition: Float
    var people: Float?
    var quality: Float
    var cropFit: [AspectRatio: Float]
    var category: Category
    var exclusion: ExclusionTag?
    /// Whether the user is in the photo: nil when we can't tell (no face set up, or no face prints).
    var withMe: Bool? = nil
    /// A face that might be you but isn't sure enough; the app asks.
    var unsureFace: UnsureFace? = nil
}

/// A face Eymra isn't sure is you, kept so the app can ask "Is this you?".
nonisolated struct UnsureFace: Codable, Sendable, Hashable {
    var photoID: String
    var box: NormRect
    var print: [Float]
    var similarity: Float
}

nonisolated struct JudgeVerdict: Codable, Sendable, Hashable {
    var photoID: String
    var score: Float
    var category: Category
    var reason: String
    var model: String
    var promptVersion: Int
}

nonisolated struct RunConfig: Codable, Sendable, Hashable {
    var range: DateInterval
    var platform: PlatformPreset.ID
    var count: Int
    var mix: Mix
    var judgeEnabled: Bool
    var prefs = UserPrefs()
}

/// Where a pick sits in the story.
nonisolated enum StoryRole: String, Codable, Sendable, Hashable {
    case opener, closer
}

nonisolated struct Pick: Codable, Sendable, Hashable, Identifiable {
    var photoID: String
    var position: Int
    var reason: String
    var category: Category
    var clusterSize: Int
    var score: PhotoScore
    var judge: JudgeVerdict?
    var isLocked: Bool
    var role: StoryRole? = nil

    var id: String { photoID }
}

nonisolated struct RunStats: Codable, Sendable, Hashable {
    var photoCount = 0
    var excludedCount = 0
    var sceneCount = 0
    var clusterCount = 0
    var candidateCount = 0
    var shortfall = 0
    var relaxations: [String] = []
    var judgeUsed = false
    var judgeImagesSent = 0
    var judgeNote: String?
    /// The user's face is set up and was found in at least one photo.
    var recognisedMe = false
    var meNote: String?
    var stageDurations: [String: TimeInterval] = [:]
}

nonisolated struct RunResult: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var createdAt: Date
    var config: RunConfig
    var picks: [Pick]
    /// Cluster winners in score order.
    var candidates: [String]
    var scenes: [Scene]
    var clusters: [Cluster]
    var excluded: [String: ExclusionTag]
    var scores: [String: PhotoScore]
    var stats: RunStats
    var setRatio: AspectRatio
    /// A short story title for the set.
    var title: String = ""

    func cluster(containing photoID: String) -> Cluster? {
        clusters.first { $0.memberIDs.contains(photoID) }
    }
}
