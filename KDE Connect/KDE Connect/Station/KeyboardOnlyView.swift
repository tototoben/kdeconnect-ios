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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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

            VStack {
                HStack {
                    if settings.showConnectionDebug {
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

            // Floating reset button at bottom-left
            if settings.showKeyboardControls {
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
        }
        .statusBarHidden()
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingSettings) {
            MainTabView()
        }
        .onAppear {
            forceLandscapeOrientation()
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
