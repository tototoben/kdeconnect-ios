/*
 * SPDX-FileCopyrightText: 2026 station-mode contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import SwiftUI
import UIKit

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
                        submitArmed: hasTyped
                    )
                } else if focusMode == .numeric {
                    NumericPadFocusView(
                        onDigit: { digit in
                            markTyped()
                            sendKeyPress(digit, [])
                        },
                        onDelete: {
                            sendSpecialKeyPress(.backspace)
                        },
                        onReturn: {
                            confirmEntry()
                        },
                        submitArmed: hasTyped
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            IceSubmitFlash(progress: flashProgress)

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
        kioskLink?.sendKey(keys)
        let modsToUse = mods.isEmpty ? modifiers : mods
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendKeyPress(keys, modsToUse)
        modifiers.removeAll()
    }

    private func sendSpecialKeyPress(_ key: RemoteInput.SpecialKey) {
        switch key {
        case .return: kioskLink?.sendSpecial("return")
        case .backspace: kioskLink?.sendSpecial("backspace")
        case .tab: kioskLink?.sendSpecial("tab")
        default: break
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
        kioskLink?.sendSlider(clamped, seq: sliderSeq)
    }

    private func confirmSlider() {
        lastSentSlider = sliderValue
        sliderSeq += 1
        kioskLink?.sendSlider(sliderValue, seq: sliderSeq)
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
        // Age (and any other numeric prompt) should drop the numpad as soon as
        // OK is pressed. The next keyboard_focus from the kiosk then selects
        // letters, yes/no, or hidden — without waiting on MQTT to leave the pad.
        if focusMode == .numeric {
            focusMode = .standard
        }
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
        DispatchQueue.main.async {
            switch action {
            case "yesNoFocused", "choiceFocused":
                applyChoiceLabels(from: control, defaultsToYesNo: action == "yesNoFocused")
                focusMode = .choice
                hasTyped = false
            case "yesNoBlur", "textFocused":
                focusMode = .standard
                hasTyped = false
            case "numericFocused":
                focusMode = .numeric
                hasTyped = false
            case "numericBlur":
                focusMode = .standard
                hasTyped = false
            case "scaleFocused":
                applySliderLabels(from: control)
                let incoming = incomingSliderValue(from: control)
                sliderValue = incoming ?? (focusMode == .scale ? sliderValue : 0.5)
                lastSentSlider = sliderValue
                focusMode = .scale
                hasTyped = true
            case "keyboardHidden":
                focusMode = .hidden
                hasTyped = false
            default:
                break
            }
        }
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
    case hidden
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
                IceScaleSlider(value: $value, onChange: onChange)
                    .frame(height: min(96, geo.size.height * 0.28))
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

private struct IceScaleSlider: View {
    @Binding var value: Double
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let thumb: CGFloat = min(84, max(64, geo.size.height))
            let trackH: CGFloat = min(56, thumb * 0.62)
            let usable = max(geo.size.width - thumb, 1)
            let x = thumb / 2 + CGFloat(value) * usable

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(StationChrome.ice.opacity(0.10))
                    .frame(height: trackH)
                    .overlay(StationIceGrain.overlay(opacity: 0.12))
                    .overlay(
                        Rectangle()
                            .stroke(StationChrome.ice.opacity(0.28), lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                Rectangle()
                    .fill(StationChrome.ice.opacity(0.42))
                    .frame(width: max(x, trackH), height: trackH)
                    .overlay(StationIceGrain.overlay(opacity: 0.18))
                    .frame(maxHeight: .infinity, alignment: .center)

                Rectangle()
                    .fill(StationChrome.ice)
                    .overlay(StationIceGrain.overlay(opacity: 0.28))
                    .overlay(
                        Rectangle()
                            .stroke(StationChrome.ice.opacity(0.95), lineWidth: 1)
                            .padding(1)
                    )
                    .shadow(color: StationChrome.ice.opacity(0.55), radius: 14)
                    .frame(width: thumb, height: thumb)
                    .offset(x: x - thumb / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let next = min(1, max(0, Double((drag.location.x - thumb / 2) / usable)))
                        if abs(next - value) >= 0.002 {
                            value = next
                            onChange(next)
                        }
                    }
            )
        }
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

struct NumericPadFocusView: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    let onReturn: () -> Void
    var submitArmed: Bool = false

    private let rows = [
        ["7", "8", "9"],
        ["4", "5", "6"],
        ["1", "2", "3"],
    ]

    var body: some View {
        GeometryReader { geo in
            let key = min(geo.size.width * 0.2, geo.size.height * 0.2)
            VStack(spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { digit in
                            FocusButton(title: digit, width: key, height: key) {
                                onDigit(digit)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    FocusButton(title: "DEL", width: key, height: key, action: onDelete)
                    FocusButton(title: "0", width: key, height: key) {
                        onDigit("0")
                    }
                    FocusButton(title: "OK", width: key, height: key, isAccent: true, isArmed: submitArmed, action: onReturn)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

            NumericPadFocusView(onDigit: { _ in }, onDelete: {}, onReturn: {})
                .background(Color.black)
                .previewInterfaceOrientation(.landscapeLeft)
                .previewDevice("iPad (9th generation)")
                .previewDisplayName("Age numpad")

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
