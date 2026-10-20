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

private struct ErrorDetail: Decodable { let detail: String }

struct SpeedAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Thin client for the yt-speedcontrol HTTP API.
/// Live Activity intents run in the app's process, so plain UserDefaults is shared with them.
enum SpeedAPI {
    static let speeds: [Double] = [1, 1.25, 1.5, 1.75, 2]
    static let serverKey = "serverURL"
    static let defaultServer = "https://ytspeed.canopysf.com"

    static var baseURL: URL? {
        let saved = UserDefaults.standard.string(forKey: serverKey)?.trimmingCharacters(in: .whitespaces)
        let raw = saved?.isEmpty == false ? saved! : defaultServer
        // https by default: the server redirects http, and URLSession turns a redirected POST into a GET.
        return URL(string: raw.hasPrefix("http") ? raw : "https://\(raw)")
    }

    static func devices() async throws -> [DeviceInfo] {
        try await request("devices", method: "GET")
    }

    static func setSpeed(_ speed: Double, device: String) async throws -> DeviceInfo {
        try await request("devices/\(device)/speed/\(speed)", method: "POST")
    }

    static func setCaptions(_ on: Bool, device: String) async throws -> DeviceInfo {
        try await request("devices/\(device)/captions/\(on ? "on" : "off")", method: "POST")
    }

    private static func request<T: Decodable>(_ path: String, method: String) async throws -> T {
        guard let base = baseURL else { throw SpeedAPIError(message: "Set the server address in the app") }
        var req = URLRequest(url: base.appending(path: path))
        req.httpMethod = method
        req.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SpeedAPIError(message: "No response") }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(ErrorDetail.self, from: data))?.detail
            throw SpeedAPIError(message: detail ?? "Server error \(http.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension Double {
    /// 1 → "1", 1.25 → "1.25", 1.5 → "1.5"
    var speedLabel: String { formatted(.number.precision(.fractionLength(0...2))) }
}
