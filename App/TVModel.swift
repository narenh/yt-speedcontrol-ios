import ActivityKit
import Foundation
import Observation
import os

/// The signed-in person's TVs, the selected one, the Live Activity that follows it, and the
/// person's settings on the speed server.
@MainActor
@Observable
final class TVModel {
    static let selectedKey = "selectedDevice"
    private static let log = Logger(subsystem: "com.canopysf.CanopyControl", category: "settings")

    private(set) var devices: [DeviceInfo] = []
    private(set) var loaded = false
    private(set) var activityRunning = SpeedActivity.isRunning
    /// The speed server needs a confirmed Canopy Account email (`403 email_unverified`).
    private(set) var emailUnverified = false
    /// "Sponsor Block only" TVs (`/skip-tvs`): sponsor skipping, no remote, no Live Activity.
    private(set) var skipTVs: [SkipTV] = []
    /// False after `403 skip_not_allowed`: this account can't use the feature, so the app hides it.
    private(set) var skipAllowed = true
    /// Bumped on every local change to `skipTVs`, so a load that left before it doesn't undo it.
    @ObservationIgnored private var skipTVChanges = 0
    @ObservationIgnored private var skipLoading = false
    /// The last error, from the server's `detail`.
    var message: String?
    /// Speed and captions changes in flight per TV. Taps don't wait for them: only the latest
    /// tap's answer is shown (`controlTaps`).
    @ObservationIgnored private var controlPending: [String: Int] = [:]
    @ObservationIgnored private var controlTaps: [String: Int] = [:]
    /// TVs with a skip-sponsors change in flight: their row waits for the server's answer.
    private(set) var skipPending: Set<String> = []
    /// Changes started or finished per TV, so a refresh that left the server before one of them
    /// landed doesn't put the old value back.
    @ObservationIgnored private var controlChanges: [String: Int] = [:]
    @ObservationIgnored private var skipChanges: [String: Int] = [:]

    /// `auto_captions` from `/me/settings`. True until the server says otherwise, and when it
    /// can't (an older server without the endpoint). Saved for the Live Activity's speed buttons.
    private(set) var autoCaptions = AccountSettings.saved {
        didSet {
            #if DEBUG
            if isPreview { return }
            #endif
            AccountSettings.saved = autoCaptions
        }
    }
    private(set) var autoCaptionsPending = false
    /// Why the last change to auto captions didn't stick.
    private(set) var autoCaptionsError: String?

    #if DEBUG
    /// Sample TVs, no server: for previews.
    @ObservationIgnored private(set) var isPreview = false
    #endif

    var selectedId: String = UserDefaults.standard.string(forKey: selectedKey) ?? "" {
        didSet {
            UserDefaults.standard.set(selectedId, forKey: Self.selectedKey)
            if selectedId != oldValue, !following, let device = selected {
                // The activity follows the selected TV, updated in place.
                Task {
                    await SpeedActivity.show(device, switching: true)
                    ActivityPush.shared.activityTVChanged()
                }
            }
        }
    }

