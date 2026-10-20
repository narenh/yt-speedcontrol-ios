import SwiftUI

/// The playing video: thumbnail, title and channel.
struct NowPlayingCard: View {
    let device: DeviceInfo
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Thumbnail(url: device.thumbnailURL)
                .frame(width: typeSize.isAccessibilitySize ? nil : 112)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.title ?? "YouTube video")
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
        .padding(12)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let title = device.title ?? "A YouTube video"
        return device.channel.map { "\(title), \($0)" } ?? title
    }
}

/// 16:9, rounded, dark until it loads (and if it doesn't).
private struct Thumbnail: View {
    let url: URL?

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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
