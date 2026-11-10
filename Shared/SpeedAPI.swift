import Foundation

/// One TV as reported by the yt-speedcontrol server (`GET /devices`).
struct DeviceInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let connected: Bool
    let videoId: String?
    /// `var`: the app shows a tapped speed or captions change before the server answers.
    var speed: Double
    var captions: Bool
    /// Playing (or starting) vs paused, stopped or ended, as the TV last said. `nil` until it has
    /// said, and from older servers.
    var playing: Bool?
    /// Whether the server skips sponsor segments and ads on this TV. `nil` (absent) when this
    /// person may not use it or the server has it off, or from an older server: no row then.
    var skipSponsors: Bool?
    /// The playing video's title and channel, when the server knows them (absent from older servers).
    var title: String?
    var channel: String?

    enum CodingKeys: String, CodingKey {
        case id, name, connected, speed, captions, playing, title, channel
        case videoId = "video_id"
        case skipSponsors = "skip_sponsors"
    }
}

/// A "Sponsor Block only" TV (`/skip-tvs`): enrolled in sponsor skipping, with no remote control
/// and no Live Activity.
struct SkipTV: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

/// The signed-in person's settings on the speed server (`GET` and `PATCH /me/settings`).
struct AccountSettings: Codable, Equatable {
    /// The server turns captions on when speeding up past 1×, and off back at 1×.
    var autoCaptions: Bool

    enum CodingKeys: String, CodingKey {
        case autoCaptions = "auto_captions"
    }

    /// The last `auto_captions` the app heard, for taps on the Live Activity (they run in the
    /// app's process, but not through `TVModel`). True until the server says otherwise.
    static var saved: Bool {
        get { UserDefaults.standard.object(forKey: "autoCaptions") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoCaptions") }
    }

    /// Captions after a speed change, as the server sets them: with auto captions on, on above 1×
    /// and off at 1×; with it off, as they were.
    static func captions(afterSpeed speed: Double, autoCaptions: Bool, current: Bool) -> Bool {
        autoCaptions ? speed > 1 : current
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

    /// This account can't use Sponsor Block only TVs (`GET /skip-tvs`).
    var isSkipNotAllowed: Bool { status == 403 && reason == "skip_not_allowed" }
    /// `POST /skip-tvs`: that TV is already one of the person's paired TVs.
    var isAlreadyPaired: Bool { status == 409 && reason == "already_paired" }
    var isTooManyDevices: Bool { status == 409 && reason == "too_many_devices" }

    static let noToken = SpeedAPIError(status: 401, reason: "signed_out", message: "Sign in to Canopy Control.")
}

/// Thin client for the yt-speedcontrol HTTP API. Every request carries the Canopy Account token.
/// Live Activity intents run in the app's process, so they use this too.
enum SpeedAPI {
    static let speeds: [Double] = [1, 1.25, 1.5, 1.75, 2]
    static let baseURL = URL(string: "https://control.canopysf.com")!

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

    /// `PATCH /devices/{id}`: a new name (the server trims it; 1–40 characters), or `nil` for the
    /// name the TV reports itself.
    static func rename(device: String, name: String?) async throws -> DeviceInfo {
        try await patch(device: device, ["name": name.map { $0 as Any } ?? NSNull()])
    }

    // MARK: Sponsor Block only TVs

    static func skipTVs() async throws -> [SkipTV] {
        try await request("skip-tvs", method: "GET")
    }

    static func addSkipTV(code: String) async throws -> SkipTV {
        try await request("skip-tvs", method: "POST", body: ["code": code])
    }

    /// `PATCH /skip-tvs/{id}`: a new name, or `nil` for the name the TV reports itself.
    static func renameSkipTV(_ id: String, name: String?) async throws -> SkipTV {
        let body = try JSONSerialization.data(withJSONObject: ["name": name.map { $0 as Any } ?? NSNull()])
        return try JSONDecoder().decode(SkipTV.self, from: try await send("skip-tvs/\(id)", method: "PATCH", body: body))
    }

    static func removeSkipTV(_ id: String) async throws {
        _ = try await send("skip-tvs/\(id)", method: "DELETE", body: nil)
    }

    /// `PATCH /devices/{id}` with `skip_sponsors`. A `403 skip_not_allowed` says why in `detail`.
    static func setSkipSponsors(_ on: Bool, device: String) async throws -> DeviceInfo {
        try await patch(device: device, ["skip_sponsors": on])
    }

    /// `PATCH /devices/{id}`: only the fields in `fields` change. Returns the updated TV.
    private static func patch(device: String, _ fields: [String: Any]) async throws -> DeviceInfo {
        let body = try JSONSerialization.data(withJSONObject: fields)
        return try JSONDecoder().decode(DeviceInfo.self, from: try await send("devices/\(device)", method: "PATCH", body: body))
    }

    static func setSpeed(_ speed: Double, device: String) async throws -> DeviceInfo {
        try await request("devices/\(device)/speed/\(speed.pathValue)", method: "POST")
    }

    static func setCaptions(_ on: Bool, device: String) async throws -> DeviceInfo {
        try await request("devices/\(device)/captions/\(on ? "on" : "off")", method: "POST")
    }

    static func setPlaying(_ play: Bool, device: String) async throws -> DeviceInfo {
        try await request("devices/\(device)/playback/\(play ? "play" : "pause")", method: "POST")
    }

    // MARK: Settings

    static func settings() async throws -> AccountSettings {
        try await request("me/settings", method: "GET")
    }

    /// `PATCH /me/settings`: answers with all the settings.
    static func setAutoCaptions(_ on: Bool) async throws -> AccountSettings {
        let body = try JSONEncoder().encode(AccountSettings(autoCaptions: on))
        return try JSONDecoder().decode(AccountSettings.self, from: try await send("me/settings", method: "PATCH", body: body))
    }

    // MARK: Installs (Live Activity push registration)

    /// `PUT /installs/{id}`: `json` is the body, built by the caller so absent and null differ.
    static func putInstall(_ id: String, json: Data) async throws {
        _ = try await send("installs/\(id)", method: "PUT", body: json)
    }

    /// `DELETE /installs/{id}`: this phone stops getting pushes for the signed-in person.
    static func deleteInstall(_ id: String) async throws {
        _ = try await send("installs/\(id)", method: "DELETE", body: nil)
    }

    private struct ErrorBody: Decodable {
        let detail: String?
        let reason: String?
    }

    private static func request<T: Decodable>(_ path: String, method: String, body: [String: String]? = nil) async throws -> T {
        let data = try await send(path, method: method, body: try body.map { try JSONEncoder().encode($0) })
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// One authorized request; returns the body of a 2xx answer, throws `SpeedAPIError` otherwise.
    private static func send(_ path: String, method: String, body: Data?) async throws -> Data {
        guard let token = TokenStore.token else { throw SpeedAPIError.noToken }
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.httpShouldHandleCookies = false
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
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
        return data
    }
}

extension Double {
    /// 1 → "1", 1.25 → "1.25", 1.5 → "1.5" (for display, in the person's locale)
    var speedLabel: String { formatted(.number.precision(.fractionLength(0...2))) }

    /// 1 → "1", 1.25 → "1.25" (for URLs: never localized)
    var pathValue: String { self == rounded() ? String(Int(self)) : String(self) }
}
