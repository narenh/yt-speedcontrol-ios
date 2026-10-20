import SwiftUI

@main
struct CanopyControlApp: App {
    @State private var session: AppSession

    init() {
        // Before anything reads the token: a Keychain item left from an earlier install.
        TokenStore.clearIfFreshInstall()
        _session = State(initialValue: AppSession())
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
