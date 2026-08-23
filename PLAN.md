# Station Mode for kdeconnect-ios

Plan to port the "station handheld remote" changes from our Android fork
(`tototoben/kdeconnect-android`) to this iOS app. On Android, MousePadActivity was
turned into a kiosk station remote: immersive black touchpad, YES/NO buttons typing
key sequences over KDE Connect, an MQTT control/event channel, front-camera visitor
tracking, a dot overlay, and remote-triggered feedback (vibrate/beep/pulse).

Reference diff: Android fork vs upstream (station MQTT contract, VisitorTracker,
VisitorDotView, YES/NO buttons, immersive layout).

## Target repository

Work lands in a personal GitHub fork, mirroring how the Android project is managed:

- Upstream: `https://github.com/KDE/kdeconnect-ios` (current `origin`)
- Fork: `https://github.com/tototoben/kdeconnect-ios` (**does not exist yet** — create
  via `gh repo fork KDE/kdeconnect-ios --clone=false`, then add as remote `fork` and
  push feature branches there)

## Platform mapping

| Android | iOS |
|---|---|
| MousePadActivity | New `StationRemoteView` (default view of the app) |
| MousePadPlugin.sendText / sendSelect | Existing `RemoteInput.sendKeyPress(_:)` ("key") / `sendSingleClick()` ("singleclick") |
| CameraX + ML Kit face detection | AVFoundation `AVCaptureSession` + Vision `VNDetectFaceRectanglesRequest` (built-in, zero deps) |
| Paho MQTT | CocoaMQTT via SPM |
| ListPreference station ID | `@Published` fields on `KdeConnectSettings` + Pickers in SettingsView |
| ToneGenerator / Vibrator / pulse animation | `AudioServicesPlaySystemSound` (extend SystemSound.swift) / CoreHaptics for arbitrary durations / SwiftUI `scaleEffect` pulse |
| VisitorDotView custom View | SwiftUI overlay view |

## Design decisions

1. **New view, not in-place rework.** Normal `RemoteInputView` stays untouched.
   `StationRemoteView` becomes the default launch view of the iOS app, with a gear
   affordance presenting `MainTabView` in a `fullScreenCover` as escape hatch
   (still needed for pairing new devices and settings). Mac build untouched.
2. **Broker address is a setting**, not hardcoded like Android:
   `stationBrokerUri`, default `tcp://192.168.88.198:1883`.
3. Device targeting: station view has no incoming `deviceId`. Persist
   `stationTargetDeviceId`; auto-select if paired + connected + mousepad plugin
   enabled; otherwise show inline picker of qualifying devices.
4. App already sets `UIApplication.shared.isIdleTimerDisabled = true` at launch —
   kiosk-friendly, no extra work.

## New settings (`KdeConnectSettings.swift` + "Station" section in SettingsView)

