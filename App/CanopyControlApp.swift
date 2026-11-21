import SwiftUI

@main
struct CanopyControlApp: App {
    @State private var session: AppSession

    init() {
        // Before anything reads the token: a Keychain item left from an earlier install.
        TokenStore.clearIfFreshInstall()
        #if DEBUG
        _session = State(initialValue: Self.mainViewPreview ? AppSession.preview() : AppSession())
        #else
        _session = State(initialValue: AppSession())
        #endif
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
    /// sign-in, for checking its layout in the simulator. Add `-PreviewIdle` for a TV with nothing
    /// playing, `-PreviewSwitcher` or `-PreviewSettings` to open those sheets, `-PreviewRename` for
    /// Settings on the Name screen, `-PreviewSkipOff` for the turn-off-sponsor-skipping dialog, or
    /// `-PreviewSkipSegment` (switcher on Sponsor Block), `-PreviewSkipEmpty` (no such TVs) or
    /// `-PreviewNoSkip` (account can't use them), or `-PreviewNameStep` for pairing's name step (`-PreviewNameText "<text>"` fills its field).
    private static var mainViewPreview: Bool { ProcessInfo.processInfo.arguments.contains("-MainViewPreview") }
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if Self.mainViewPreview {
                    MainView(model: .preview(selecting: ProcessInfo.processInfo.arguments.contains("-PreviewIdle") ? "preview-2" : nil,
                                             skipTVs: ProcessInfo.processInfo.arguments.contains("-PreviewSkipEmpty") ? [] : SkipTV.samples,
                                             skipAllowed: !ProcessInfo.processInfo.arguments.contains("-PreviewNoSkip")))
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
