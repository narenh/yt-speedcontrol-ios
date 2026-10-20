import SwiftUI

/// The app's colors. The light values are the design's; the dark ones keep the same roles
/// readable on dark grouped backgrounds.
extension Color {
    /// The selected speed: #D92D20, with white text, in both appearances.
    static let canopyAccent = Color(hex: 0xD92D20)
    /// Text buttons, links and destructive rows: #C42B1C, lighter in dark mode.
    static let canopyLink = Color(light: 0xC42B1C, dark: 0xFF6B5E)
    /// The status dot when YouTube is open on the TV.
    static let statusGreen = Color(light: 0x248A3D, dark: 0x30D158)
    /// The Captions button when captions are on: near-black in light mode, near-white in dark,
    /// so "on" is always the high-contrast one.
    static let captionsOnFill = Color(light: 0x1C1C1E, dark: 0xF2F2F7)
    static let captionsOnText = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// The pairing screens' background.
    static let pairBackground = Color(hex: 0x0B0B0C)

    /// Cards on the grouped background: white, or #1C1C1E in dark mode.
    static let card = Color(.secondarySystemGroupedBackground)
    static let groupedBackground = Color(.systemGroupedBackground)

    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// A white (dark: #1C1C1E) rounded card on the grouped background.
    func card(cornerRadius: CGFloat = 20) -> some View {
        background(Color.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - TV status

extension DeviceInfo {
    enum Status: Equatable {
        /// YouTube is open on the TV and playing (or paused on) a video.
        case playing
        /// YouTube is open, with no video.
        case open
        /// YouTube isn't open, or the TV is off.
        case closed
    }

    var status: Status {
        guard connected else { return .closed }
        return videoId == nil ? .open : .playing
    }

    /// YouTube's medium thumbnail (320×180) for the playing video.
    var thumbnailURL: URL? {
        videoId.flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/mqdefault.jpg") }
    }
}

/// A colored dot and a line saying what the TV is doing.
struct StatusLine: View {
    enum Style {
        /// Under the TV name on the main screen: "Playing on YouTube".
        case header
        /// In the TV list: "Playing · 1.5×".
        case row
    }

    let device: DeviceInfo
    var style: Style = .header
    @ScaledMetric(relativeTo: .subheadline) private var dot: CGFloat = 8

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(device.status == .closed ? Color(.systemGray) : .statusGreen)
                .frame(width: dot, height: dot)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    private var text: String {
        switch (device.status, style) {
        case (.playing, .header): "Playing on YouTube"
        case (.playing, .row): "Playing · \(device.speed.speedLabel)×"
        case (.open, _): "YouTube is open"
        case (.closed, _): "YouTube isn't open"
        }
    }
}
