/*
 * SPDX-FileCopyrightText: 2026 station-mode contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import AudioToolbox
import SwiftUI
import UIKit

struct StationRemoteView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var settings = KdeConnectSettings.shared
    @ObservedObject private var devicesViewModel = connectedDevicesViewModel

    @State private var pulse: Bool = false
    @State private var showingSettings: Bool = false
    @State private var cameraManager: StationCameraManager?
    @State private var mqttCoordinator: MqttCoordinator?
    @State private var mqttLog: [String] = []
    @State private var logPaused: Bool = false

    @State private var previousHorizontalDragOffset: Float = 0.0
    @State private var previousVerticalDragOffset: Float = 0.0
    @State private var cursorSensitivity: Float = 3.0
    @State private var hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle = .light

    private var targetDeviceId: String? {
        let id = settings.stationTargetDeviceId
        if id != nil
            && ConnectedDevicesViewModel.isDeviceCurrentlyPairedAndConnected(id!)
            && backgroundService._devices[id!]?._pluginsEnableStatus[.mousePadRequest] != nil {
            return id
        }
        return autoSelectDevice()
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TwoFingerTapView { _ in
                    sendRightClick()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let dxDrag: Float = Float(gesture.translation.width) - previousHorizontalDragOffset
                            let dyDrag: Float = Float(gesture.translation.height) - previousVerticalDragOffset
                            sendMouseDelta(dx: dxDrag * cursorSensitivity, dy: dyDrag * cursorSensitivity)
                            previousHorizontalDragOffset = Float(gesture.translation.width)
                            previousVerticalDragOffset = Float(gesture.translation.height)
                        }
                        .onEnded { _ in
                            previousHorizontalDragOffset = 0.0
                            previousVerticalDragOffset = 0.0
                        }
                )
                .tapRecognizer(tapSensitivity: 0.2, singleTapAction: sendSingleClick, doubleTapAction: sendDoubleClick)
                .onLongPressGesture {
                    sendSingleHold()
                }

                KeyboardListenerPlaceholderView { key, modifiers in
                    sendKeyPress(key, modifiers)
                } onDeleteBackward: {
                    sendSpecialKeyPress(.backspace)
                } onReturn: {
                    sendSpecialKeyPress(.return)
                } onTab: {
                    sendSpecialKeyPress(.tab)
                }
            }

            if settings.stationMqttDebug {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(logPaused ? "LOGS (paused)" : "LOGS")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.green.opacity(0.6))
                        Spacer()
                        Button(action: { logPaused.toggle() }) {
                            Image(systemName: logPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green.opacity(0.6))
                                .padding(4)
                        }
                    }
                    .padding(.horizontal, 8)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(mqttLog.indices.reversed(), id: \.self) { index in
                                logText(for: mqttLog[index])
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .allowsHitTesting(logPaused)
            }

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("target: \(targetDeviceId ?? "nil")")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.yellow.opacity(0.7))
                        Text("connected: \(devicesViewModel.connectedDevices.count)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.yellow.opacity(0.7))
                        ForEach(devicesViewModel.connectedDevices.sorted(by: { $0.value < $1.value }), id: \.key) { id, name in
                            let hasPlugin = (backgroundService._devices[id]?._plugins[.mousePadRequest] as? RemoteInput) != nil
                            Text("  \(name): \(hasPlugin ? "remoteInput" : "no-remoteInput")")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(hasPlugin ? .green.opacity(0.5) : .red.opacity(0.5))
                        }
                    }
                    Spacer()
                    Button(action: { showingSettings = true }, label: {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .padding(8)
                    })
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
                Spacer()
            }
        }
        .statusBar(hidden: true)
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingSettings) {
            MainTabView()
        }
        .onAppear {
            // Force landscape orientation for kiosk mode
            forceLandscapeOrientation()
            let logCallback: (String) -> Void = { entry in
                DispatchQueue.main.async {
                    mqttLog.append(entry)
                    if mqttLog.count > 50 {
                        mqttLog.removeFirst(mqttLog.count - 50)
                    }
                }
            }
            let coordinator = MqttCoordinator(
                brokerUri: settings.stationBrokerUri,
                stationId: settings.stationId,
                onControl: { control in
                    handleControlMessage(control)
                },
                onLog: logCallback
            )
            mqttCoordinator = coordinator
            let camera = StationCameraManager(
                uploadUrl: settings.stationUploadUrl,
                listener: coordinator,
                onLog: logCallback
            )
            cameraManager = camera
            coordinator.connect()
        }
        .onDisappear {
            mqttCoordinator?.disconnect()
            mqttCoordinator = nil
            cameraManager?.stop()
            cameraManager = nil
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                mqttCoordinator?.connect()
            case .background, .inactive:
                mqttCoordinator?.disconnect()
            @unknown default:
                break
            }
        }
    }

    private func sendKeyPress(_ keys: String, _ modifiers: [RemoteInput.KeyModifier]) {
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendKeyPress(keys, modifiers)
        mqttCoordinator?.publishEvent(.textSent(text: keys))
    }

    private func sendSpecialKeyPress(_ key: RemoteInput.SpecialKey) {
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendSpecialKeyPress(key)
    }

    private func sendMouseDelta(dx: Float, dy: Float) {
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendMouseDelta(dx: dx, dy: dy)
    }

    private func sendSingleClick() {
        UIImpactFeedbackGenerator(style: hapticStyle).impactOccurred()
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendSingleClick()
    }

    private func sendDoubleClick() {
        notificationHapticsGenerator.notificationOccurred(.success)
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendDoubleClick()
    }

    private func sendSingleHold() {
        UIImpactFeedbackGenerator(style: hapticStyle).impactOccurred()
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendSingleHold()
    }

    private func sendRightClick() {
        UIImpactFeedbackGenerator(style: hapticStyle).impactOccurred()
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendRightClick()
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

    private func forceLandscapeOrientation() {
        if #available(iOS 16.0, *) {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                    ?? scenes.first(where: { $0.activationState == .foregroundInactive })
                    ?? scenes.first else {
                // Scene not ready yet; retry shortly
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

    private func handleControlMessage(_ control: [String: Any]) {
        let action = control["action"] as? String ?? ""

        if action == "take_photo" {
            DispatchQueue.main.async {
                cameraManager?.record(duration: 3.0)
            }
        }

        if let feedback = control["feedback"] as? [String: Any] {
            applyFeedback(feedback)
        }
    }

    private func applyFeedback(_ feedback: [String: Any]) {
        if let vibrateMs = feedback["vibrateMs"] as? Int, vibrateMs > 0 {
            let clamped = min(vibrateMs, 1000)
            DispatchQueue.main.async {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(clamped) / 1000.0) {
                    generator.impactOccurred()
                }
            }
        }

        if feedback["sound"] as? String == "beep" {
            DispatchQueue.main.async {
                AudioServicesPlaySystemSound(1057)
            }
        }

        if feedback["animation"] as? String == "pulse" {
            DispatchQueue.main.async {
                pulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pulse = false
                }
            }
        }
    }

    private func logColor(for entry: String) -> Color {
        if entry.contains("error") || entry.contains("failed") {
            return Color(red: 0.9, green: 0.3, blue: 0.3)
        }
        if entry.hasPrefix("-> ") {
            return Color(red: 0.3, green: 0.8, blue: 0.9)
        }
        if entry.hasPrefix("<- ") {
            return Color(red: 0.9, green: 0.85, blue: 0.3)
        }
        if entry.hasPrefix("CONNECT") || entry.hasPrefix("DISCONNECT") {
            return Color(red: 0.3, green: 0.5, blue: 0.9)
        }
        if entry.hasPrefix("VISITOR") {
            return Color(red: 0.3, green: 0.85, blue: 0.3)
        }
        if entry.hasPrefix("CAMERA") {
            return Color(red: 0.3, green: 0.7, blue: 0.3)
        }
        if entry.hasPrefix("REC") {
            return Color(red: 0.9, green: 0.6, blue: 0.2)
        }
        if entry.hasPrefix("UPLOAD") {
            return Color(red: 0.7, green: 0.4, blue: 0.9)
        }
        return Color(red: 0.3, green: 0.8, blue: 0.3)
    }

    private func logText(for entry: String) -> Text {
        let font = Font.system(size: 10, design: .monospaced)

        guard let braceIndex = entry.firstIndex(of: "{"),
              braceIndex > entry.startIndex else {
            return Text(entry)
                .font(font)
                .foregroundColor(logColor(for: entry))
        }

        let prefix = String(entry[entry.startIndex..<braceIndex])
        let json = String(entry[braceIndex...])

        let prefixText = Text(prefix)
            .font(font)
            .foregroundColor(logColor(for: entry))

        return prefixText + highlightJSONText(json, font: font)
    }

    private func highlightJSONText(_ json: String, font: Font) -> Text {
        let keyColor = Color(red: 0.4, green: 0.7, blue: 0.9)
        let stringColor = Color(red: 0.8, green: 0.8, blue: 0.4)
        let numberColor = Color(red: 0.9, green: 0.6, blue: 0.5)
        let boolColor = Color(red: 0.9, green: 0.5, blue: 0.6)
        let nullColor = Color(red: 0.6, green: 0.6, blue: 0.6)
        let punctColor = Color(red: 0.5, green: 0.5, blue: 0.5)

        var result = Text("")
        var i = json.startIndex

        while i < json.endIndex {
            let ch = json[i]

            if ch == "{" || ch == "}" || ch == "[" || ch == "]" || ch == "," || ch == ":" {
                result = result + Text(String(ch)).font(font).foregroundColor(punctColor)
                i = json.index(after: i)
            } else if ch == "\"" {
                let stringStart = i
                i = json.index(after: i)
                while i < json.endIndex && json[i] != "\"" {
                    if json[i] == "\\" && json.index(after: i) < json.endIndex {
                        i = json.index(after: i)
                    }
                    i = json.index(after: i)
                }
                if i < json.endIndex { i = json.index(after: i) }
                let stringContent = String(json[stringStart..<i])

                var nextNonSpace = i
                while nextNonSpace < json.endIndex && json[nextNonSpace] == " " {
                    nextNonSpace = json.index(after: nextNonSpace)
                }
                let isKey = nextNonSpace < json.endIndex && json[nextNonSpace] == ":"

                result = result + Text(stringContent).font(font).foregroundColor(isKey ? keyColor : stringColor)
            } else if ch.isNumber || (ch == "-" && json.index(after: i) < json.endIndex && json[json.index(after: i)].isNumber) {
                let numStart = i
                while i < json.endIndex && (json[i].isNumber || json[i] == "." || json[i] == "-" || json[i] == "e" || json[i] == "E" || json[i] == "+") {
                    i = json.index(after: i)
                }
                result = result + Text(String(json[numStart..<i])).font(font).foregroundColor(numberColor)
            } else if ch == "t" || ch == "f" {
                let wordStart = i
                while i < json.endIndex && json[i].isLetter { i = json.index(after: i) }
                result = result + Text(String(json[wordStart..<i])).font(font).foregroundColor(boolColor)
            } else if ch == "n" {
                let wordStart = i
                while i < json.endIndex && json[i].isLetter { i = json.index(after: i) }
                result = result + Text(String(json[wordStart..<i])).font(font).foregroundColor(nullColor)
            } else {
                result = result + Text(String(ch)).font(font).foregroundColor(punctColor)
                i = json.index(after: i)
            }
        }
        return result
    }
}

final class MqttCoordinator: StationMqttListener, StationCameraListener {
    private var client: StationMqttClient?
    private let brokerUri: String
    private let stationId: String
    private let onControl: ([String: Any]) -> Void
    private var onLog: ((String) -> Void)?

    init(
        brokerUri: String,
        stationId: String,
        onControl: @escaping ([String: Any]) -> Void,
        onLog: ((String) -> Void)? = nil
    ) {
        self.brokerUri = brokerUri
        self.stationId = stationId
        self.onControl = onControl
        self.onLog = onLog
    }

    func connect() {
        guard client == nil else { return }
        let client = StationMqttClient(brokerUri: brokerUri, stationId: stationId, listener: self)
        self.client = client
        client.connect()
        onLog?("CONNECT \(brokerUri) station=\(stationId)")
    }

    func disconnect() {
        client?.disconnect()
        client = nil
        onLog?("DISCONNECT")
    }

    func publishEvent(_ event: StationEvent) {
        let payload = event.payload()
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            onLog?("-> \(json)")
        }
        client?.publishEvent(event)
    }

    func publishRemoteSlider(value: Double, seq: Int, confirm: Bool = false) {
        onLog?("-> slider \(value) seq=\(seq) confirm=\(confirm)")
        client?.publishRemoteSlider(value: value, seq: seq, confirm: confirm)
    }

    func publishRemoteOperator(_ action: String) {
        onLog?("-> operator \(action)")
        client?.publishRemoteOperator(action)
    }

    func publishRemoteKey(
        key: String? = nil,
        special: String? = nil,
        alt: Bool = false,
        shift: Bool = false
    ) {
        onLog?("-> key \(key ?? special ?? "?")")
        client?.publishRemoteKey(key: key, special: special, alt: alt, shift: shift)
    }

    func onControlMessage(_ control: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: control),
           let json = String(data: data, encoding: .utf8) {
            onLog?("<- \(json)")
        }
        onControl(control)
    }

    // MARK: - StationCameraListener

    func onVisitorEntered(side: String, distance: StationDistance) {
        publishEvent(.visitorEntered(side: side, distance: distance))
    }

    func onVisitorDistanceChanged(distance: StationDistance) {
        publishEvent(.visitorDistanceChanged(distance: distance))
    }

    func onVisitorApproached() {
        publishEvent(.visitorApproached)
    }

    func onVisitorLeft() {
        publishEvent(.visitorLeft)
    }
}
