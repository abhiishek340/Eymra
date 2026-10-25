import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

nonisolated struct GoogleProfile: Codable, Sendable, Hashable {
    var id: String
    var email: String?
    var name: String?
    var givenName: String?
    var pictureURL: URL?
}

nonisolated enum GoogleSignInError: Error, Sendable, Equatable {
    case notConfigured
    case cancelled
    case failed(String)
}

/// "Sign in with Google" without Google's SDK: the system's secure browser sheet, OAuth 2.0 with PKCE
/// (Google's installed-app flow; iOS clients have no secret). Only the basic profile is read.
@MainActor
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// The iOS OAuth client ID from Info.plist (`GoogleClientID`, set from Config/Secrets.xcconfig).
    static var clientID: String? {
        let id = (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return id.hasSuffix(".apps.googleusercontent.com") ? id : nil
    }

    static var isConfigured: Bool { clientID != nil }

    private var session: ASWebAuthenticationSession?

    func signIn() async throws -> GoogleProfile {
        guard let clientID = Self.clientID else { throw GoogleSignInError.notConfigured }
        let scheme = "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        let redirect = scheme + ":/oauthredirect"
        let verifier = Self.randomURLSafe(64)
        let state = Self.randomURLSafe(24)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        guard let url = components?.url else { throw GoogleSignInError.failed("bad URL") }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleSignInError.cancelled)
                } else {
                    continuation.resume(throwing: GoogleSignInError.failed(error?.localizedDescription ?? "unknown"))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
        session = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw GoogleSignInError.failed("state mismatch") }
        if let error = items.first(where: { $0.name == "error" })?.value { throw GoogleSignInError.failed(error) }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw GoogleSignInError.failed("no code") }
        return try await Self.exchange(code: code, verifier: verifier, clientID: clientID, redirect: redirect)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    // MARK: Token exchange

    nonisolated static func exchange(code: String, verifier: String, clientID: String, redirect: String) async throws -> GoogleProfile {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else { throw GoogleSignInError.failed("bad URL") }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = ["code": code, "client_id": clientID, "redirect_uri": redirect,
                    "grant_type": "authorization_code", "code_verifier": verifier]
        request.httpBody = form.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String else {
            throw GoogleSignInError.failed(String(data: data, encoding: .utf8) ?? "token exchange failed")
        }
        return try profile(fromIDToken: idToken)
    }

    /// Reads the profile claims from the ID token. It came straight from Google over TLS in exchange for our
    /// one-time code, so the signature isn't re-checked; nothing server-side trusts it.
    nonisolated static func profile(fromIDToken token: String) throws -> GoogleProfile {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { throw GoogleSignInError.failed("bad token") }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = claims["sub"] as? String else { throw GoogleSignInError.failed("bad claims") }
        return GoogleProfile(id: sub, email: claims["email"] as? String, name: claims["name"] as? String,
                             givenName: claims["given_name"] as? String,
                             pictureURL: (claims["picture"] as? String).flatMap(URL.init(string:)))
    }

    // MARK: PKCE helpers

    nonisolated static func randomURLSafe(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars[Int(rng.next() % UInt64(chars.count))] })
    }

    nonisolated static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    nonisolated static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
