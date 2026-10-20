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
        if LiveActivityPreview.isOn {
            // Not ActivityPush: signed out, it would end the sample activity.
            LiveActivityPreview.run()
            return
        }
        #endif
        ActivityPush.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isSignedIn {
                    MainView()
                } else {
                    SignInView()
                }
            }
            .environment(session)
        }
    }
}
