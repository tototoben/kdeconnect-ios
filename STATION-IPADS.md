# Installing the station iPad build

This fork’s launch UI is `KeyboardOnlyView` (ice keyboard, YES/NO, slider).
Pushing `origin/master` does **not** update the three venue iPads. Sideload
from Xcode after every UI change.

Full room procedure (gitlinks, kiosk restart, MQTT):
`docs/IPAD-STATION-REMOTE.md` in the parent
`house-of-negotiated-selves` repo.

## Build onto a physical iPad

1. Plug in the iPad 6th gen, unlock, trust the computer.
2. Open `KDE Connect/KDE Connect.xcodeproj`.
3. Scheme **KDE Connect** → that iPad (not a Simulator).
4. Development-team signing.
5. Run. Bundle id `org.kde.kdeconnect` is overwritten in place.

Do **not** commit a local SwiftLint package skip in `project.pbxproj`. That
is only a Simulator convenience.

## Per-iPad settings

Gear (top-right) while Guided Access is off:

- **This iPad's station** — Station I / II / III (`1` / `2` / `3`). One iPad
  per kiosk; it does not follow whichever browser tab is open.
- **Broker URI** — `tcp://192.168.88.191:1883` on the venue LAN (Simulator
  defaults to `tcp://127.0.0.1:1883`).
- Pair KDE Connect with that station’s Pi (keyboard / mouse-pad plugin).
- Guided Access for show mode.

The kiosk tells this app what to show over MQTT `keyboard_focus`
(`text` / `numeric` / `yesno` / `choice` / `scale` / `hidden`). If the
layout never changes, the kiosk `ui/` checkout is stale or the station
bridge was not restarted.
