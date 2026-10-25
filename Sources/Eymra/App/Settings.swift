import Foundation
import Observation

/// User settings persisted in UserDefaults; the API key lives in the Keychain.
@MainActor @Observable
final class Settings {
    private let defaults: UserDefaults
    private static let keyAccount = "anthropic"

    var judgeEnabled: Bool { didSet { defaults.set(judgeEnabled, forKey: "judgeEnabled") } }
    var judgeModel: String { didSet { defaults.set(judgeModel, forKey: "judgeModel") } }
    var judgeLongEdge: Int { didSet { defaults.set(judgeLongEdge, forKey: "judgeLongEdge") } }
    var allowICloudDownloads: Bool { didSet { defaults.set(allowICloudDownloads, forKey: "allowICloudDownloads") } }
    var iCloudWiFiOnly: Bool { didSet { defaults.set(iCloudWiFiOnly, forKey: "iCloudWiFiOnly") } }
    private(set) var hasAPIKey: Bool

    static let longEdgeOptions = [504, 756, 1008]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        judgeEnabled = defaults.object(forKey: "judgeEnabled") as? Bool ?? false
        judgeModel = defaults.string(forKey: "judgeModel") ?? ClaudeJudge.models[0].id
        judgeLongEdge = defaults.object(forKey: "judgeLongEdge") as? Int ?? 756
        allowICloudDownloads = defaults.object(forKey: "allowICloudDownloads") as? Bool ?? true
        iCloudWiFiOnly = defaults.object(forKey: "iCloudWiFiOnly") as? Bool ?? true
        hasAPIKey = !(Keychain.read(Self.keyAccount) ?? "").isEmpty
    }

    var apiKey: String? { Keychain.read(Self.keyAccount) }

    func setAPIKey(_ key: String) {
        Keychain.write(key.trimmingCharacters(in: .whitespacesAndNewlines), account: Self.keyAccount)
        hasAPIKey = !(Keychain.read(Self.keyAccount) ?? "").isEmpty
    }

    /// Whether iCloud originals may be downloaded right now.
    var allowNetworkNow: Bool {
        guard allowICloudDownloads else { return false }
        return iCloudWiFiOnly ? !Reachability.shared.current.isExpensive : true
    }
}