- `stationBrokerUri`: String, default `tcp://192.168.88.198:1883`
- `stationId`: String, default `"1"` (Stations 1–3 picker, like Android's ListPreference)
- `stationTargetDeviceId`: String?, persisted last-used remote
- `launchIntoStationMode`: Bool, default `true` — safety switch for normal launch

## Phases

### Phase 1 — Settings foundation
Add the four fields with UserDefaults persistence + defaults registration; add
"Station" section in SettingsView (broker URI TextField, station Picker, launch
toggle, target device row).

### Phase 2 — MQTT client (`Station/StationMqttClient.swift`)
Add CocoaMQTT SPM package. Port the exact wire contract from Android:

- Client id `ios-remote-<UUID>`, clean session, QoS 1, automatic reconnect
- Subscribe `station/<id>/ui/control` after connect *and* after reconnects
- Control messages must contain `ts`, `src`, `action`; actions `set_ui`
  (`yes`, `no`, `yesEnabled`, `noEnabled`), `reset`, optional `feedback` object
  (`vibrateMs`, `sound: "beep"`, `animation: "pulse"`)
- Publish `{ts, src, event, …}` JSON to `station/<id>/ui/event`
  (events: `yes`, `no`, `visitor_entered`, `visitor_distance_changed`,
  `visitor_approached`, `visitor_left`)
- Recreate client when broker URI or station ID changes

### Phase 3 — Visitor tracking (`Station/VisitorTracker.swift`, `Station/VisitorDotOverlay.swift`)
Front camera, low-res (~320×240), keep-only-latest, ≤10 inferences/sec,
frame-in-flight guard. Vision face rectangles request. Port state machine verbatim:

- ENTER_STABLE_MS = 500, LEAVE_STABLE_MS = 1000, DISTANCE_STABLE_MS = 300
- EMA α = 0.32 on normalized position
- Distance buckets by max bounding-box fraction: ≥0.45 NEAR (≤0.75 m),
  ≥0.22 MID (0.75–1.5 m), else FAR
- Mirrored X so entry side matches what the visitor sees; verify empirically that
  Vision coordinates need the same `1 - x/w` math as ML Kit
- Listener protocol: entered(fromLeft, distance) / distanceChanged /
  approached / left / position(x, y, distance)
- Privacy stance preserved: derived face position only; no preview, frames never
  stored or sent anywhere
- Add `NSCameraUsageDescription` to Info.plist; runtime permission via
  `AVCaptureDevice.requestAccess(for: .video)`

### Phase 4 — StationRemoteView (`Station/StationRemoteView.swift`)
- Black immersive screen: hidden nav bar + status bar using iOS 14-safe APIs
  (min deployment target is 14.0; avoid iOS 16-only modifiers)
- YES / NO buttons → key sequences `Y,E,S,+singleclick` / `N,O,+singleclick` through
  existing `RemoteInput` plugin + publish `yes`/`no` MQTT events
- Visitor dot overlay + approach feedback (pulse both buttons + haptic + beep)
- Control message handling: `reset`, `set_ui` labels (≤32 chars)/enabled flags,
  `feedback` (clamp `vibrateMs` to 0–1000, beep, pulse animation)
- Device auto-selection logic per design decision 3
- Lifecycle wiring: `onAppear`/`scenePhase` ↔ mqtt connect/disconnect +
  tracker start/stop (with short render delay before camera warm-up, as on Android)

### Phase 5 — App integration & fork publishing
- `KDE_Connect_App.swift`: iOS WindowGroup shows `StationRemoteView` when
  `launchIntoStationMode`; gear presents `MainTabView` fullScreenCover
- Register new files in `project.pbxproj`; pin CocoaMQTT package
- Create fork `tototoben/kdeconnect-ios`, add remote, push work branch

### Phase 6 — Verification
- Build all targets for iOS Simulator; run SwiftLint (repo `.swiftlint.yml`)
- Manual contract test against real broker with `mosquitto_pub`/`mosquitto_sub`:
  - Press YES/NO → events on `station/<id>/ui/event` with correct payload
  - Send each control action (`set_ui`, `reset`, feedback variants) → UI reacts
  - Camera permission denied path (graceful, no tracking, no crash)
  - Broker unreachable at start → auto-recover; broker drops mid-session → reconnect resubscribes
  - Remote device disconnects mid-session → graceful handling
  - Change station ID / broker URI while connected → clean reconnect
  - Background/foreground cycles → tracking stops/resumes, camera released

## File summary

```
KDE Connect/KDE Connect/
├── Station/
│   ├── StationRemoteView.swift      (new)
│   ├── StationMqttClient.swift      (new)
│   ├── VisitorTracker.swift         (new)
│   └── VisitorDotOverlay.swift      (new)
├── Swift Backend/KdeConnectSettings.swift   (add 4 settings)
├── Views/Settings/SettingsView.swift        (add Station section)
├── Views/Top Level/KDE_Connect_App.swift    (launch routing)
└── Info.plist                               (NSCameraUsageDescription)
```
