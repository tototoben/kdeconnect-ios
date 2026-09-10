/*
 * SPDX-FileCopyrightText: 2026 station-mode contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import SwiftUI
import UIKit

enum ScaleRatingMapping {
    static func value(for rating: Int) -> Double {
        let clamped = min(10, max(1, rating))
        return Double(clamped - 1) / 9.0
    }

    static func rating(for value: Double) -> Int {
        guard value.isFinite else { return 1 }
        let clamped = min(1.0, max(0.0, value))
        return min(10, max(1, Int((clamped * 9.0).rounded()) + 1))
    }
}

enum StationPrompt {
    static func normalized(_ prompt: String) -> String {
        prompt.caseInsensitiveCompare("waiting for your turn") == .orderedSame
            ? "WAITING FOR PREVIOUS STATION INPUT"
            : prompt
    }
}

struct KeyboardOnlyView: View {
    @ObservedObject private var settings = KdeConnectSettings.shared
    @ObservedObject private var devicesViewModel = connectedDevicesViewModel

    @State private var showingSettings: Bool = false
    @State private var modifiers: [RemoteInput.KeyModifier] = []
    @State private var isGuidedAccessActive: Bool = UIAccessibility.isGuidedAccessEnabled
    @State private var focusMode: InputFocusMode = .standard
    @State private var mqttCoordinator: MqttCoordinator?
    @State private var kioskLink: StationKioskLoopback?
    @State private var hasTyped: Bool = false
    @State private var flashProgress: CGFloat = 0
    @State private var iceBreath: Bool = false
    @State private var choiceLeft: String = "YES"
    @State private var choiceRight: String = "NO"
    @State private var sliderValue: Double = 0.5
    @State private var sliderLeft: String = "Not very"
    @State private var sliderRight: String = "Extremely"
    @State private var lastSentSlider: Double = -1
    @State private var sliderSeq: Int = 0
    @State private var focusPrompt: String = ""
    @State private var focusEpoch: Int = 0
    @State private var focusSignature: String = ""
    @State private var lastLocalSliderAt: Date?
    @State private var mqttLog: [String] = []
    @State private var lastMqttControl: String = ""
    @State private var introDiagnostics: String = ""

    /// True when Guided Access is active — all config/debug UI is hidden.
    private var isKiosk: Bool { isGuidedAccessActive }

    var body: some View {
        ZStack {
            IceAtmosphere(breathing: iceBreath, charged: hasTyped)

            Group {
                if focusMode == .standard {
                    StationKeyboardRootView(
                        onKey: { key in
                            markTyped()
                            sendKeyPress(key, [])
                        },
                        onDelete: {
                            sendSpecialKeyPress(.backspace)
                        },
                        onReturn: {
                            confirmEntry()
                        },
                        onSpace: {
                            markTyped()
                            sendKeyPress(" ", [])
                        },
                        onTab: {
                            sendSpecialKeyPress(.tab)
                        },
                        onModifierToggle: { modifier, isOn in
                            if isOn {
                                modifiers.append(modifier)
                            } else {
                                modifiers.removeAll { $0 == modifier }
                            }
                        },
                        scale: 1.22,
                        submitArmed: hasTyped,
                        showNumberRow: false
                    )
                } else if focusMode == .numeric {
                    StationKeyboardRootView(
                        onKey: { key in
                            markTyped()
                            sendKeyPress(key, [])
                        },
                        onDelete: {
                            sendSpecialKeyPress(.backspace)
                        },
                        onReturn: {
                            confirmEntry()
                        },
                        onSpace: {
                            markTyped()
                            sendKeyPress(" ", [])
                        },
                        onTab: {
                            sendSpecialKeyPress(.tab)
                        },
                        onModifierToggle: { modifier, isOn in
                            if isOn {
                                modifiers.append(modifier)
                            } else {
                                modifiers.removeAll { $0 == modifier }
                            }
                        },
                        scale: 1.22,
                        submitArmed: hasTyped,
                        showNumberRow: true,
                        numbersOnly: true
                    )
                } else if focusMode == .choice {
                    SplitChoiceView(
                        leftTitle: choiceLeft,
                        rightTitle: choiceRight,
                        onLeft: {
                            sendKeyPress("y", [])
                            triggerSubmitFlash()
                        },
                        onRight: {
                            sendKeyPress("n", [])
                            triggerSubmitFlash()
                        }
                    )
                } else if focusMode == .scale {
                    ScaleSliderFocusView(
                        leftTitle: sliderLeft,
                        rightTitle: sliderRight,
                        value: $sliderValue,
                        onChange: sendSlider,
                        onConfirm: confirmSlider
                    )
                } else if focusMode == .intro {
                    IntroFinishView {
                        mqttCoordinator?.publishRemoteOperator("finish_intro")
                    }
                }
            }
            .id(focusEpoch)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            IceSubmitFlash(progress: flashProgress)

            OperatorChordCorners(
                onPicker: {
                    mqttCoordinator?.publishRemoteOperator("picker")
                    sendKeyPress("p", [.alt, .shift])
                },
                onRestart: {
                    mqttCoordinator?.publishRemoteOperator("restart")
                    sendKeyPress("r", [.alt, .shift])
                }
            )

            VStack {
                HStack {
                    if settings.showConnectionDebug && !isKiosk {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("station \(settings.stationId)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.yellow.opacity(0.7))
                            Text("target: \(targetDeviceId ?? "nil")")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.yellow.opacity(0.7))
                            Text("connected: \(devicesViewModel.connectedDevices.count)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.yellow.opacity(0.7))
                        }
                    }
                    Spacer()
                    if !isKiosk {
                        Button(action: { showingSettings = true }, label: {
                            Image(systemName: "gearshape")
                                .font(.title2)
                                .foregroundColor(StationChrome.ice.opacity(0.55))
                                .padding(8)
                        })
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
                if !focusPrompt.isEmpty && focusMode != .hidden {
                    Text(focusPrompt.uppercased())
                        .font(StationChrome.labelFont(size: 14))
                        .foregroundColor(StationChrome.ice.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                }
                if !introDiagnostics.isEmpty {
                    Text(introDiagnostics)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(StationChrome.ice.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                }
                if settings.stationMqttDebug && !lastMqttControl.isEmpty {
                    Text(lastMqttControl)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.green.opacity(0.75))
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                        .padding(.top, 2)
                }
                Spacer()
            }
            .allowsHitTesting(!isKiosk)

            // Floating reset button at bottom-left
            if settings.showKeyboardControls && !isKiosk {
                VStack {
                    Spacer()
                    HStack {
                        Button(action: {
                            settings.resetKeyboardLayout()
                        }, label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(StationChrome.ice.opacity(0.45))
                                .padding(10)
                                .background(Color(white: 0.12))
                                .clipShape(Circle())
                        })
                        Spacer()
                    }
                    .padding(.bottom, 16)
                    .padding(.leading, 16)
                }
            }

            // Edge gesture deferring controller (makes system defer edge swipes to app)
            if isKiosk {
                EdgeGestureDeferrer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
        .statusBarHidden()
        .navigationBarHidden(true)
        .modifier(SystemOverlayHidden())
        .fullScreenCover(isPresented: $showingSettings) {
            MainTabView()
        }
        .onAppear {
            forceLandscapeOrientation()
            UIApplication.shared.isIdleTimerDisabled = true
            isGuidedAccessActive = UIAccessibility.isGuidedAccessEnabled
            connectMqtt()
            iceBreath = true
        }
        .onChange(of: settings.stationId) { _ in
            connectMqtt()
        }
        .onChange(of: settings.stationBrokerUri) { _ in
            connectMqtt()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            mqttCoordinator?.disconnect()
            mqttCoordinator = nil
            kioskLink?.stop()
            kioskLink = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.guidedAccessStatusDidChangeNotification)) { _ in
            isGuidedAccessActive = UIAccessibility.isGuidedAccessEnabled
        }
    }

    // MARK: - Device targeting

    private var targetDeviceId: String? {
        let id = settings.stationTargetDeviceId
        if id != nil
            && ConnectedDevicesViewModel.isDeviceCurrentlyPairedAndConnected(id!)
            && backgroundService._devices[id!]?._pluginsEnableStatus[.mousePadRequest] != nil {
            return id
        }
        return autoSelectDevice()
    }

    private func autoSelectDevice() -> String? {
        for (deviceId, _) in devicesViewModel.connectedDevices {
            if backgroundService._devices[deviceId]?._pluginsEnableStatus[.mousePadRequest] != nil {
                settings.stationTargetDeviceId = deviceId
                return deviceId
            }
        }
        return nil
    }

    // MARK: - Key sending

    private func sendKeyPress(_ keys: String, _ mods: [RemoteInput.KeyModifier]) {
        var modsToUse = mods.isEmpty ? modifiers : mods
        // Number-row digits must stay 1–0 even if Alt/Shift is still latched
        // from the picker chord (Shift+1 would otherwise become "!").
        if keys.count == 1, keys.allSatisfy({ $0.isNumber }) {
            modsToUse = []
        }
        kioskLink?.sendKey(
            keys,
            alt: modsToUse.contains(.alt),
            shift: modsToUse.contains(.shift)
        )
        mqttCoordinator?.publishRemoteKey(
            key: keys,
            alt: modsToUse.contains(.alt),
            shift: modsToUse.contains(.shift)
        )
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendKeyPress(keys, modsToUse)
        modifiers.removeAll()
    }

    private func sendSpecialKeyPress(_ key: RemoteInput.SpecialKey) {
        let special: String?
        switch key {
        case .return: special = "return"
        case .backspace: special = "backspace"
        case .tab: special = "tab"
        default: special = nil
        }
        switch key {
        case .return: kioskLink?.sendSpecial("return")
        case .backspace: kioskLink?.sendSpecial("backspace")
        case .tab: kioskLink?.sendSpecial("tab")
        default: break
        }
        if let special {
            mqttCoordinator?.publishRemoteKey(special: special)
        }
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendSpecialKeyPress(key)
        modifiers.removeAll()
    }

    private func sendSlider(_ value: Double) {
        let clamped = min(1, max(0, value))
        sliderValue = clamped
        guard abs(clamped - lastSentSlider) >= 0.008 || lastSentSlider < 0 else { return }
        lastSentSlider = clamped
        sliderSeq += 1
        lastLocalSliderAt = Date()
        kioskLink?.sendSlider(clamped, seq: sliderSeq)
        mqttCoordinator?.publishRemoteSlider(value: clamped, seq: sliderSeq)
    }

    private func confirmSlider() {
        lastSentSlider = sliderValue
        sliderSeq += 1
        lastLocalSliderAt = Date()
        kioskLink?.sendSlider(sliderValue, seq: sliderSeq)
        mqttCoordinator?.publishRemoteSlider(value: sliderValue, seq: sliderSeq, confirm: true)
        if kioskLink != nil {
            kioskLink?.sendSpecial("confirm")
        } else if let deviceId = targetDeviceId,
                  let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput {
            remoteInput.sendSpecialKeyPress(.return)
        }
        triggerSubmitFlash()
    }

    private func markTyped() {
        hasTyped = true
    }

    private func confirmEntry() {
        sendSpecialKeyPress(.return)
        guard hasTyped else { return }
        hasTyped = false
        triggerSubmitFlash()
    }

    private func triggerSubmitFlash() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        flashProgress = 0
        withAnimation(.easeOut(duration: 0.06)) {
            flashProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            withAnimation(.easeOut(duration: 0.22)) {
                flashProgress = 0
            }
        }
    }

    // MARK: - MQTT

    private func connectMqtt() {
        mqttCoordinator?.disconnect()
        mqttCoordinator = nil
        kioskLink?.stop()
        kioskLink = nil
        let coordinator = MqttCoordinator(
            brokerUri: settings.stationBrokerUri,
            stationId: settings.stationId,
            onControl: { control in
                handleControlMessage(control)
            },
            onLog: { line in
                guard settings.stationMqttDebug else { return }
                DispatchQueue.main.async {
                    if line.hasPrefix("<-") {
                        lastMqttControl = line
                    }
                    mqttLog.append(line)
                    if mqttLog.count > 40 {
                        mqttLog.removeFirst(mqttLog.count - 40)
                    }
                }
            }
        )
        mqttCoordinator = coordinator
        coordinator.connect()
        if let base = StationKioskLoopback.baseURL(from: settings.stationBrokerUri) {
            let link = StationKioskLoopback(
                baseURL: base,
                stationId: settings.stationId,
                onControl: { control in
                    handleControlMessage(control)
                }
            )
            kioskLink = link
            link.start()
        }
    }

    private func applyChoiceLabels(from control: [String: Any], defaultsToYesNo: Bool) {
        let fallbackLeft = defaultsToYesNo ? "YES" : choiceLeft
        let fallbackRight = defaultsToYesNo ? "NO" : choiceRight
        if let left = control["left"] as? String, !left.isEmpty {
            choiceLeft = left
        } else {
            choiceLeft = fallbackLeft
        }
        if let right = control["right"] as? String, !right.isEmpty {
            choiceRight = right
        } else {
            choiceRight = fallbackRight
        }
    }

    private func applySliderLabels(from control: [String: Any]) {
        if let left = control["left"] as? String, !left.isEmpty {
            sliderLeft = left
        } else {
            sliderLeft = "Not very"
        }
        if let right = control["right"] as? String, !right.isEmpty {
            sliderRight = right
        } else {
            sliderRight = "Extremely"
        }
    }

    private func incomingSliderValue(from control: [String: Any]) -> Double? {
        let raw = control["value"]
        let number: Double?
        if let n = raw as? NSNumber {
            number = n.doubleValue
        } else if let n = raw as? Double {
            number = n
        } else if let s = raw as? String {
            number = Double(s)
        } else {
            number = nil
        }
        guard let number, number.isFinite else { return nil }
        return min(1, max(0, number))
    }

    private func handleControlMessage(_ control: [String: Any]) {
        let action = control["action"] as? String ?? ""
        let prompt = StationPrompt.normalized(
            (control["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
        let signature = Self.focusSignature(action: action, prompt: prompt, control: control)
        DispatchQueue.main.async {
            bumpFocusEpoch(from: control, signature: signature)
            switch action {
            case "yesNoFocused", "choiceFocused":
                applyChoiceLabels(from: control, defaultsToYesNo: action == "yesNoFocused")
                focusMode = .choice
                focusPrompt = prompt
                hasTyped = false
            case "yesNoBlur", "textFocused", "numericBlur":
                focusMode = .standard
                focusPrompt = prompt
                hasTyped = false
            case "numericFocused":
                focusMode = .numeric
                focusPrompt = prompt
                hasTyped = false
            case "scaleFocused":
                applySliderLabels(from: control)
                let entering = focusMode != .scale
                let recentlySent = lastLocalSliderAt.map { Date().timeIntervalSince($0) < 0.8 } ?? false
                if let incoming = incomingSliderValue(from: control), entering || !recentlySent {
                    sliderValue = incoming
                    lastSentSlider = sliderValue
                } else if entering {
                    sliderValue = 0.5
                    lastSentSlider = sliderValue
                }
                focusMode = .scale
                focusPrompt = prompt
                hasTyped = true
                introDiagnostics = ""
            case "introRecording":
                focusMode = .intro
                focusPrompt = prompt
                hasTyped = false
                introDiagnostics = ""
            case "introDiagnostics":
                focusMode = .hidden
                focusPrompt = ""
                hasTyped = false
                introDiagnostics = formatIntroDiagnostics(control["diagnostics"])
            case "keyboardHidden":
                focusMode = .hidden
                focusPrompt = ""
                hasTyped = false
            default:
                break
            }
        }
    }

    private func formatIntroDiagnostics(_ raw: Any?) -> String {
        guard let diagnostics = raw as? [String: Any] else {
            return "INTRO CAPTURE COMPLETE"
        }
        let chars = (diagnostics["capturedChars"] as? NSNumber)?.intValue
            ?? (diagnostics["chars"] as? NSNumber)?.intValue
            ?? 0
        let speech = (diagnostics["speechChars"] as? NSNumber)?.intValue ?? 0
        let whisper = (diagnostics["whisperChars"] as? NSNumber)?.intValue ?? 0
        let reason = (diagnostics["finishReason"] as? String ?? "timer").uppercased()
        return "CAPTURED \(chars) CHARS · SPEECH \(speech) · WHISPER \(whisper) · \(reason)"
    }

    /// What the remote actually displays for a focus message. The kiosk
    /// republishes the current focus on a timer with only `seq` moving, so the
    /// signature deliberately ignores `seq`/`ts` -- and `value`, which the
    /// kiosk streams while a slider moves.
    private static func focusSignature(
        action: String,
        prompt: String,
        control: [String: Any]
    ) -> String {
        let left = (control["left"] as? String) ?? ""
        let right = (control["right"] as? String) ?? ""
        return [action, left, right, prompt].joined(separator: "\u{1}")
    }

    /// Rebuild the focus view only when the displayed state changes.
    ///
    /// `focusEpoch` is the SwiftUI `.id()` of the whole focus view, so any
    /// change tears the view down and builds a fresh one. It used to track the
    /// kiosk's `seq`, which moves on every heartbeat republish (750 ms on the
    /// Station III build) -- the Yes/No buttons visibly flashed and a tap that
    /// spanned a rebuild was swallowed. Repeats of the same displayed state
    /// leave the epoch alone; a genuinely new question changes the signature.
    /// Two identical questions back to back therefore do not force a rebuild,
    /// which is fine: the switch below resets the per-question state anyway.
    private func bumpFocusEpoch(from control: [String: Any], signature: String) {
        guard signature != focusSignature else { return }
        focusSignature = signature
        if let seq = control["seq"] as? NSNumber {
            focusEpoch = seq.intValue
            return
        }
        if let seq = control["seq"] as? Int {
            focusEpoch = seq
            return
        }
        if let ts = control["ts"] as? NSNumber {
            focusEpoch = ts.intValue
            return
        }
        focusEpoch += 1
    }

    // MARK: - Orientation

    private func forceLandscapeOrientation() {
        if #available(iOS 16.0, *) {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                    ?? scenes.first(where: { $0.activationState == .foregroundInactive })
                    ?? scenes.first else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    forceLandscapeOrientation()
                }
                return
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

// MARK: - Input focus mode

enum InputFocusMode {
    case standard
    case numeric
    case choice
    case scale
    case intro
    case hidden
}

private struct IntroFinishView: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            StationHazeLabel(
                text: "INTRODUCTION IN PROGRESS",
                fontSize: 20,
                light: true,
                kerning: 2.2
            )
            FocusButton(
                title: "FINISH EARLY",
                width: 360,
                height: 92,
                isAccent: true,
                isArmed: true,
                action: onFinish
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

/// Invisible operator chords for when the letter keyboard is hidden
/// (YES/NO, slider). Long-press top-left restarts the station;
/// top-right opens the production picker. Same Alt+Shift+R / P the
/// kiosk listens for from the letter keyboard.
private struct OperatorChordCorners: View {
    let onPicker: () -> Void
    let onRestart: () -> Void

    var body: some View {
        VStack {
            HStack {
                OperatorChordHit(action: onRestart)
                Spacer()
                OperatorChordHit(action: onPicker)
            }
            Spacer()
        }
        .padding(.top, 2)
        .padding(.horizontal, 2)
        .allowsHitTesting(true)
    }
}

private struct OperatorChordHit: View {
    let action: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 56, height: 56)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.9) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                action()
            }
    }
}

// MARK: - Split choice (yes/no and this-or-that)

struct ScaleSliderFocusView: View {
    let leftTitle: String
    let rightTitle: String
    @Binding var value: Double
    let onChange: (Double) -> Void
    let onConfirm: () -> Void

    var body: some View {
        GeometryReader { geo in
            let confirmH = min(84, max(64, geo.size.height * 0.16))
            let innerW = max(geo.size.width - 72, 120)
            VStack(spacing: 28) {
                HStack {
                    StationHazeLabel(
                        text: leftTitle.uppercased(),
                        fontSize: 18,
                        light: true,
                        kerning: 2.4
                    )
                    Spacer()
                    StationHazeLabel(
                        text: rightTitle.uppercased(),
                        fontSize: 18,
                        light: true,
                        kerning: 2.4
                    )
                }
                ScaleRatingRow(value: $value, onChange: onChange)
                    .frame(height: min(112, geo.size.height * 0.34))
                FocusButton(
                    title: "CONFIRM",
                    width: innerW,
                    height: confirmH,
                    isAccent: true,
                    isArmed: true,
                    action: onConfirm
                )
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

private struct ScaleRatingRow: View {
    @Binding var value: Double
    let onChange: (Double) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 10)

    var body: some View {
        GeometryReader { geo in
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(1...10, id: \.self) { rating in
                    FocusButton(
                        title: "\(rating)",
                        width: max((geo.size.width - 72) / 10, 1),
                        height: min(82, geo.size.height),
                        isAccent: true,
                        isArmed: ScaleRatingMapping.rating(for: value) == rating
                    ) {
                        let next = ScaleRatingMapping.value(for: rating)
                        value = next
                        onChange(next)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

struct SplitChoiceView: View {
    let leftTitle: String
    let rightTitle: String
    let onLeft: () -> Void
    let onRight: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SplitPane(title: leftTitle, action: onLeft)
            Rectangle()
                .fill(StationChrome.ice.opacity(0.55))
                .frame(width: 1)
                .shadow(color: StationChrome.ice.opacity(0.45), radius: 6)
            SplitPane(title: rightTitle, action: onRight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

private struct SplitPane: View {
    let title: String
    let action: () -> Void

    @GestureState private var isPressed: Bool = false

    private var displayTitle: String { title.uppercased() }

    var body: some View {
        GeometryReader { geo in
            let fontSize = min(geo.size.width * (displayTitle.count > 8 ? 0.09 : 0.13), 58)
            ZStack {
                StationChrome.frost
                LinearGradient(
                    gradient: Gradient(colors: [
                        StationChrome.ice.opacity(isPressed ? 0.64 : 0.06),
                        StationChrome.ice.opacity(isPressed ? 0.28 : 0.0),
                        Color.clear,
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    gradient: Gradient(colors: [
                        StationChrome.ice.opacity(isPressed ? 0.22 : 0.08),
                        Color.clear,
                    ]),
                    center: .center,
                    startRadius: 8,
                    endRadius: max(geo.size.width, geo.size.height) * 0.55
                )
                StationIceGrain.overlay(opacity: isPressed ? 0.32 : 0.11)
                StationHazeLabel(
                    text: displayTitle,
                    fontSize: fontSize,
                    light: true,
                    kerning: fontSize * 0.12,
                    pressed: isPressed
                )
                .padding(.horizontal, 22)
            }
            .overlay(
                Rectangle()
                    .stroke(StationChrome.ice.opacity(isPressed ? 0.95 : 0.22), lineWidth: 1)
                    .padding(1)
            )
            .shadow(color: StationChrome.ice.opacity(isPressed ? 0.5 : 0), radius: isPressed ? 28 : 0)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.16), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        SoundManager.shared.play(.keyPress)
                        action()
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FocusButton: View {
    let title: String
    let width: CGFloat
    let height: CGFloat
    var isAccent: Bool = false
    var isArmed: Bool = false
    let action: () -> Void

    @GestureState private var isPressed: Bool = false

    var body: some View {
        label
            .background(background)
            .overlay(StationIceGrain.overlay(opacity: isPressed ? 0.3 : 0.14))
            .overlay(border)
            .shadow(
                color: StationChrome.ice.opacity(glowOpacity),
                radius: glowRadius
            )
            .animation(.easeOut(duration: 0.14), value: isPressed)
            .animation(.easeInOut(duration: 0.45), value: isArmed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        SoundManager.shared.play(.keyPress)
                        action()
                    }
            )
    }

    private var glowOpacity: Double {
        if isPressed { return 0.8 }
        if isArmed { return 0.55 }
        if isAccent { return 0.28 }
        return isPressed ? 0.7 : 0
    }

    private var glowRadius: CGFloat {
        if isPressed { return 18 }
        if isArmed { return 16 }
        if isAccent { return 8 }
        return 0
    }

    private var label: some View {
        StationHazeLabel(
            text: title,
            fontSize: min(width, height) * (title.count > 1 ? 0.22 : 0.38),
            kerning: title.count > 1 ? min(width, height) * 0.06 : 0,
            pressed: isPressed || isArmed
        )
        .frame(width: width, height: height)
    }

    private var background: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        isPressed || isArmed ? StationChrome.ice : StationChrome.ice.opacity(0.10),
                        isPressed || isArmed ? StationChrome.ice : StationChrome.keyFill,
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var border: some View {
        Rectangle()
            .stroke((isPressed || isArmed || isAccent) ? StationChrome.ice : StationChrome.line, lineWidth: 1)
    }
}

// MARK: - System overlay hidden modifier (iOS 16+ guard)

private struct SystemOverlayHidden: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.persistentSystemOverlays(.hidden)
        } else {
            content
        }
    }
}

// MARK: - Edge gesture deferrer

/// Wraps a UIViewController that returns all edges in
/// `preferredScreenEdgesDeferringSystemGestures`, causing iOS to defer
/// system edge gestures (home indicator, notification center, control center)
/// to the app on first swipe.
struct EdgeGestureDeferrer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> EdgeGestureViewController {
        EdgeGestureViewController()
    }

    func updateUIViewController(_ uiViewController: EdgeGestureViewController, context: Context) {
    }
}

final class EdgeGestureViewController: UIViewController {
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        return [.top, .bottom, .left, .right]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }
}

// MARK: - Ice atmosphere

private struct IceAtmosphere: View {
    var breathing: Bool
    var charged: Bool

    var body: some View {
        ZStack {
            StationChrome.frost
            RadialGradient(
                gradient: Gradient(colors: [
                    StationChrome.ice.opacity(mistOpacity),
                    Color.clear,
                ]),
                center: .bottom,
                startRadius: 40,
                endRadius: charged ? 620 : 520
            )
            .scaleEffect(breathing ? 1.1 : 1.0)
            .animation(
                Animation.easeInOut(duration: 3.8).repeatForever(autoreverses: true),
                value: breathing
            )
            .animation(.easeInOut(duration: 0.5), value: charged)
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(charged ? 0.11 : 0.07),
                    Color.clear,
                ]),
                center: UnitPoint(x: 0.5, y: 0.0),
                startRadius: 8,
                endRadius: 280
            )
            RadialGradient(
                gradient: Gradient(colors: [
                    StationChrome.ice.opacity(charged ? 0.16 : 0.08),
                    Color.clear,
                ]),
                center: UnitPoint(x: 0.82, y: 0.28),
                startRadius: 10,
                endRadius: 240
            )
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    StationChrome.ice.opacity(charged ? 0.10 : 0.05),
                ]),
                startPoint: .center,
                endPoint: .bottom
            )
            StationIceGrain.overlay(opacity: charged ? 0.16 : 0.11)
        }
        .ignoresSafeArea()
    }

    private var mistOpacity: Double {
        if charged { return breathing ? 0.34 : 0.22 }
        return breathing ? 0.22 : 0.12
    }
}

private struct IceSubmitFlash: View {
    var progress: CGFloat

    var body: some View {
        StationChrome.ice
            .opacity(0.22 * Double(progress))
            .blendMode(.screen)
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}

#if DEBUG
@available(iOS 15.0, *)
struct KeyboardOnlyView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            KeyboardOnlyView()
                .previewInterfaceOrientation(.landscapeLeft)
                .previewDevice("iPad (9th generation)")
                .previewDisplayName("Keyboard kiosk")

            SplitChoiceView(leftTitle: "YES", rightTitle: "NO", onLeft: {}, onRight: {})
                .background(Color.black)
                .previewInterfaceOrientation(.landscapeLeft)
                .previewDevice("iPad (9th generation)")
                .previewDisplayName("Yes / No split")

            SplitChoiceView(leftTitle: "Beauty", rightTitle: "Money", onLeft: {}, onRight: {})
                .background(Color.black)
                .previewInterfaceOrientation(.landscapeLeft)
                .previewDevice("iPad (9th generation)")
                .previewDisplayName("This or that")
        }
    }
}
#endif
