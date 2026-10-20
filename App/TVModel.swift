import ActivityKit
import Foundation
import Observation

/// The signed-in person's TVs, the selected one, and the Live Activity that follows it.
@MainActor
@Observable
final class TVModel {
    private static let selectedKey = "selectedDevice"

    private(set) var devices: [DeviceInfo] = []
    private(set) var loaded = false
    private(set) var activityRunning = SpeedActivity.isRunning
    /// The speed server needs a confirmed Canopy Account email (`403 email_unverified`).
    private(set) var emailUnverified = false
    /// The last error, from the server's `detail`.
    var message: String?
    /// A control call in flight, so the buttons don't double-fire.
    private(set) var busy = false

    var selectedId: String = UserDefaults.standard.string(forKey: selectedKey) ?? "" {
        didSet {
            UserDefaults.standard.set(selectedId, forKey: Self.selectedKey)
            if selectedId != oldValue, let device = selected {
                // The activity follows the selected TV, updated in place.
                Task { await SpeedActivity.show(device, switching: true) }
            }
        }
    }

    var selected: DeviceInfo? { devices.first { $0.id == selectedId } }

    // MARK: Loading

    func refresh() async {
        do {
            let list = try await SpeedAPI.devices()
            devices = list
            loaded = true
            emailUnverified = false
            if selected == nil { selectedId = list.first?.id ?? "" }
            if let device = selected {
                await SpeedActivity.show(device, switching: true)
            } else if SpeedActivity.isRunning {
                await SpeedActivity.end()
            }
        } catch {
            handle(error)
        }
        activityRunning = SpeedActivity.isRunning
    }

    // MARK: Controls

    func setSpeed(_ speed: Double) async {
        guard let id = selected?.id else { return }
        await control { try await SpeedAPI.setSpeed(speed, device: id) }
    }

    func setCaptions(_ on: Bool) async {
        guard let id = selected?.id else { return }
        await control { try await SpeedAPI.setCaptions(on, device: id) }
    }

    private func control(_ call: () async throws -> DeviceInfo) async {
        busy = true
        defer { busy = false }
        do {
            replace(try await call())
            message = nil
        } catch {
            handle(error)
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

    // MARK: Pairing and removing

    /// Throws the server's `detail` so the pair sheet can show it.
    func pair(code: String) async throws {
        do {
            let device = try await SpeedAPI.pair(code: code)
            replace(device)
            selectedId = device.id
            message = nil
        } catch {
            if let api = error as? SpeedAPIError, api.isEmailUnverified { emailUnverified = true }
            throw error
        }
    }

    func removeSelected() async {
        guard let id = selected?.id else { return }
        do {
            try await SpeedAPI.remove(device: id)
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
            try await SpeedActivity.start(device)
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

    func reset() {
        devices = []
        loaded = false
        emailUnverified = false
        message = nil
    }
}
