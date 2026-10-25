import CoreGraphics
import Foundation
import Observation
import os

nonisolated struct UserProfile: Codable, Sendable, Hashable {
    enum Provider: String, Codable, Sendable { case google, local }

    var id: String
    var name: String
    var firstName: String
    var email: String?
    var pictureURL: URL?
    var provider: Provider
}

/// Who the user is: their profile, what they told us in onboarding, and their face setup.
/// Everything lives on this phone; there is no server.
@MainActor @Observable
final class Account {
    private static let log = Logger(subsystem: "app.eymra", category: "account")
    private let defaults: UserDefaults

    private(set) var profile: UserProfile?
    var prefs: UserPrefs { didSet { save(prefs, "prefs") } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: "onboarded") } }
    private(set) var meReference: MeReference?
    private(set) var faceImageURLs: [URL] = []
    var signInError: String?
    var isSigningIn = false
    private let google = GoogleSignIn()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profile = Self.load(UserProfile.self, "profile", defaults)
        prefs = Self.load(UserPrefs.self, "prefs", defaults) ?? UserPrefs()
        hasCompletedOnboarding = defaults.bool(forKey: "onboarded")
        reloadFace()
    }

    var isSignedIn: Bool { profile != nil }
    var hasFace: Bool { !faceImageURLs.isEmpty }
    /// Face set up but Vision couldn't make prints (e.g. on the Simulator), so we can't recognise the user.
    var faceUnusable: Bool { hasFace && meReference == nil }

    var greetingName: String { profile?.firstName ?? "" }

    // MARK: Sign in

    func signInWithGoogle() async {
        signInError = nil
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let g = try await google.signIn()
            let name = g.name ?? g.email ?? String(localized: "Friend")
            setProfile(UserProfile(id: "google:\(g.id)", name: name, firstName: g.givenName ?? name.components(separatedBy: " ").first ?? name,
                                   email: g.email, pictureURL: g.pictureURL, provider: .google))
        } catch GoogleSignInError.cancelled {
            // The user closed the sheet; nothing to say.
        } catch GoogleSignInError.notConfigured {
            signInError = String(localized: "Google sign-in isn't switched on in this version yet.")
        } catch {
            Self.log.error("Google sign-in failed: \(String(describing: error), privacy: .public)")
            signInError = String(localized: "We couldn't sign you in with Google. Please try again.")
        }
    }

    /// Only offered when Google sign-in isn't set up in this build.
    func continueWithName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let display = trimmed.isEmpty ? String(localized: "Friend") : trimmed
        setProfile(UserProfile(id: "local:\(UUID().uuidString)", name: display,
                               firstName: display.components(separatedBy: " ").first ?? display,
                               email: nil, pictureURL: nil, provider: .local))
    }

    func setProfile(_ profile: UserProfile) {
        self.profile = profile
        save(profile, "profile")
    }

    /// Forgets everything about the user on this phone: profile, answers and face.
    func signOut() {
        profile = nil
        defaults.removeObject(forKey: "profile")
        prefs = UserPrefs()
        hasCompletedOnboarding = false
        FaceReferenceStore.clear()
        reloadFace()
    }

    // MARK: Face

    func saveFace(crops: [CGImage], prints: [[Float]]) {
        do {
            try FaceReferenceStore.save(crops: crops, prints: prints)
        } catch {
            Self.log.error("Saving face failed: \(error.localizedDescription, privacy: .public)")
        }
        reloadFace()
    }

    func removeFace() {
        FaceReferenceStore.clear()
        reloadFace()
    }

    /// For UI tests: use the fixture set's reference prints without touching disk.
    func useReference(_ reference: MeReference?) {
        meReference = reference
    }

    private func reloadFace() {
        meReference = FaceReferenceStore.load()
        faceImageURLs = FaceReferenceStore.faceImageURLs()
    }

    // MARK: Storage

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
