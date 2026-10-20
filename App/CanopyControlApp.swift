import SwiftUI

@main
struct CanopyControlApp: App {
    @State private var session: AppSession

    init() {
        // Before anything reads the token: a Keychain item left from an earlier install.
        TokenStore.clearIfFreshInstall()
        _session = State(initialValue: AppSession())
        // Here rather than in a view: the system launches the app in the background (no UI)
        // when the server starts a Live Activity by push.
        #if DEBUG
        if Self.mainViewPreview { return }
        if LiveActivityPreview.isOn {
            // Not ActivityPush: signed out, it would end the sample activity.
            LiveActivityPreview.run()
            return
        }
        #endif
        ActivityPush.shared.start()
    }

    #if DEBUG
    /// Debug only: launch with `-MainViewPreview` to show the main screen with sample TVs and no
    /// sign-in, for checking its layout in the simulator.
    private static var mainViewPreview: Bool { ProcessInfo.processInfo.arguments.contains("-MainViewPreview") }
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if Self.mainViewPreview {
                    MainView(model: .preview())
                } else if session.isSignedIn {
                    MainView()
                } else {
                    SignInView()
                }
                #else
                if session.isSignedIn {
                    MainView()
                } else {
                    SignInView()
                }
                #endif
            }
            .environment(session)
        }
    }
}
