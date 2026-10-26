import CoreGraphics
import Foundation
import ImageIO
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
    /// The saved face came from an older version that recognised faces differently; it needs a new scan.
    private(set) var faceNeedsRedo = false
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

    /// Saves the face setup. Signatures that don't agree with the rest are dropped (with their crops).
    /// Returns how many were kept.
    @discardableResult
    func saveFace(crops: [CGImage], prints: [[Float]]) -> Int {
        let kept = Identity.consistentReferences(prints)
        let keptCrops = zip(crops, prints).filter { pair in kept.contains(pair.1) }.map(\.0)
        do {
            try FaceReferenceStore.save(crops: keptCrops.isEmpty ? crops : keptCrops, prints: kept)
        } catch {
            Self.log.error("Saving face failed: \(error.localizedDescription, privacy: .public)")
        }
        reloadFace()
        return kept.count
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
        var reference = FaceReferenceStore.load()
        // Face signatures are 128 numbers; anything else was saved by an older version and can't be compared.
        if let r = reference, r.prints.contains(where: { $0.count != FaceReferenceStore.signatureLength }) {
            FaceReferenceStore.clear()
            reference = nil
            faceNeedsRedo = true
        }
        meReference = reference
        faceImageURLs = FaceReferenceStore.faceImageURLs()
        if meReference != nil { faceNeedsRedo = false }
        if let r = reference, r.version != MeReference.currentVersion { Task { await remakeReference() } }
    }

    /// Re-reads the saved face crops with the current method, so improvements don't need a new scan.
    private func remakeReference() async {
        var crops: [CGImage] = [], prints: [[Float]] = []
        for url in faceImageURLs {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let face = await FaceEmbedder.largestFace(in: image), !face.signature.isEmpty else { continue }
            crops.append(image)
            prints.append(face.signature)
        }
        guard !prints.isEmpty else { return }
        Self.log.info("Re-made \(prints.count) face references with the current method")
        saveFace(crops: crops, prints: prints)
    }

    // MARK: Storage

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
