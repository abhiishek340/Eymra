import Foundation
import Observation
import SwiftData
import UIKit
import os

/// Dependencies and library access for the whole app.
@MainActor @Observable
final class AppModel {
    private static let log = Logger(subsystem: "app.eymra", category: "app")

    /// Launched with -uiTesting: fixtures, fake extractor, stub judge, in-memory store.
    let isUITesting: Bool
    let source: any PhotoSource
    let extractor: any FeatureExtracting
    let store: FeatureStore
    let container: ModelContainer
    let settings: Settings
    let account: Account
    var access: LibraryAccess

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isUITesting = arguments.contains("-uiTesting")
        if isUITesting {
            Keychain.useMemoryStore()
            let defaults = UserDefaults(suiteName: "eymra-uitests") ?? .standard
            defaults.removePersistentDomain(forName: "eymra-uitests")
            settings = Settings(defaults: defaults)
            settings.judgeEnabled = arguments.contains("-judge")
            account = Account(defaults: defaults)
            if !arguments.contains("-onboarding") {
                account.setProfile(UserProfile(id: "local:test", name: "Alex Rivera", firstName: "Alex", email: nil,
                                               pictureURL: nil, provider: .local))
                account.hasCompletedOnboarding = true
            }
        } else {
            settings = Settings()
            account = Account()
        }
        let fixtures = isUITesting ? try? FixtureSet.load(rebaseTo: Date()) : nil
        if let fixtures {
            if !arguments.contains("-onboarding") { account.useReference(fixtures.meReference) }
            source = FixturePhotoSource(fixtures: fixtures)
            extractor = FakeFeatureExtractor(features: fixtures.features,
                                             delay: arguments.contains("-slowRun") ? .milliseconds(450) : .zero)
        } else {
            source = PhotoLibrary()
            extractor = FeatureExtractor()
        }
        if let persistent = try? FeatureStore.makeContainer(inMemory: isUITesting) {
            container = persistent
        } else if let memory = try? FeatureStore.makeContainer(inMemory: true) {
            Self.log.fault("Persistent store failed; caching in memory for this session")
            container = memory
        } else {
            fatalError("SwiftData could not create even an in-memory store")
        }
        store = FeatureStore(modelContainer: container)
        access = source.authorizationStatus()
    }

    func requestAccess() async {
        access = await source.requestAuthorization()
    }

    func refreshAccess() {
        access = source.authorizationStatus()
    }

    /// The judge to use for a run, or nil when it is off or has no key.
    func makeJudge() -> (any JudgeProvider)? {
        guard settings.judgeEnabled else { return nil }
        if isUITesting { return StubJudge() }
        guard let key = settings.apiKey, !key.isEmpty else { return nil }
        return ClaudeJudge(model: settings.judgeModel, apiKey: key)
    }

    func makePipeline() -> CurationPipeline {
        CurationPipeline(source: source, extractor: extractor, store: store, judge: makeJudge())
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
