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

    /// True when Guided Access is active — all config/debug UI is hidden.
    private var isKiosk: Bool { isGuidedAccessActive }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if focusMode == .standard {
                StationKeyboardRootView(
                    onKey: { key in
                        sendKeyPress(key, [])
                    },
                    onDelete: {
                        sendSpecialKeyPress(.backspace)
                    },
                    onReturn: {
                        sendSpecialKeyPress(.return)
                    },
                    onSpace: {
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
                    scale: 1.0
                )
            } else {
                YesNoFocusView(
                    onYes: {
                        sendKeyPress("y", [])
                        focusMode = .standard
                    },
                    onSkip: {
                        sendKeyPress("n", [])
                        focusMode = .standard
                    }
                )
            }

            VStack {
                HStack {
                    if settings.showConnectionDebug && !isKiosk {
                        VStack(alignment: .leading, spacing: 2) {
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
                                .foregroundColor(.gray)
                                .padding(8)
                        })
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
                Spacer()
            }

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
                                .foregroundColor(.gray)
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
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            mqttCoordinator?.disconnect()
            mqttCoordinator = nil
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
        let modsToUse = mods.isEmpty ? modifiers : mods
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendKeyPress(keys, modsToUse)
        modifiers.removeAll()
    }

    private func sendSpecialKeyPress(_ key: RemoteInput.SpecialKey) {
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendSpecialKeyPress(key)
        modifiers.removeAll()
    }

    // MARK: - MQTT

    private func connectMqtt() {
        guard mqttCoordinator == nil else { return }
        let coordinator = MqttCoordinator(
            brokerUri: settings.stationBrokerUri,
            stationId: settings.stationId,
            onControl: { control in
                handleControlMessage(control)
            }
        )
        mqttCoordinator = coordinator
        coordinator.connect()
    }

    private func handleControlMessage(_ control: [String: Any]) {
        let action = control["action"] as? String ?? ""
        DispatchQueue.main.async {
            switch action {
            case "yesNoFocused":
                focusMode = .yesNo
            case "yesNoBlur":
                focusMode = .standard
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
    case yesNo
}

// MARK: - Yes/No focus view

struct YesNoFocusView: View {
    let onYes: () -> Void
    let onSkip: () -> Void

    var body: some View {
        GeometryReader { geo in
            // Two large buttons for the "ready?" confirm -- Yes starts the
            // recording countdown, Skip declines it. Both choices are saved
            // (see readyAnswer in ThirdStation.tsx / photobashTrigger.ts).
            let buttonWidth = (geo.size.width - 60) / 2
            let buttonHeight = geo.size.height - 40

            HStack(spacing: 20) {
                FocusButton(
                    title: "YES",
                    width: buttonWidth,
                    height: buttonHeight,
                    action: onYes
                )
                FocusButton(
                    title: "SKIP",
                    width: buttonWidth,
                    height: buttonHeight,
                    action: onSkip
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct FocusButton: View {
    let title: String
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    @GestureState private var isPressed: Bool = false

    var body: some View {
        label
            .background(background)
            .overlay(border)
            .scaleEffect(isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.1, dampingFraction: 0.8), value: isPressed)
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

    private var label: some View {
        Text(title)
            .font(.system(size: min(min(width, height) * 0.35, 72), weight: .medium))
            .foregroundColor(.white)
            .frame(width: width, height: height)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isPressed ? Color(red: 0.3, green: 0.6, blue: 1.0, opacity: 0.5) : Color(white: 0.18))
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(isPressed ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1.5)
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