    /// Selecting the TV of a newly adopted activity, which already shows it.
    @ObservationIgnored private var following = false
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .liveActivityTVChanged, object: nil, queue: .main) { [weak self] note in
            guard let deviceId = note.object as? String else { return }
            MainActor.assumeIsolated { self?.follow(deviceId) }
        }
    }

    /// A new activity (usually started by the server's push) is for this TV: select it.
    private func follow(_ deviceId: String) {
        following = true
        selectedId = deviceId
        following = false
        activityRunning = SpeedActivity.isRunning
    }

    var selected: DeviceInfo? { devices.first { $0.id == selectedId } }

    // MARK: Loading

    func refresh() async {
        #if DEBUG
        if isPreview { return }
        #endif
        // Its own task: it never slows or fails the TV refresh.
        if skipAllowed, !skipLoading {
            skipLoading = true
            Task { await loadSkipTVs() }
        }
        let changes = Changes(control: controlChanges, skip: skipChanges)
        do {
            let list = try await SpeedAPI.devices()
            devices = list.map { merging($0, since: changes) }
            loaded = true
            emailUnverified = false
            if selected == nil { selectedId = list.first?.id ?? "" }
            if let device = selected {
                await SpeedActivity.show(device, switching: true)
                ActivityPush.shared.activityTVChanged()
            } else if SpeedActivity.isRunning {
                await SpeedActivity.end()
            }
        } catch {
            handle(error)
        }
        activityRunning = SpeedActivity.isRunning
    }

    private func loadSkipTVs() async {
        defer { skipLoading = false }
        let changes = skipTVChanges
        do {
            let list = try await SpeedAPI.skipTVs()
            if changes == skipTVChanges, list != skipTVs { skipTVs = list }
        } catch {
            if let api = error as? SpeedAPIError, api.isSkipNotAllowed {
                skipAllowed = false
                skipTVs = []
            } else {
                Self.log.error("GET /skip-tvs failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Controls

    /// The speed changes on screen right away, and with auto captions on, captions with it; the
    /// server's answer then replaces the TV. An error puts the old values back and shows the
    /// server's `detail`.
    func setSpeed(_ speed: Double) {
        guard let device = selected, device.speed != speed else { return }
        let autoCaptions = autoCaptions
        control(device.id, change: {
            $0.speed = speed
            $0.captions = AccountSettings.captions(afterSpeed: speed, autoCaptions: autoCaptions, current: $0.captions)
        }) { try await SpeedAPI.setSpeed(speed, device: device.id) }
    }

    func setCaptions(_ on: Bool) {
        guard let device = selected, device.captions != on else { return }
        control(device.id, change: { $0.captions = on }) { try await SpeedAPI.setCaptions(on, device: device.id) }
    }

    func setPlaying(_ play: Bool) {
        guard let device = selected else { return }
        control(device.id, change: { $0.playing = play }) { try await SpeedAPI.setPlaying(play, device: device.id) }
    }

    private func control(_ id: String, change: (inout DeviceInfo) -> Void, call: @escaping () async throws -> DeviceInfo) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        let before = devices[i]
        change(&devices[i])
        #if DEBUG
        if isPreview { return }
        #endif
        controlTaps[id, default: 0] += 1
        let tap = controlTaps[id]
        controlPending[id, default: 0] += 1
        controlChanges[id, default: 0] += 1
        Task {
            defer {
                controlPending[id, default: 1] -= 1
                if controlPending[id] == 0 { controlPending[id] = nil }
                controlChanges[id, default: 0] += 1
            }
            let changes = Changes(control: controlChanges, skip: skipChanges)
            do {
                let answer = try await call()
                // A later tap's answer says where things ended up; this one would flicker back.
                guard controlTaps[id] == tap else { return }
                // The answer's speed, captions and playing are the server's word; only skip may be newer here.
                replace(merging(answer, since: changes, keepControl: false))
                message = nil
            } catch {
                guard controlTaps[id] == tap else { return }
                if let j = devices.firstIndex(where: { $0.id == id }) {
                    devices[j].speed = before.speed
                    devices[j].captions = before.captions
                    devices[j].playing = before.playing
                }
                handle(error)
            }
        }
    }

    private func replace(_ device: DeviceInfo) {
        if let i = devices.firstIndex(where: { $0.id == device.id }) {
            devices[i] = device
        } else {
            devices.append(device)
        }
        Task { await SpeedActivity.show(device) }
    }

    /// Turns skipping sponsors on or off for the selected TV: the row flips right away, then
    /// takes the server's answer. An error puts it back and shows the server's `detail`.
    func setSkipSponsors(_ on: Bool) {
        guard let i = devices.firstIndex(where: { $0.id == selectedId }),
              let before = devices[i].skipSponsors, before != on else { return }
        let id = devices[i].id
        guard !skipPending.contains(id) else { return }
        devices[i].skipSponsors = on
        #if DEBUG
        if isPreview { return }
        #endif
        skipPending.insert(id)
        skipChanges[id, default: 0] += 1
        Task {
            defer {
                skipPending.remove(id)
                skipChanges[id, default: 0] += 1
            }
            let changes = Changes(control: controlChanges, skip: skipChanges)
            do {
                replace(merging(try await SpeedAPI.setSkipSponsors(on, device: id), since: changes, keepSkip: false))
                message = nil
            } catch {
                if let j = devices.firstIndex(where: { $0.id == id }) { devices[j].skipSponsors = before }
                handle(error)
            }
        }
    }

    /// The change counters when a server call was asked for.
    private struct Changes {
        let control: [String: Int]
        let skip: [String: Int]
    }

    /// The server's answer for a TV, keeping the app's values for anything with a change in
    /// flight, or one that landed while this answer was on its way.
    /// `keepControl`/`keepSkip` false: the answer is to that very change, so it's the server's word.
    private func merging(_ device: DeviceInfo, since changes: Changes, keepControl: Bool = true, keepSkip: Bool = true) -> DeviceInfo {
        guard let local = devices.first(where: { $0.id == device.id }) else { return device }
        let id = device.id
        var device = device
        if keepSkip, skipPending.contains(id) || skipChanges[id] != changes.skip[id] {
            device.skipSponsors = local.skipSponsors
        }
        if keepControl, controlPending[id] != nil || controlChanges[id] != changes.control[id] {
            device.speed = local.speed
            device.captions = local.captions
            device.playing = local.playing
        }
        return device
    }

    /// Renames the selected TV (`nil`: back to the TV's own name). The list and the Live Activity
    /// take the answer right away; the server's push says the same a moment later.
    func renameSelected(to name: String?) async {
        guard let id = selected?.id else { return }
        do {
            try await rename(device: id, to: name)
        } catch {
            handle(error)
        }
    }

    /// Renames one TV, like `renameSelected`, but throws the server's `detail` (for the rename
    /// screen and the pairing name step) instead of showing it on the main screen.
    func rename(device id: String, to name: String?) async throws {
        #if DEBUG
        if isPreview, let i = devices.firstIndex(where: { $0.id == id }) {
            let d = devices[i]
            devices[i] = DeviceInfo(id: d.id, name: name ?? d.name, connected: d.connected, videoId: d.videoId,
                                    speed: d.speed, captions: d.captions, playing: d.playing, skipSponsors: d.skipSponsors,
                                    title: d.title, channel: d.channel)
            return
        }
        #endif
        let changes = Changes(control: controlChanges, skip: skipChanges)
        replace(merging(try await SpeedAPI.rename(device: id, name: name), since: changes))
        message = nil
    }

    // MARK: Settings

    /// `GET /me/settings`. If it fails (an older server answers 404), auto captions stays on,
    /// which is what the server did before it had the setting; the failure is only logged.
    func loadSettings() async {
        #if DEBUG
        if isPreview { return }
        #endif
        guard !autoCaptionsPending else { return }
        do {
            let settings = try await SpeedAPI.settings()
            if !autoCaptionsPending { autoCaptions = settings.autoCaptions }
        } catch {
            if let api = error as? SpeedAPIError, api.isEmailUnverified { emailUnverified = true }
            Self.log.error("GET /me/settings failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The switch flips right away; an error puts it back and says why under it.
    func setAutoCaptions(_ on: Bool) {
        guard on != autoCaptions, !autoCaptionsPending else { return }
        let before = autoCaptions
        autoCaptions = on
        autoCaptionsError = nil
        #if DEBUG
        if isPreview { return }
        #endif
        autoCaptionsPending = true
        Task {
            defer { autoCaptionsPending = false }
            do {
                autoCaptions = try await SpeedAPI.setAutoCaptions(on).autoCaptions
            } catch {
                autoCaptions = before
                Self.log.error("PATCH /me/settings failed: \(error.localizedDescription, privacy: .public)")
                if let api = error as? SpeedAPIError {
                    if api.isSignedOut { return }
                    if api.isEmailUnverified { emailUnverified = true }
                }
                if (error as? URLError)?.code == .cancelled { return }
                autoCaptionsError = error.localizedDescription
            }
        }
    }

    // MARK: Pairing and removing

    /// Throws the server's `detail` so the pairing screen can show it. Returns the new TV, with
    /// the name it reported (or the custom name it already had, when paired again).
    @discardableResult
    func pair(code: String) async throws -> DeviceInfo {
        do {
            let device = try await SpeedAPI.pair(code: code)
            replace(device)
            selectedId = device.id
            message = nil
            return device
        } catch {
            if let api = error as? SpeedAPIError, api.isEmailUnverified { emailUnverified = true }
            throw error
        }
    }

    /// Adds a Sponsor Block only TV with its code. Throws a message fit for the pairing screen.
    @discardableResult
    func addSkipTV(code: String) async throws -> SkipTV {
        #if DEBUG
        if isPreview {
            let tv = SkipTV(id: "preview-skip-\(skipTVs.count)", name: "New TV")
            skipTVs.append(tv)
            return tv
        }
        #endif
        do {
            let tv = try await SpeedAPI.addSkipTV(code: code)
            skipTVChanges += 1
            skipTVs.removeAll { $0.id == tv.id }
            skipTVs.append(tv)
            return tv
        } catch let api as SpeedAPIError {
            if api.isEmailUnverified { emailUnverified = true }
            if api.isAlreadyPaired {
                throw SpeedAPIError(status: api.status, reason: api.reason,
                                    message: "That TV is already one of your paired TVs. Use its Skip sponsors toggle instead.")
            }
            if api.isTooManyDevices {
                throw SpeedAPIError(status: api.status, reason: api.reason,
                                    message: "You've reached the limit of TVs. Remove one to add another.")
            }
            throw api
        }
    }

    /// Renames a Sponsor Block only TV (`nil`: back to the TV's own name). Throws the server's `detail`.
    func renameSkipTV(_ id: String, to name: String?) async throws {
        #if DEBUG
        if isPreview {
            if let i = skipTVs.firstIndex(where: { $0.id == id }) { skipTVs[i] = SkipTV(id: id, name: name ?? skipTVs[i].name) }
            return
        }
        #endif
        let tv = try await SpeedAPI.renameSkipTV(id, name: name)
        skipTVChanges += 1
        if let i = skipTVs.firstIndex(where: { $0.id == id }) { skipTVs[i] = tv }
    }

    /// Removes a Sponsor Block only TV: gone from the list right away, back in its place with the
    /// server's `detail` if the server says no.
    func removeSkipTV(_ id: String) {
        guard let i = skipTVs.firstIndex(where: { $0.id == id }) else { return }
        let removed = skipTVs.remove(at: i)
        skipTVChanges += 1
        #if DEBUG
        if isPreview { return }
        #endif
        Task {
            do {
                try await SpeedAPI.removeSkipTV(id)
                skipTVChanges += 1
                message = nil
            } catch {
                skipTVChanges += 1
                if !skipTVs.contains(where: { $0.id == id }) { skipTVs.insert(removed, at: min(i, skipTVs.count)) }
                handle(error)
            }
        }
    }

    func removeSelected() async {
        guard let id = selected?.id else { return }
        do {
            #if DEBUG
            if !isPreview { try await SpeedAPI.remove(device: id) }
            #else
            try await SpeedAPI.remove(device: id)
            #endif
            devices.removeAll { $0.id == id }
            selectedId = devices.first?.id ?? ""
            if devices.isEmpty { await endActivity() }
            message = nil
        } catch {
            handle(error)
        }
    }

    // MARK: Live Activity

    func startActivity() async {
        guard let device = selected else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Live Activities are turned off for Canopy Control in Settings."
            return
        }
        do {
            // Same registration path as a push-started activity.
            let activity = try await SpeedActivity.start(device)
            ActivityPush.shared.adopt(activity, select: false)
            ActivityPush.shared.activityTVChanged()
            message = nil
        } catch {
            message = error.localizedDescription
        }
        activityRunning = SpeedActivity.isRunning
    }

    func endActivity() async {
        await SpeedActivity.end()
        activityRunning = false
    }

    // MARK: Errors

    private func handle(_ error: Error) {
        if let api = error as? SpeedAPIError {
            // 401: SpeedAPI has deleted the token, and the session goes back to sign-in.
            if api.isSignedOut { return }
            if api.isEmailUnverified {
                emailUnverified = true
                return
            }
        }
        if (error as? URLError)?.code == .cancelled { return }
        message = error.localizedDescription
    }

    #if DEBUG
    /// Sample TVs for previews and the `-MainViewPreview` launch argument. Never calls the
    /// server: controls, renames and removes change the samples only.
    static func preview(_ devices: [DeviceInfo] = DeviceInfo.samples, selecting id: String? = nil,
                        autoCaptions: Bool = true, loaded: Bool = true,
                        skipTVs: [SkipTV] = SkipTV.samples, skipAllowed: Bool = true) -> TVModel {
        let model = TVModel()
        model.isPreview = true
        model.skipTVs = skipTVs
        model.skipAllowed = skipAllowed
        model.devices = devices
        model.loaded = loaded
        model.autoCaptions = autoCaptions
        model.following = true
        model.selectedId = id ?? devices.first?.id ?? ""
        model.following = false
        return model
    }
    #endif

    func reset() {
        devices = []
        skipTVs = []
        skipAllowed = true
        loaded = false
        emailUnverified = false
        message = nil
    }
}

#if DEBUG
extension SkipTV {
    static let samples: [SkipTV] = [
        SkipTV(id: "preview-skip-1", name: "Mom's TV"),
        SkipTV(id: "preview-skip-2", name: "Cabin Living Room"),
    ]
}

extension DeviceInfo {
    static let samples: [DeviceInfo] = [
        DeviceInfo(id: "preview-1", name: "Living Room TV", connected: true, videoId: "dQw4w9WgXcQ",
                   speed: 1.5, captions: true, skipSponsors: true,
                   title: "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)", channel: "Rick Astley"),
        DeviceInfo(id: "preview-2", name: "Bedroom TV", connected: false, videoId: nil,
                   speed: 1, captions: false),
    ]

    /// The first sample with YouTube open but nothing playing.
    static let waitingSample = DeviceInfo(id: "preview-1", name: "Living Room TV", connected: true, videoId: nil,
                                          speed: 1, captions: false, skipSponsors: true)
}
#endif
