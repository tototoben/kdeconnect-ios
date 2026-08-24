# Station Mode — Work State

Last updated: 2026-08-24

## Branch
`station-mode` on `fork/station-mode` (tototoben/kdeconnect-ios)

## Completed phases

### Phase 1 — Settings foundation (done, committed)
- `KdeConnectSettings.swift`: added `stationBrokerUri`, `stationId`,
  `stationTargetDeviceId`, `launchIntoStationMode`, `stationMqttDebug` with
  UserDefaults persistence and defaults registration
- `SettingsView.swift`: Station section with broker URI TextField, station ID
  Picker, launch toggle, MQTT debug toggle
- Dev convenience: `directIPs` default set to `["192.168.88.193"]` — **remove
  before fork push**

### Phase 2 — MQTT client (done, committed)
- Added CocoaMQTT 2.4.0 SPM package to project.pbxproj
- `Station/StationMqttClient.swift`: CocoaMQTT wrapper porting Android wire
  contract verbatim
  - Client ID `ios-remote-<UUID>`, clean session, QoS 1, auto-reconnect
  - Subscribes `station/<id>/ui/control` on connect and reconnect
  - Publishes `{ts, src:"ios-remote", event, ...}` to `station/<id>/ui/event`
  - Validates control messages require `ts`, `src`, `action`
  - `StationEvent` enum: yes, no, visitor_entered, visitor_distance_changed,
    visitor_approached, visitor_left
  - `StationDistance` enum: near, mid, far
- `Station/StationRemoteView.swift` MQTT wiring:
  - `MqttCoordinator` class bridges `StationMqttListener` to SwiftUI view
  - Connects on `onAppear`/`.active`, disconnects on `onDisappear`/`.background`
  - YES/NO buttons publish `yes`/`no` events before sending key sequences
  - `handleControlMessage`: reset, set_ui (labels ≤32 chars, enabled flags),
    feedback (vibrate clamped 0-1000ms, beep, pulse animation)
  - MQTT debug overlay: scrollable monospaced log shown when
    `stationMqttDebug` is on; logs connect/disconnect, → published, ← received

### Phase 4 (partial) — StationRemoteView (done, committed)
- Full-screen black kiosk view, hidden status bar and nav bar
- Trackpad surface (TwoFingerTapView) with drag, tap, double-tap, long-press,
  two-finger tap
- YES/NO buttons sending key sequences via RemoteInput
- Device auto-selection from connected devices with mousepad plugin
- Gear icon → MainTabView fullScreenCover
- Launch routing in KDE_Connect_App based on `launchIntoStationMode`
- TwoFingerTapView: replaced instruction text with hand.tap SF Symbol icon

### mDNS discovery fix (done, committed)
- `LanLinkProvider.m`: unicast directIPs before broadcast
- `MdnsDiscovery.swift`: NetService resolution + direct NWConnection instead
  of bonjour endpoint (fixes NECP flow rejection on physical iPad)
- `DnsResolver` retained in `MDNSDiscovery.activeResolvers`

## Not yet started

### Phase 3 — Visitor tracking
- `Station/VisitorTracker.swift` — front camera, Vision face detection, state
  machine (ENTER_STABLE_MS=500, LEAVE_STABLE_MS=1000, DISTANCE_STABLE_MS=300,
  EMA α=0.32, distance buckets)
- `Station/VisitorDotOverlay.swift` — SwiftUI overlay
- `NSCameraUsageDescription` in Info.plist
- Camera permission via `AVCaptureDevice.requestAccess(for: .video)`

### Phase 5 — App integration & fork publishing
- Register all new files in project.pbxproj (StationRemoteView and
  StationMqttClient already registered)
- Pin CocoaMQTT package (already added)
- Create fork `tototoben/kdeconnect-ios`, add remote, push work branch
- **Remove dev default `directIPs: ["192.168.88.193"]` before pushing**

### Phase 6 — Verification
- Build all targets for iOS Simulator
- SwiftLint
- Manual contract test against real broker
- Camera permission denied path
- Broker unreachable / reconnect
- Background/foreground cycles

## Build environment notes
- Xcode SDK: iOS 26.5 (simulator runtime 26.5 is installed)
- Also available: iOS 17.2, iOS 26.0 simulator runtimes
- Physical iPad (6th gen) used for testing, paired with Mac running KDE
  Connect from App Store
- Mac local IP: 192.168.88.193
- MQTT broker: 192.168.88.198:1883 (central component in
  ../house-of-negotiated-selves/components/central)
- Build command that works:
  ```
  xcodebuild build -project "KDE Connect/KDE Connect.xcodeproj" \
    -scheme "KDE Connect" \
    -destination "platform=iOS Simulator,name=iPad (10th generation),OS=17.2"
  ```
- If Xcode PIF session error: kill xcodebuild/Xcode processes, clear
  DerivedData, relaunch Xcode

## Files modified (not yet committed since last commit)
- `KdeConnectSettings.swift` — added `stationMqttDebug` setting
- `SettingsView.swift` — added MQTT debug toggle
- `Station/StationRemoteView.swift` — added MQTT debug overlay, log callback
  in MqttCoordinator

## Last commit
`79bcc2e` — "Add station mode settings, kiosk remote view, and fix mDNS
discovery"
