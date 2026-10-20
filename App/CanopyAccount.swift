import Foundation
import UIKit

/// The signed-in person, as the account service describes them (only what the app uses).
struct CanopyPerson: Decodable, Equatable {
    let id: String
    let email: String
    let emailVerified: Bool
    let firstName: String?
    let lastName: String?
    let shortName: String?

    var displayName: String { shortName ?? firstName ?? email }
}

/// An error answer from the account service: `{"error": "<sentence>", "reason": "<code>"}`.
/// The sentence is for logs; the app matches on `reason`.
struct CanopyAccountError: LocalizedError {
    let status: Int
    let reason: String?
    let sentence: String?

    var errorDescription: String? {
        switch reason {
        case "wrong_code": "That's not the code. Check the email and try again."
        case "expired": "That took too long. Try again."
        case "rate_limited": "Too many tries. Wait a few minutes and try again."
        case "bad_email": "That doesn't look like an email address."
        case "mail_failed": "The email couldn't be sent. Try again later."
        case "verify_first": "Your code ran out. Start again with your email."
        case "unknown_passkey": "That passkey isn't linked to a Canopy Account any more."
        case "not_verified": "The passkey didn't check out. Try again."
        case "passkey_exists": "That passkey is already saved. Sign in with it instead."
        case "signed_out": "You're signed out. Sign in again."
        case "server_error": "Something went wrong at Canopy Account. Try again."
        default: sentence.map { "Canopy Account: \($0)" } ?? "Canopy Account answered \(status)."
        }
    }
}

/// Client for the Canopy Account native API (`docs/native-api.md` in canopy-account-service).
enum CanopyAccount {
    static let baseURL = URL(string: "https://account.canopysf.com/api/native/v1")!
    static let website = URL(string: "https://account.canopysf.com")!

    /// No cookies and no Origin: these endpoints never read either.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    // MARK: Answers

    struct Ceremony: Decodable { let ceremony: String }
    struct SignedIn: Decodable {
        let token: String
        let person: CanopyPerson
        let tookOver: Bool?
    }
    struct EmailStarted: Decodable { let email: String }
    struct EmailVerified: Decodable {
        let state: String  // "new" or "existing"
        let email: String
        let firstName: String?
        let hasPasskey: Bool?
        let unverified: Bool?
    }
    private struct Me: Decodable { let person: CanopyPerson }
    private struct Options<T: Decodable>: Decodable { let options: T }
    private struct Empty: Encodable {}
    private struct Ignored: Decodable {}
    private struct ErrorBody: Decodable {
        let error: String?
        let reason: String?
    }

    // MARK: Signing in

    static func begin() async throws -> String {
        struct Begin: Encodable { let platform, app, device: String }
        // The model ("iPhone"), not the name its owner gave it.
        let model = await MainActor.run { UIDevice.current.model }
        let body = Begin(platform: "ios", app: "Canopy Control", device: String(model.prefix(40)))
        let answer: Ceremony = try await post("auth/begin", body: body, bearer: nil)
        return answer.ceremony
    }

    static func passkeyOptions(ceremony: String) async throws -> PasskeyRequestOptions {
        let answer: Options<PasskeyRequestOptions> = try await post("auth/passkey/options", body: Empty(), bearer: ceremony)
        return answer.options
    }

    static func passkeyVerify(ceremony: String, assertion: PasskeyResponse) async throws -> SignedIn {
        try await post("auth/passkey/verify", body: ["response": assertion], bearer: ceremony)
    }

    static func emailStart(ceremony: String, email: String) async throws -> EmailStarted {
        try await post("auth/email/start", body: ["email": email], bearer: ceremony)
    }

    static func emailVerify(ceremony: String, code: String) async throws -> EmailVerified {
        try await post("auth/email/verify", body: ["code": code], bearer: ceremony)
    }

    static func registerExisting(ceremony: String) async throws -> PasskeyCreationOptions {
        let answer: Options<PasskeyCreationOptions> = try await post("auth/register/existing", body: Empty(), bearer: ceremony)
        return answer.options
    }

    static func registerVerify(ceremony: String, registration: PasskeyResponse) async throws -> SignedIn {
        try await post("auth/register/verify", body: ["response": registration], bearer: ceremony)
    }

    // MARK: Signed in

    static func me(token: String) async throws -> CanopyPerson {
        let answer: Me = try await request("me", method: "GET", body: Optional<Empty>.none, bearer: token)
        return answer.person
    }

    static func signOut(token: String) async throws {
        let _: Ignored = try await post("signout", body: Empty(), bearer: token)
    }

    // MARK: Plumbing

    private static func post<B: Encodable, T: Decodable>(_ path: String, body: B, bearer: String?) async throws -> T {
        try await request(path, method: "POST", body: body, bearer: bearer)
    }

    private static func request<B: Encodable, T: Decodable>(_ path: String, method: String, body: B?, bearer: String?) async throws -> T {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.httpShouldHandleCookies = false
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CanopyAccountError(status: 0, reason: nil, sentence: "no answer")
        }
        guard (200..<300).contains(http.statusCode) else {
            let err = try? JSONDecoder().decode(ErrorBody.self, from: data)
            let error = CanopyAccountError(status: http.statusCode, reason: err?.reason, sentence: err?.error)
            // A signed-in request (not a ceremony step) that's signed out ends the token.
            if http.statusCode == 401, error.reason == "signed_out", !path.hasPrefix("auth/") {
                TokenStore.delete()
            }
            throw error
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
