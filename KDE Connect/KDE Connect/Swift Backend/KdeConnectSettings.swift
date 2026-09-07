/*
 * SPDX-FileCopyrightText: 2021 Lucas Wang <lucas.wang@tuta.io>
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

// Original header below:
//
//  DeviceData.swift
//  KDE Connect Test
//
//  Created by Lucas Wang on 2021-06-17.
//

import UniformTypeIdentifiers
import SwiftUI

import os.log
@objc
class KdeConnectSettings: NSObject, ObservableObject {
    @objc
    static let shared = KdeConnectSettings()

    @objc
    static let CurrentProtocolVersion = 8
    
    // FIXME: actually read what plugins are available
    static let IncomingCapabilities: [NetworkPacket.`Type`] = [
        .ping,
        .share,
        .shareRequestUpdate,
        .findMyPhoneRequest,
        .batteryRequest,
        .battery,
        .clipboard,
        .clipboardConnect,
        .runCommand,
    ]
    static let OutgoingCapabilities: [NetworkPacket.`Type`] = [
        .ping,
        .share,
        .shareRequestUpdate,
        .findMyPhoneRequest,
        .batteryRequest,
        .battery,
        .clipboard,
        .clipboardConnect,
        .mousePadRequest,
        .presenter,
        .runCommandRequest,
    ]
    
    private static var cachedUuid: String?

    @objc
    static func getUUID() -> String {
        if cachedUuid == nil {
            let group = "5433B4KXM8.org.kde.kdeconnect"
            let wrapper = KeychainItemWrapper(identifier: "org.kde.kdeconnect-ios", accessGroup: group)!
            if let savedUUID = wrapper.object(forKey: kSecValueData as String) as? String, !savedUUID.isEmpty {
                cachedUuid = savedUUID
            } else {
#if !os(macOS)
                // identifierForVendor can be nil if called when a device has restarted but not been unlocked yet
                if let identifierForVendor = UIDevice.current.identifierForVendor {
                    cachedUuid = identifierForVendor.uuidString.replacingOccurrences(of: "-", with: "_").lowercased()
                    wrapper.setObject(cachedUuid, forKey: kSecValueData as String)
                }
#else
                let identifierForVendor = NetworkPacket.getMacUUID()
                cachedUuid = identifierForVendor.replacingOccurrences(of: "-", with: "_").lowercased()
                wrapper.setObject(cachedUuid, forKey: kSecValueData as String)
#endif
            }
            let logger = OSLog(subsystem: NSStringFromClass(self), category: "UUIDManager")
            os_log("Get UUID %{mask.hash}@", log: logger, type: .info, cachedUuid ?? "")
        }
        return cachedUuid!
    }
    
    @Published var deviceName: String {
        didSet {
            UserDefaults.standard.set(DeviceInfo.filterDeviceName(name: deviceName), forKey: "deviceName")
        }
    }
    
    @Published var chosenTheme: ColorScheme? {
        didSet {
            UserDefaults.standard.set(chosenTheme?.rawValue, forKey: "chosenTheme")
        }
    }
    
    @Published var appIcon: AppIcon {
        didSet {
            UserDefaults.standard.set(appIcon.rawValue, forKey: "appIcon")
        }
    }
    
    @Published var directIPs: [String] {
        didSet {
            UserDefaults.standard.set(directIPs, forKey: "directIPs")
        }
    }
    
    @Published var savePhotosToPhotosLibrary: Bool {
        didSet {
            UserDefaults.standard.set(savePhotosToPhotosLibrary,
                                      forKey: "savePhotosToPhotosLibrary")
        }
    }
    
    @Published var saveVideosToPhotosLibrary: Bool {
        didSet {
            UserDefaults.standard.set(saveVideosToPhotosLibrary,
                                      forKey: "saveVideosToPhotosLibrary")
        }
    }
    
    @Published var disableUdpBroadcastDiscovery: Bool {
        didSet {
            UserDefaults.standard.set(disableUdpBroadcastDiscovery,
                                      forKey: "disableUdpBroadcastDiscovery")
        }
    }
    
    // MARK: - Station mode
    
    static let StationIds = ["1", "2", "3"]
    
    @Published var stationBrokerUri: String {
        didSet {
            UserDefaults.standard.set(stationBrokerUri, forKey: "stationBrokerUri")
        }
    }
    
    @Published var stationId: String {
        didSet {
            UserDefaults.standard.set(stationId, forKey: "stationId")
        }
    }
    
    @Published var stationTargetDeviceId: String? {
        didSet {
            UserDefaults.standard.set(stationTargetDeviceId, forKey: "stationTargetDeviceId")
        }
    }
    
    @Published var launchIntoStationMode: Bool {
        didSet {
            UserDefaults.standard.set(launchIntoStationMode, forKey: "launchIntoStationMode")
        }
    }

    @Published var stationMqttDebug: Bool {
        didSet {
            UserDefaults.standard.set(stationMqttDebug, forKey: "stationMqttDebug")
        }
    }

    @Published var stationUploadUrl: String {
        didSet {
            UserDefaults.standard.set(stationUploadUrl, forKey: "stationUploadUrl")
        }
    }

    @Published var showConnectionDebug: Bool {
        didSet {
            UserDefaults.standard.set(showConnectionDebug, forKey: "showConnectionDebug")
        }
    }

    @Published var showKeyboardControls: Bool {
        didSet {
            UserDefaults.standard.set(showKeyboardControls, forKey: "showKeyboardControls")
        }
    }

    @Published var keyboardLayout: KeyboardLayout {
        didSet {
            UserDefaults.standard.set(keyboardLayout.rawValue, forKey: "keyboardLayout")
        }
    }

    // Keyboard panel layout: persisted offsets and scales per panel
    @Published var keyboardModifiersOffset: CGSize {
        didSet { UserDefaults.standard.set(["w": keyboardModifiersOffset.width, "h": keyboardModifiersOffset.height], forKey: "kbModifiersOffset") }
    }
    @Published var keyboardCharactersOffset: CGSize {
        didSet { UserDefaults.standard.set(["w": keyboardCharactersOffset.width, "h": keyboardCharactersOffset.height], forKey: "kbCharactersOffset") }
    }
    @Published var keyboardNumpadOffset: CGSize {
        didSet { UserDefaults.standard.set(["w": keyboardNumpadOffset.width, "h": keyboardNumpadOffset.height], forKey: "kbNumpadOffset") }
    }
    @Published var keyboardActionsOffset: CGSize {
        didSet { UserDefaults.standard.set(["w": keyboardActionsOffset.width, "h": keyboardActionsOffset.height], forKey: "kbActionsOffset") }
    }
    @Published var keyboardModifiersScale: CGFloat {
        didSet { UserDefaults.standard.set(keyboardModifiersScale, forKey: "kbModifiersScale") }
    }
    @Published var keyboardCharactersScale: CGFloat {
        didSet { UserDefaults.standard.set(keyboardCharactersScale, forKey: "kbCharactersScale") }
    }
    @Published var keyboardNumpadScale: CGFloat {
        didSet { UserDefaults.standard.set(keyboardNumpadScale, forKey: "kbNumpadScale") }
    }
    @Published var keyboardActionsScale: CGFloat {
        didSet { UserDefaults.standard.set(keyboardActionsScale, forKey: "kbActionsScale") }
    }

    func resetKeyboardLayout() {
        keyboardModifiersOffset = CGSize(width: -8, height: 75.5)
        keyboardCharactersOffset = CGSize(width: -4, height: 184.5)
        keyboardNumpadOffset = CGSize(width: 65, height: 66)
        keyboardActionsOffset = CGSize(width: 130, height: 66)
        keyboardModifiersScale = 1.0
        keyboardCharactersScale = 1.0
        keyboardNumpadScale = 1.0
        keyboardActionsScale = 1.0
    }

    /// Intentionally not persisted
    @Published var isDebugging: Bool
    @objc
    @Published var isDebuggingDiscovery: Bool
    @objc
    @Published var isDebuggingNetworkPacket: Bool
    
    private override init() {
        #if targetEnvironment(simulator)
        let defaultBroker = "tcp://127.0.0.1:1883"
        #else
        let defaultBroker = "tcp://192.168.88.191:1883"
        #endif
        UserDefaults.standard.register(defaults: [
            "savePhotosToPhotosLibrary": !DeviceType.isMac,
            "saveVideosToPhotosLibrary": !DeviceType.isMac,
            "stationBrokerUri": defaultBroker,
            "stationId": "1",
            "launchIntoStationMode": true,
            "stationMqttDebug": false,
            "stationUploadUrl": "http://b310-mac:8080/upload",
            "directIPs": ["192.168.88.193"],
            "showConnectionDebug": true,
            "showKeyboardControls": true,
            "keyboardLayout": "english",
            "kbModifiersScale": 1.0,
            "kbCharactersScale": 1.0,
            "kbNumpadScale": 1.0,
            "kbActionsScale": 1.0,
        ])
#if !os(macOS)
        let fallbackName = UIDevice.current.name
#else
        let fallbackName = Host.current().localizedName ?? "Unknown Hostname"
#endif
        self.deviceName = UserDefaults.standard.string(forKey: "deviceName") ?? fallbackName
        self.chosenTheme = UserDefaults.standard.string(forKey: "chosenTheme").flatMap(ColorScheme.init)
        self.directIPs = UserDefaults.standard.stringArray(forKey: "directIPs") ?? []
        self.disableUdpBroadcastDiscovery = UserDefaults.standard.bool(forKey: "disableUdpBroadcastDiscovery")
        self.stationBrokerUri = UserDefaults.standard.string(forKey: "stationBrokerUri") ?? defaultBroker
        self.stationId = UserDefaults.standard.string(forKey: "stationId") ?? "1"
        self.stationTargetDeviceId = UserDefaults.standard.string(forKey: "stationTargetDeviceId")
        self.launchIntoStationMode = UserDefaults.standard.object(forKey: "launchIntoStationMode") as? Bool ?? true
        self.stationMqttDebug = UserDefaults.standard.bool(forKey: "stationMqttDebug")
        self.stationUploadUrl = UserDefaults.standard.string(forKey: "stationUploadUrl") ?? "http://b310-mac:8080/upload"
        self.showConnectionDebug = UserDefaults.standard.object(forKey: "showConnectionDebug") as? Bool ?? true
        self.showKeyboardControls = UserDefaults.standard.object(forKey: "showKeyboardControls") as? Bool ?? true
        self.keyboardLayout = KeyboardLayout(rawValue: UserDefaults.standard.string(forKey: "keyboardLayout") ?? "english") ?? .english
        let modOff = UserDefaults.standard.dictionary(forKey: "kbModifiersOffset")
        self.keyboardModifiersOffset = CGSize(width: modOff?["w"] as? CGFloat ?? -8, height: modOff?["h"] as? CGFloat ?? 75.5)
        let charOff = UserDefaults.standard.dictionary(forKey: "kbCharactersOffset")
        self.keyboardCharactersOffset = CGSize(width: charOff?["w"] as? CGFloat ?? -4, height: charOff?["h"] as? CGFloat ?? 184.5)
        let numOff = UserDefaults.standard.dictionary(forKey: "kbNumpadOffset")
        self.keyboardNumpadOffset = CGSize(width: numOff?["w"] as? CGFloat ?? 65, height: numOff?["h"] as? CGFloat ?? 66)
        let actOff = UserDefaults.standard.dictionary(forKey: "kbActionsOffset")
        self.keyboardActionsOffset = CGSize(width: actOff?["w"] as? CGFloat ?? 130, height: actOff?["h"] as? CGFloat ?? 66)
        self.keyboardModifiersScale = UserDefaults.standard.object(forKey: "kbModifiersScale") as? CGFloat ?? 1.0
        self.keyboardCharactersScale = UserDefaults.standard.object(forKey: "kbCharactersScale") as? CGFloat ?? 1.0
        self.keyboardNumpadScale = UserDefaults.standard.object(forKey: "kbNumpadScale") as? CGFloat ?? 1.0
        self.keyboardActionsScale = UserDefaults.standard.object(forKey: "kbActionsScale") as? CGFloat ?? 1.0
        self.appIcon = AppIcon(rawValue: UserDefaults.standard.string(forKey: "appIcon")) ?? .default
        self.savePhotosToPhotosLibrary = UserDefaults.standard.bool(forKey: "savePhotosToPhotosLibrary")
        self.saveVideosToPhotosLibrary = UserDefaults.standard.bool(forKey: "saveVideosToPhotosLibrary")
        #if DEBUG
        let launchArguments = Set(ProcessInfo.processInfo.arguments)
        self.isDebugging = launchArguments.contains("isDebugging")
        self.isDebuggingDiscovery = launchArguments.contains("isDebuggingDiscovery")
        self.isDebuggingNetworkPacket = launchArguments.contains("isDebuggingNetworkPacket")
        #else
        self.isDebugging = false
        self.isDebuggingDiscovery = false
        self.isDebuggingNetworkPacket = false
        #endif
        super.init()
    }
}

extension ColorScheme: RawRepresentable {
    public typealias RawValue = String
    
    public init?(rawValue: String) {
        switch rawValue {
        case "Light": self = .light
        case "Dark": self = .dark
        default: return nil
        }
    }
    
    public var rawValue: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        @unknown default: return "Unknown"
        }
    }
}

extension Optional where Wrapped == ColorScheme {
    var text: Text {
        switch self {
        case .none:
            return Text("System Default")
        case .some(let scheme):
            switch scheme {
            case .light: return Text("Light")
            case .dark: return Text("Dark")
            @unknown default: return Text("Unknown Theme")
            }
        }
    }
}

extension Optional: CaseIterable where Wrapped: CaseIterable {
    public static var allCases: [Optional<Wrapped>] {
        return [nil] + Wrapped.allCases.map(Self.init)
    }
}

// The host's SHA256 hash, calculated upon launch so we don't have to calculated it every single time
var hostSHA256Hash: String = "ERROR"

// Array of all UTTypes, used by .fileImporter() to allow importing of all file types
let allUTTypes: [UTType] = [
    .aiff, .aliasFile, .appleArchive, .appleProtectedMPEG4Audio,
    .appleProtectedMPEG4Video, .appleScript, .application,
    .applicationBundle, .applicationExtension, .arReferenceObject,
    .archive, .assemblyLanguageSource, .audio, .audiovisualContent,
    .avi, .binaryPropertyList, .bmp, .bookmark, .bundle, .bz2,
    .cHeader, .cPlusPlusHeader, .cPlusPlusSource, .cSource,
    .calendarEvent, .commaSeparatedText, .compositeContent,
    .contact, .content, .data, .database, .delimitedText, .directory,
    .diskImage, .emailMessage, .epub, .exe, .executable, .fileURL,
    .flatRTFD, .folder, .font, .framework, .gif, .gzip, .heic, .html,
    .icns, .ico, .image, .internetLocation, .internetShortcut, .item,
    .javaScript, .jpeg, .json, .livePhoto, .log, .m3uPlaylist,
    /**.makefile (iOS 15 beta),**/ .message, .midi, .mountPoint, .movie, .mp3,
    .mpeg, .mpeg2TransportStream, .mpeg2Video, .mpeg4Audio,
    .mpeg4Movie, .objectiveCPlusPlusSource, .objectiveCSource,
    .osaScript, .osaScriptBundle, .package, .pdf, .perlScript,
    .phpScript, .pkcs12, .plainText, .playlist, .pluginBundle, .png,
    .presentation, .propertyList, .pythonScript, .quickLookGenerator,
    .quickTimeMovie, .rawImage, .realityFile, .resolvable, .rtf, .rtfd,
    .rubyScript, .sceneKitScene, .script, .shellScript, .sourceCode,
    .spotlightImporter, .spreadsheet, .svg, .swiftSource,
    .symbolicLink, .systemPreferencesPane, .tabSeparatedText, .text,
    .threeDContent, .tiff, .toDoItem, .unixExecutable, .url,
    .urlBookmarkData, .usd, .usdz, .utf16ExternalPlainText,
    .utf16PlainText, .utf8PlainText, .utf8TabSeparatedText, .vCard,
    .video, .volume, .wav, .webArchive, .webP, .x509Certificate, .xml,
    .xmlPropertyList, .xpcService, .yaml, .zip,
]
