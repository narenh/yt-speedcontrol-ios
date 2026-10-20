import SwiftUI

/// The playing video: thumbnail, title and channel. Fills the space between the header and the
/// controls and centers itself in it: a full-width thumbnail with a large title when that fits,
/// otherwise a row with a small thumbnail. With no title yet (no oEmbed data), just the thumbnail.
struct NowPlayingCard: View {
    let device: DeviceInfo

    var body: some View {
        ViewThatFits(in: .vertical) {
            large
            compact
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // If even the compact row is too tall (huge Dynamic Type, banners), it truncates and
        // clips here instead of pushing the controls off-screen. Wider than the frame so the
        // large thumbnail's shadow isn't cut off at the sides.
        .mask { Rectangle().padding(.horizontal, -24) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 16) {
            Thumbnail(url: device.thumbnailURL, cornerRadius: 18)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
            if let title = device.title {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(.title2, weight: .bold))
                        .tracking(-0.3)
                        .lineLimit(3)
                    if let channel = device.channel {
                        Text(channel)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Only when there's room to breathe: if it would just barely fit, use the row instead.
        .padding(.vertical, 16)
    }

    private var compact: some View {
        HStack(spacing: 12) {
            Thumbnail(url: device.thumbnailURL, cornerRadius: 12)
                .frame(width: 144)
            if let title = device.title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                    if let channel = device.channel {
                        Text(channel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var accessibilityText: String {
        let title = device.title ?? "A YouTube video"
        return device.channel.map { "\(title), \($0)" } ?? title
    }
}

/// 16:9, rounded, dark until it loads (and if it doesn't).
private struct Thumbnail: View {
    let url: URL?
    let cornerRadius: CGFloat

    var body: some View {
        Color(white: 0.11)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "play.rectangle.fill")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .id(url)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    NowPlayingCard(device: DeviceInfo.samples[0])
        .padding()
        .background(Color.groupedBackground)
}
#endif
