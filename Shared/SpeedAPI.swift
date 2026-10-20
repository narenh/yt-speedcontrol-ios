import Foundation

/// One TV as reported by the yt-speedcontrol server (`GET /devices`).
struct DeviceInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let connected: Bool
    let videoId: String?
    let speed: Double
    let captions: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, connected, speed, captions
        case videoId = "video_id"
    }
}

/// An error answer from the speed server: `{"detail": "<sentence>", "reason": "<code>"}`.
/// `detail` is written for people, so it's what the app shows.
struct SpeedAPIError: LocalizedError {
    let status: Int
    let reason: String?
    let message: String
    var errorDescription: String? { message }

    /// The token is over (or there isn't one): sign in again.
    var isSignedOut: Bool { status == 401 }
    /// The person's Canopy Account email isn't confirmed, and this server needs it to be.
    var isEmailUnverified: Bool { status == 403 && reason == "email_unverified" }

    static let noToken = SpeedAPIError(status: 401, reason: "signed_out", message: "Sign in to Canopy Control.")
}

/// Thin client for the yt-speedcontrol HTTP API. Every request carries the Canopy Account token.
/// Live Activity intents run in the app's process, so they use this too.
enum SpeedAPI {
    static let speeds: [Double] = [1, 1.25, 1.5, 1.75, 2]
    static let baseURL = URL(string: "https://ytspeed.canopysf.com")!

    /// No cookies: the token is the only credential.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }()

    static func devices() async throws -> [DeviceInfo] {
        try await request("devices", method: "GET")
    }

    static func pair(code: String) async throws -> DeviceInfo {
        try await request("pair", method: "POST", body: ["code": code])
    }

    static func remove(device: String) async throws {
        struct Removed: Decodable {}
        let _: Removed = try await request("devices/\(device)", method: "DELETE")
    }

    static func setSpeed(_ speed: Double, device: String) async throws -> DeviceInfo {
        try await request("devices/\(device)/speed/\(speed.pathValue)", method: "POST")
    }

    static func setCaptions(_ on: Bool, device: String) async throws -> DeviceInfo {
        try await request("devices/\(device)/captions/\(on ? "on" : "off")", method: "POST")
    }

    private struct ErrorBody: Decodable {
        let detail: String?
        let reason: String?
    }

    private static func request<T: Decodable>(_ path: String, method: String, body: [String: String]? = nil) async throws -> T {
        guard let token = TokenStore.token else { throw SpeedAPIError.noToken }
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.httpShouldHandleCookies = false
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SpeedAPIError(status: 0, reason: nil, message: "No answer from the server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let err = try? JSONDecoder().decode(ErrorBody.self, from: data)
            let error = SpeedAPIError(status: http.statusCode, reason: err?.reason,
                                      message: err?.detail ?? "Server error \(http.statusCode).")
            if error.isSignedOut { TokenStore.delete() }
            throw error
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension Double {
    /// 1 → "1", 1.25 → "1.25", 1.5 → "1.5" (for display, in the person's locale)
    var speedLabel: String { formatted(.number.precision(.fractionLength(0...2))) }

    /// 1 → "1", 1.25 → "1.25" (for URLs: never localized)
    var pathValue: String { self == rounded() ? String(Int(self)) : String(self) }
}
