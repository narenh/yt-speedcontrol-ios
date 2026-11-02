import AVFoundation
import MediaPlayer
import Observation
import os
import UIKit

/// Experiment: the Lock Screen's media controls as a TV remote. Live Activity buttons need Face
/// ID on a locked phone; the Now Playing controls don't. To be the Now Playing app, the app plays
/// silence in a loop (in a `.playback` session that doesn't mix: mixing apps can't be the Now
/// Playing app), and the Now Playing card shows the selected TV.
@MainActor
@Observable
final class NowPlayingRemote {
    static let shared = NowPlayingRemote()
    static let log = Logger(subsystem: "com.canopysf.CanopyControl", category: "remote")

    /// Playing silence and showing the selected TV. Off at launch; off again when another app
    /// takes the audio over.
    private(set) var isOn = false

    @ObservationIgnored private weak var model: TVModel?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    /// Bumped on every start and stop, so an observation left from an earlier start goes quiet.
    @ObservationIgnored private var generation = 0
    /// The video the artwork is for, fetched once per video.
    @ObservationIgnored private var artworkVideo: String?
    @ObservationIgnored private var artwork: MPMediaItemArtwork?

    private init() {}

    // MARK: Starting and stopping

    func start(model: TVModel) {
        guard !isOn else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: Self.silentWAV, fileTypeHint: AVFileType.wav.rawValue)
            player.numberOfLoops = -1
            guard player.play() else {
                Self.log.error("Start failed: the silent player didn't play")
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }
            self.player = player
        } catch {
            Self.log.error("Start failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        self.model = model
        isOn = true
        generation += 1
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated { if type == .began { self?.interrupted() } }
        }
        Self.log.info("Started for \(model.selected?.name ?? "no TV", privacy: .public)")
        follow(generation)
    }

    func stop() {
        guard isOn else { return }
        tearDown()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Self.log.error("Deactivating the session failed: \(error.localizedDescription, privacy: .public)")
        }
        Self.log.info("Stopped")
    }

    /// Another app (music, a call, Siri) took the audio over. It keeps it: no grabbing it back.
    private func interrupted() {
        guard isOn else { return }
        tearDown()
        Self.log.info("Interrupted: another app took the audio, stopped")
    }

    private func tearDown() {
        isOn = false
        generation += 1
        player?.stop()
        player = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        model = nil
        artworkVideo = nil
        artwork = nil
    }

    // MARK: Now Playing card

    /// Shows the selected TV now and again whenever it changes: a refresh, a tap, another TV.
    private func follow(_ generation: Int) {
        guard isOn, generation == self.generation, let model else { return }
        let device = withObservationTracking { model.selected } onChange: { [weak self] in
            Task { @MainActor in self?.follow(generation) }
        }
        show(device)
    }

    private func show(_ device: DeviceInfo?) {
        var info: [String: Any] = [:]
        if let device {
            info[MPMediaItemPropertyTitle] = device.title ?? device.name
            if let channel = device.channel { info[MPMediaItemPropertyArtist] = channel }
            info[MPMediaItemPropertyAlbumTitle] = "\(device.name) · \(device.speed.speedLabel)×"
            info[MPNowPlayingInfoPropertyPlaybackRate] = device.playing != false ? 1.0 : 0.0
            loadArtwork(for: device)
            if let artwork, artworkVideo == device.videoId { info[MPMediaItemPropertyArtwork] = artwork }
        } else {
            info[MPMediaItemPropertyTitle] = "Canopy Control"
            info[MPMediaItemPropertyArtist] = "No TV"
            info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// The video's thumbnail, fetched once per video; the card shows it once it's here.
    private func loadArtwork(for device: DeviceInfo) {
        guard device.videoId != artworkVideo else { return }
        artworkVideo = device.videoId
        artwork = nil
        guard let url = device.thumbnailURL else { return }
        let videoId = device.videoId
        let generation = generation
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else {
                Self.log.error("No artwork for \(videoId ?? "", privacy: .public)")
                return
            }
            guard generation == self.generation, artworkVideo == videoId else { return }
            artwork = Self.artwork(image)
            show(model?.selected)
        }
    }

    /// Not on the main actor: the card asks for the image from any thread.
    private nonisolated static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    // MARK: Silence

    /// One second of 16-bit mono silence at 44.1 kHz, as a WAV file, for the player to loop.
    private static let silentWAV: Data = {
        let rate: UInt32 = 44_100
        let size = rate * 2
        var data = Data()
        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        append("RIFF"); append32(36 + size); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1); append32(rate); append32(rate * 2); append16(2); append16(16)
        append("data"); append32(size)
        data.append(Data(count: Int(size)))
        return data
    }()
}
