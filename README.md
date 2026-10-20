# yt-speedcontrol-ios

Personal iOS 26 app for [yt-speedcontrol](https://github.com/narenh/yt-speedcontrol): pick a paired TV and run a Live Activity with speed buttons (1, 1.25, 1.5, 1.75, 2×) and a captions toggle on the Lock Screen and in the Dynamic Island.

## Build

```
brew install xcodegen
xcodegen generate
open SpeedControl.xcodeproj
```

Set your team in Signing for both targets (or fill `DEVELOPMENT_TEAM` in `project.yml`), then run on your phone. Bundle IDs are `com.narenh.speedcontrol` and `.widget`; change them in `project.yml` if needed. The Xcode project and Info.plists are generated, so edit `project.yml` rather than the project.

## Use

1. Enter the server address (e.g. `http://homelab.local:8000`) and allow local network access.
2. Pick a TV (pair TVs in the web UI) and tap **Start Live Activity**.
3. Speed buttons set the speed (captions on above 1×, off at 1× — same rule as the web UI); the captions pill toggles captions.

## How it works

- `Shared/` is compiled into both targets: the API client, `SpeedAttributes`, and the `LiveActivityIntent`s. The system runs those intents in the app's process, so they read the server address from the app's `UserDefaults` and call the server directly.
- Each tap updates the Live Activity from the server's response.

## Limitations / next

- No push updates: changes made from the TV remote or web UI show up on the Live Activity only after your next tap or when you open the app. Fix: send the activity push token to the server and push on speed/caption events via apns-relay.
- Live Activities end after 8 hours; start a new one from the app.
- No app icon yet.
