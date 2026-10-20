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

The app target has Push Notifications (`aps-environment`, for Live Activity pushes) and the Associated Domains entitlement for passkeys, `webcredentials:canopysf.com` (`App/CanopyControl.entitlements`), in every build. Automatic signing (`-allowProvisioningUpdates` from the command line) adds Push Notifications to the App ID. Not `?mode=developer`: iOS ignores that entry unless Settings > Developer > Associated Domains Development is on, which left Debug builds with no association.

### Passkeys need the association file

`https://canopysf.com/.well-known/apple-app-site-association` must list `UC3Y84QJ83.com.canopysf.CanopyControl` under `webcredentials.apps`, next to Canopy Events:

```json
{"webcredentials": {"apps": ["UC3Y84QJ83.com.canopysf.CanopyEvents", "UC3Y84QJ83.com.canopysf.CanopyControl"]}}
```

Until that's served, iOS refuses to use `canopysf.com` passkeys in this app, so signing in fails (both "Sign in with passkey" and the passkey step after an email code). Apple's CDN can take a day or more to pick up a change; Debug builds skip it.

## Use

1. **Sign in** with your Canopy Account: **Sign in with passkey**, or **Email me a code** (then save a passkey on this phone). The app doesn't create accounts: an email with no Canopy Account is sent to [account.canopysf.com](https://account.canopysf.com) to make one first.
2. **Pair a TV** from the ⋯ menu: on the TV, YouTube → Settings → Link with TV code, then type the code or tap **Scan code** to read it with the camera. Each person has their own TVs (up to 10).
3. Pick a TV from the switcher under the title. The speed buttons set the speed (captions on above 1×, off at 1×); the captions button toggles captions.
4. **The Live Activity** puts the same controls on the Lock Screen and in the Dynamic Island. It starts by itself when one of your TVs starts playing, even with the app closed, on every iPhone you're signed in on; the TV that started playing last gets it. **Start Live Activity** (and **End Live Activity**) in the ⋯ menu starts it for the selected TV. Switching TVs in the app switches the Live Activity too, and changes made from the TV remote show up on it.

**Skip sponsors** (below the captions button) turns sponsor and ad skipping on or off for the selected TV (`PATCH /devices/{id}` with `skip_sponsors`). The server does the skipping with SponsorBlock, using the server owner's categories. The toggle only shows when the server sends `skip_sponsors` for that TV; it's absent for people who may not use it and when the server has it off. It flips right away, and an error puts it back and shows the server's `detail`. The 5 s refresh leaves it alone while a change is in flight. It isn't on the Live Activity.

The ⋯ menu also has **Rename TV…** (Save, or **Use TV's name** to go back to the name the TV reports; `PATCH /devices/{id}`), **Remove this TV** and **Sign out**.

## How it works

- **Sign-in** uses the Canopy Account native API (`https://account.canopysf.com/api/native/v1`, documented in canopy-account-service's `docs/native-api.md`): `App/CanopyAccount.swift` is the client, `App/Passkeys.swift` wraps `ASAuthorizationController` in async/await and converts WebAuthn JSON to and from bytes, `App/AppSession.swift` runs the flows.
- **The token** is a Keychain generic password (`com.canopysf.CanopyControl.canopyToken`, `AfterFirstUnlockThisDeviceOnly`; `Shared/TokenStore.swift`). It's deleted on the first launch after an install, on sign-out, on a `401 signed_out` from the account service, and on any `401` from the speed server. No cookies are kept.
- **The speed server** is `https://ytspeed.canopysf.com` (`Shared/SpeedAPI.swift`); every request sends `Authorization: Bearer <token>`. A `403 email_unverified` shows a banner pointing to account.canopysf.com.
- The app refreshes the TV list on appear, on pull to refresh, and every 5 s while it's open, so changes made from the TV remote show up in the app.
- **The Live Activity** (`Shared/SpeedActivity.swift`, `Widget/SpeedLiveActivity.swift`): at most one, showing the selected TV. The TV's id and name are in the content state, so switching TVs updates it in place. `Shared/` is compiled into both targets; the system runs the `LiveActivityIntent`s in the app's process, so they read the token from the app's Keychain and call the server directly. A `401` in an intent signs the app out and ends the activity.
- **Push** (`App/ActivityPush.swift`): the app registers itself with the speed server as an install, `PUT /installs/{install_id}` (a UUID kept in UserDefaults, new after signing out) with `environment` (`sandbox` in Debug builds, `production` otherwise) and:
  - `push_to_start_token`: from `Activity<SpeedAttributes>.pushToStartTokenUpdates`, sent while signed in. The server uses it to start the activity when one of the person's TVs starts playing.
  - `activity: {token, device_id}`: the current activity's push token (activities start with `pushType: .token`) and the TV it shows, sent again whenever that TV changes. The server pushes that TV's speed, captions, connection and name to it, starting right away. `activity: null` when it ends.
  - Pushes use attributes type `SpeedAttributes` with `{}` attributes and content-state keys `deviceId, deviceName, speed, captions, connected`, so `SpeedAttributes.ContentState` mustn't be renamed.
  - The observers start in the App's init, because the system launches the app in the background when a push starts an activity. A new activity (`Activity<SpeedAttributes>.activityUpdates`, or one found at launch) becomes the current one: the others end, its token goes up, and the app selects its TV. The in-app button goes through the same path.
  - Everything is sent again on each foreground. Failed PUTs are logged (`com.canopysf.CanopyControl`, category `push`) and otherwise ignored.
  - **Sign out** sends `DELETE /installs/{install_id}` and ends the activity before deleting the token.
- **Scan code** (`App/PairSheet.swift`) uses VisionKit's `DataScannerViewController` (text recognition) and stops at the first 12-digit code, allowing spaces or dashes between digits. It fills the field without pairing, so you can check it and tap Pair. The button only appears where the scanner is supported and available; typing the code always works.

## Limitations / next

- Live Activities end after 8 hours. The next time a TV starts playing, the server starts a new one; or start one from the app.
- After a `401` signs the app out (rather than **Sign out**), the install isn't deleted on the server: there's no token left to do it with. The app ends any activity a push starts while it's signed out.
- No app icon yet.
