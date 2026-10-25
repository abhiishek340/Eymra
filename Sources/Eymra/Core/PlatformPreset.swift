import Foundation

/// How the final set is ordered for posting.
nonisolated enum OrderingRule: String, Codable, Sendable, Hashable {
    /// Strongest people shot as the cover, the rest in capture order, second-strongest as the closer.
    case coverThenStory
    /// Capture order from start to end (slideshows).
    case chronological
    /// Highest score first.
    case bestFirst
}

nonisolated struct PlatformPreset: Codable, Sendable, Hashable, Identifiable {
    enum ID: String, Codable, Sendable, Hashable, CaseIterable {
        case instagramCarousel, instagramSingle, reels, facebook, x
    }

    var id: ID
    var name: String
    var defaultCount: Int
    var maxCount: Int
    /// Preferred aspect ratios, most preferred first. The first one is the set ratio used for crops.
    var ratios: [AspectRatio]
    var ordering: OrderingRule
    /// URL scheme opened by "Open app" on the results screen.
    var appURL: String?
    var symbol: String

    var primaryRatio: AspectRatio { ratios.first ?? .square }

    static let all: [PlatformPreset] = [
        PlatformPreset(id: .instagramCarousel, name: "Instagram carousel", defaultCount: 10, maxCount: 20,
                       ratios: [.portrait4x5, .square], ordering: .coverThenStory,
                       appURL: "instagram://app", symbol: "square.stack"),
        PlatformPreset(id: .instagramSingle, name: "Instagram post", defaultCount: 1, maxCount: 1,
                       ratios: [.portrait4x5, .square], ordering: .bestFirst,
                       appURL: "instagram://app", symbol: "square"),
        PlatformPreset(id: .reels, name: "Reels / TikTok", defaultCount: 10, maxCount: 20,
                       ratios: [.vertical9x16, .portrait3x4], ordering: .chronological,
                       appURL: "instagram://reels", symbol: "rectangle.portrait"),
        PlatformPreset(id: .facebook, name: "Facebook post", defaultCount: 6, maxCount: 20,
                       ratios: [.portrait4x5, .square, .landscape191x1], ordering: .coverThenStory,
                       appURL: "fb://", symbol: "rectangle.grid.2x2"),
        PlatformPreset(id: .x, name: "X post", defaultCount: 4, maxCount: 4,
                       ratios: [.landscape16x9, .square], ordering: .bestFirst,
                       appURL: "twitter://", symbol: "rectangle"),
    ]

    static func preset(_ id: ID) -> PlatformPreset {
        all.first { $0.id == id } ?? all[0]
    }
}
