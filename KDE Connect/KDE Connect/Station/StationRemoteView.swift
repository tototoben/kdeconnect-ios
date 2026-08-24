/*
 * SPDX-FileCopyrightText: 2026 station-mode contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import SwiftUI
import UIKit

struct StationRemoteView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var settings = KdeConnectSettings.shared
    @ObservedObject private var devicesViewModel = connectedDevicesViewModel

    @State private var yesLabel: String = "YES"
    @State private var noLabel: String = "NO"
    @State private var yesEnabled: Bool = true
    @State private var noEnabled: Bool = true
    @State private var pulse: Bool = false
    @State private var showingSettings: Bool = false

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

                HStack(spacing: 0) {
                    Button(action: sendYes) {
                        Text(yesLabel)
                            .font(.system(size: 48, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(yesEnabled ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                    }
                    .disabled(!yesEnabled)
                    .scaleEffect(pulse ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: pulse)

                    Button(action: sendNo) {
                        Text(noLabel)
                            .font(.system(size: 48, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(noEnabled ? Color.red.opacity(0.15) : Color.gray.opacity(0.1))
                    }
                    .disabled(!noEnabled)
                    .scaleEffect(pulse ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: pulse)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            }

            VStack {
                HStack {
                    Button(action: { showingSettings = true }, label: {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .padding(8)
                    })
                    Spacer()
                }
                .padding(.top, 8)
                Spacer()
            }
        }
        .statusBar(hidden: true)
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingSettings) {
            MainTabView()
        }
    }

    private func sendYes() {
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendKeyPress("Y")
        remoteInput.sendKeyPress("E")
        remoteInput.sendKeyPress("S")
        remoteInput.sendSpecialKeyPress(.return)
    }

    private func sendNo() {
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendKeyPress("N")
        remoteInput.sendKeyPress("O")
        remoteInput.sendSpecialKeyPress(.return)
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
}
