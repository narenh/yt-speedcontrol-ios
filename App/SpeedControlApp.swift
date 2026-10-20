import ActivityKit
import SwiftUI

@main
struct SpeedControlApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            // Without push updates, opening the app is when the Live Activity catches up
            // with changes made from the TV remote or the web UI.
            if phase == .active { Task { await SpeedActivity.syncAll() } }
        }
    }
}

struct ContentView: View {
    @AppStorage(SpeedAPI.serverKey) private var server = ""
    @AppStorage("selectedDevice") private var selectedId = ""
    @State private var devices: [DeviceInfo] = []
    @State private var running: Set<String> = []
    @State private var message: String?

    private var selected: DeviceInfo? { devices.first { $0.id == selectedId } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("http://homelab.local:8000", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await load() } }
                }

                Section("TV") {
                    if devices.isEmpty {
                        Text("No TVs. Pair one from the web UI first.").foregroundStyle(.secondary)
                    } else {
                        Picker("TV", selection: $selectedId) {
                            ForEach(devices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        if let device = selected {
                            LabeledContent("Status", value: device.connected ? "Connected" : "YouTube not open")
                            LabeledContent("Speed", value: "\(device.speed.speedLabel)×")
                        }
                    }
                }

                if let device = selected {
                    Section {
                        if running.contains(device.id) {
                            Button("End Live Activity", role: .destructive) {
                                Task { await SpeedActivity.end(device.id); refreshRunning() }
                            }
                        } else {
                            Button("Start Live Activity") { start(device) }
                        }
                    }
                }

                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Speed")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        refreshRunning()
        do {
            devices = try await SpeedAPI.devices()
            if selected == nil { selectedId = devices.first?.id ?? "" }
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func start(_ device: DeviceInfo) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Live Activities are turned off for Speed in Settings."
            return
        }
        do {
            try SpeedActivity.start(device)
            refreshRunning()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func refreshRunning() {
        running = Set(SpeedActivity.running.map(\.attributes.deviceId))
    }
}
