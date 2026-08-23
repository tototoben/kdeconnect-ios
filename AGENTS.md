# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project context

- This is the `station-mode` fork of KDE/kdeconnect-ios. We are porting the
  "station handheld remote" feature from our Android fork to this iOS app.
- **The full implementation plan lives in [PLAN.md](PLAN.md)** — read it before
  doing any work. Work happens on the `station-mode` branch, pushed to
  `fork` (`tototoben/kdeconnect-ios`).
- The Android reference implementation is checked out at `../kdeconnect-android`
  (relative to this repo). Key files for the port:
  - `src/main/java/org/kde/kdeconnect/plugins/mousepad/MousePadActivity.java`
    (YES/NO key sequences, MQTT lifecycle, feedback handling)
  - `src/main/java/org/kde/kdeconnect/plugins/mousepad/StationMqttClient.java`
    (authoritative MQTT wire contract: topics, payloads, QoS, validation)
  - `src/main/java/org/kde/kdeconnect/plugins/mousepad/VisitorTracker.java`
    (face-tracking state machine constants: debounce windows, EMA, distance buckets)
  - Port these behaviors verbatim unless the plan says otherwise.

## Building and verification

The Xcode project is at `KDE Connect/KDE Connect.xcodeproj`; shared scheme is
`KDE Connect`. After code changes:

```sh
# Build (iOS Simulator)
xcodebuild build -project "KDE Connect/KDE Connect.xcodeproj" \
  -scheme "KDE Connect" -destination "generic/platform=iOS Simulator"

# Lint
swiftlint
```

### XcodeBuildMCP (optional but recommended)

For implementation and testing we can use
[XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP) — an MCP server +
CLI wrapping xcodebuild, simulators, device log capture, and UI automation,
which is convenient for agent-driven build/run/test loops.

```sh
# Install (either)
brew install xcodebuildmcp        # Homebrew
npm install -g xcodebuildmcp@latest

# Use as CLI, e.g.:
xcodebuildmcp simulator build --scheme "KDE Connect" \
  --project-path "./KDE Connect/KDE Connect.xcodeproj"
xcodebuildmcp tools   # list everything else it can do

# Or expose as an MCP server to your client:
xcodebuildmcp mcp
```

If available, prefer it over raw `xcodebuild` invocations for building,
launching on a simulator, capturing logs, and driving UI during manual-test
checklist items from PLAN.md Phase 6.
