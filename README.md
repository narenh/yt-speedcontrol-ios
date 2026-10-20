# Canopy Control

iOS 26 app for [yt-speedcontrol](https://github.com/narenh/yt-speedcontrol). Sign in with your Canopy Account, pair your TVs, and control YouTube's playback speed (1, 1.25, 1.5, 1.75, 2×) and captions from the app or from a Live Activity on the Lock Screen and in the Dynamic Island.

## Build

```
brew install xcodegen
xcodegen generate
open CanopyControl.xcodeproj
```

The Xcode project and Info.plists are generated, so edit `project.yml` rather than the project.

| | |
|---|---|
| App | `com.canopysf.CanopyControl` ("Canopy Control") |
| Live Activity extension | `com.canopysf.CanopyControl.Widget` |
| Team | `UC3Y84QJ83` |

The app target has the Associated Domains entitlement for passkeys, `webcredentials:canopysf.com` (`App/CanopyControl.entitlements`), in every build. Not `?mode=developer`: iOS ignores that entry unless Settings > Developer > Associated Domains Development is on, which left Debug builds with no association.

### Passkeys need the association file

`https://canopysf.com/.well-known/apple-app-site-association` must list `UC3Y84QJ83.com.canopysf.CanopyControl` under `webcredentials.apps`, next to Canopy Events:

```json
{"webcredentials": {"apps": ["UC3Y84QJ83.com.canopysf.CanopyEvents", "UC3Y84QJ83.com.canopysf.CanopyControl"]}}
```

Until that's served, iOS refuses to use `canopysf.com` passkeys in this app, so signing in fails (both "Sign in with passkey" and the passkey step after an email code). Apple's CDN can take a day or more to pick up a change; Debug builds skip it.

## Use

1. **Sign in** with your Canopy Account: **Sign in with passkey**, or **Email me a code** (then save a passkey on this phone). The app doesn't create accounts: an email with no Canopy Account is sent to [account.canopysf.com](https://account.canopysf.com) to make one first.
2. **Pair a TV** from the ⋯ menu: on the TV, YouTube → Settings → Link with TV code, then type the code or tap **Scan code** to read it with the camera. Each person has their own TVs (up to 10).
3. Pick a TV from the switcher at the top left. The speed buttons set the speed (captions on above 1×, off at 1×); the captions button toggles captions.
4. **Start Live Activity** puts the same controls on the Lock Screen and in the Dynamic Island for the selected TV. Switching TVs in the app switches the Live Activity too.

The ⋯ menu also has **Remove this TV** and **Sign out**.

## How it works

- **Sign-in** uses the Canopy Account native API (`https://account.canopysf.com/api/native/v1`, documented in canopy-account-service's `docs/native-api.md`): `App/CanopyAccount.swift` is the client, `App/Passkeys.swift` wraps `ASAuthorizationController` in async/await and converts WebAuthn JSON to and from bytes, `App/AppSession.swift` runs the flows.
- **The token** is a Keychain generic password (`com.canopysf.CanopyControl.canopyToken`, `AfterFirstUnlockThisDeviceOnly`; `Shared/TokenStore.swift`). It's deleted on the first launch after an install, on sign-out, on a `401 signed_out` from the account service, and on any `401` from the speed server. No cookies are kept.
- **The speed server** is `https://ytspeed.canopysf.com` (`Shared/SpeedAPI.swift`); every request sends `Authorization: Bearer <token>`. A `403 email_unverified` shows a banner pointing to account.canopysf.com.
- The app refreshes the TV list on appear, on pull to refresh, and every 5 s while it's open, so changes made from the TV remote show up.
- **The Live Activity** (`Shared/SpeedActivity.swift`, `Widget/SpeedLiveActivity.swift`): at most one, showing the selected TV. The TV's id and name are in the content state, so switching TVs updates it in place. `Shared/` is compiled into both targets; the system runs the `LiveActivityIntent`s in the app's process, so they read the token from the app's Keychain and call the server directly. A `401` in an intent signs the app out and ends the activity.
- **Scan code** (`App/PairSheet.swift`) uses VisionKit's `DataScannerViewController` (text recognition) and stops at the first 12-digit code, allowing spaces or dashes between digits. It fills the field without pairing, so you can check it and tap Pair. The button only appears where the scanner is supported and available; typing the code always works.

## Limitations / next

- No push updates: changes made from the TV remote show up on the Live Activity only after your next tap or while the app is open. Fix: send the activity push token to the server and push on speed/caption events via apns-relay.
- Live Activities end after 8 hours; start a new one from the app.
- No app icon yet.
