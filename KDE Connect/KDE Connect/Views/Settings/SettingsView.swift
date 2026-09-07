//
//  SettingsView.swift
//  KDE Connect Test
//
//  Created by Lucas Wang on 2021-06-17.
//

#if !os(macOS)

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var kdeConnectSettingsForSettings: KdeConnectSettings = .shared
    @ObservedObject private var devicesViewModel: ConnectedDevicesViewModel = connectedDevicesViewModel

    /// Merged [deviceId: deviceName] from connected and remembered devices, for the target picker.
    private var availableDevices: [String: String] {
        devicesViewModel.connectedDevices.merging(devicesViewModel.savedDevices) { current, _ in current }
    }

    /// Sentinel for the "Auto-select" picker option (nil stationTargetDeviceId).
    private static let autoSelectTag = ""

    private static func stationPickerTitle(_ id: String) -> String {
        switch id {
        case "1": return "Station I"
        case "2": return "Station II"
        case "3": return "Station III"
        default: return "Station \(id)"
        }
    }

    var body: some View {
        List {
            // These could go in sections to give them each descriptions and space
            Section(header: Text("General")) {
                NavigationLink(destination: SettingsDeviceNameView(deviceName: $kdeConnectSettingsForSettings.deviceName)) {
                    AccessibleHStack {
                        Label("Device Name", systemImage: DeviceType.current.sfSymbolName)
                            .labelStyle(.accessibilityTitleOnly)
                            .accentColor(.primary)
                        Spacer()
                        Text(kdeConnectSettingsForSettings.deviceName)
                            .foregroundColor(.secondary)
                    }
                }
                
                AccessibleHStack {
                    Label {
                        SettingsChosenThemeView(chosenTheme: $kdeConnectSettingsForSettings.chosenTheme)
                    } icon: {
                        Image(systemName: "lightbulb")
                    }
                    .labelStyle(.accessibilityTitleOnly)
                    .accentColor(.primary)
                }
                
                if UIApplication.shared.supportsAlternateIcons {
                    NavigationLink {
                        AppIconPicker()
                    } label: {
                        AccessibleHStack {
                            Label("App Icon", systemImage: "app")
                                .labelStyle(.accessibilityTitleOnly)
                                .accentColor(.primary)
                            Spacer()
                            kdeConnectSettingsForSettings.appIcon.name
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                NavigationLink {
                    SettingsAdvancedView()
                } label: {
                    Label("Advanced Settings", systemImage: "wrench.and.screwdriver")
                        .labelStyle(.accessibilityTitleOnly)
                        .accentColor(.primary)
                }
            }
            
            Section(header: Text("Station")) {
                AccessibleHStack {
                    Label("Broker URI", systemImage: "network")
                        .labelStyle(.accessibilityTitleOnly)
                        .accentColor(.primary)
                    Spacer()
                    TextField("tcp://host:1883",
                              text: $kdeConnectSettingsForSettings.stationBrokerUri)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Picker(selection: $kdeConnectSettingsForSettings.stationId) {
                    ForEach(KdeConnectSettings.StationIds, id: \.self) { id in
                        Text(Self.stationPickerTitle(id)).tag(id)
                    }
                } label: {
                    Label("This iPad's station", systemImage: "number")
                        .labelStyle(.accessibilityTitleOnly)
                        .accentColor(.primary)
                }

                Picker(selection: Binding(
                    get: { kdeConnectSettingsForSettings.stationTargetDeviceId ?? Self.autoSelectTag },
                    set: { newValue in
                        kdeConnectSettingsForSettings.stationTargetDeviceId = newValue == Self.autoSelectTag ? nil : newValue
                    }
                )) {
                    Text("Auto-select").tag(Self.autoSelectTag)
                    ForEach(availableDevices.sorted(by: { $0.value < $1.value }), id: \.key) { deviceId, deviceName in
                        Text(deviceName).tag(deviceId)
                    }
                } label: {
                    Label("Target Device", systemImage: "display")
                        .labelStyle(.accessibilityTitleOnly)
                        .accentColor(.primary)
                }

                Toggle(isOn: $kdeConnectSettingsForSettings.launchIntoStationMode) {
                    Label("Launch into Station Mode", systemImage: "rectangle.dock")
                        .labelStyle(.accessibilityTitleOnly)
                        .accentColor(.primary)
                }

                Toggle(isOn: $kdeConnectSettingsForSettings.stationMqttDebug) {
                    Label("Show MQTT Traffic", systemImage: "antenna.radiowaves.left.and.right")
                        .labelStyle(.accessibilityTitleOnly)
                        .accentColor(.primary)
                }

                Toggle(isOn: $kdeConnectSettingsForSettings.showConnectionDebug) {
                    Label("Show Connection Status", systemImage: "antenna.radiowaves.left.and.right")
                        .labelStyle(.accessibilityTitleOnly)
                        .accentColor(.primary)
                }

                Toggle(isOn: $kdeConnectSettingsForSettings.showKeyboardControls) {
                    Label("Show Move/Resize Controls", systemImage: "move.3d")
                        .labelStyle(.accessibilityTitleOnly)
                        .accentColor(.primary)
                }

                Button {
                    kdeConnectSettingsForSettings.resetKeyboardLayout()
                } label: {
                    Label("Reset Keyboard Layout", systemImage: "arrow.counterclockwise")
                        .labelStyle(.accessibilityTitleOnly)
                        .accentColor(.primary)
                }

                AccessibleHStack {
                    Label("Upload URL", systemImage: "arrow.up.circle")
                        .labelStyle(.accessibilityTitleOnly)
                        .accentColor(.primary)
                    Spacer()
                    TextField("http://host:8080/upload",
                              text: $kdeConnectSettingsForSettings.stationUploadUrl)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }

            Section(header: Text("Information")) {
                NavigationLink {
                    SettingsAboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                        .labelStyle(.accessibilityTitleOnly)
                        .accentColor(.primary)
                }
                NavigationLink(destination: FeaturesList()) {
                    Label {
                        Text("Features")
                    } icon: {
                        if #available(iOS 15, *) {
                            Image(systemName: "checklist")
                        } else {
                            Image(systemName: "scroll")
                        }
                    }
                    .labelStyle(.accessibilityTitleOnly)
                    .accentColor(.primary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

// struct SettingsView_Previews: PreviewProvider {
//     static var previews: some View {
//         SettingsView()
//     }
// }

#endif
