/*
 * SPDX-FileCopyrightText: 2026 station-mode contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import CocoaMQTT
import Foundation

protocol StationMqttListener: AnyObject {
    func onControlMessage(_ control: [String: Any])
}

enum StationDistance: String {
    case near, mid, far
}

enum StationEvent {
    case textSent(text: String)
    case visitorEntered(side: String, distance: StationDistance)
    case visitorDistanceChanged(distance: StationDistance)
    case visitorApproached
    case visitorLeft

    var name: String {
        switch self {
        case .textSent: return "text_sent"
        case .visitorEntered: return "visitor_entered"
        case .visitorDistanceChanged: return "visitor_distance_changed"
        case .visitorApproached: return "visitor_approached"
        case .visitorLeft: return "visitor_left"
        }
    }

    func payload() -> [String: Any] {
        var payload: [String: Any] = [
            "id": UUID().uuidString,
            "ts": Int64(Date().timeIntervalSince1970 * 1000),
            "src": StationMqttClient.source,
            "event": name,
        ]
        switch self {
        case .textSent(let text):
            payload["text"] = text
        case .visitorEntered(let side, let distance):
            payload["side"] = side
            payload["distance"] = distance.rawValue
        case .visitorDistanceChanged(let distance):
            payload["distance"] = distance.rawValue
        default:
            break
        }
        return payload
    }
}

final class StationMqttClient: CocoaMQTTDelegate {
    static let source = "ios-remote"
    private static let qos = CocoaMQTTQoS.qos1

    private struct PendingPublish {
        let topic: String
        let json: String
        let queuedAt: Date
    }

    private var mqtt: CocoaMQTT?
    private weak var listener: StationMqttListener?
    private let stationId: String
    private let brokerUri: String
    private let logger = Logger(category: "StationMqttClient")
    private let stateLock = NSLock()
    private var connectionReady = false
    private var pendingPublishes: [PendingPublish] = []
    private let maxPendingPublishes = 32
    private let pendingPublishTTL: TimeInterval = 3

    private var controlTopic: String {
        "station/\(stationId)/ui/control"
    }

    private var eventTopic: String {
        "station/\(stationId)/ui/event"
    }

    init(brokerUri: String, stationId: String, listener: StationMqttListener) {
        self.brokerUri = brokerUri
        self.stationId = stationId
        self.listener = listener
    }

    func connect() {
        guard let url = URL(string: brokerUri) else {
            logger.error("Invalid broker URI: \(self.brokerUri)")
            return
        }
        guard let host = url.host else {
            logger.error("No host in broker URI: \(self.brokerUri)")
            return
        }
        let port = UInt16(url.port ?? 1883)
        logger.info("Connecting to \(host):\(port)")

        let clientId = "ios-remote-\(UUID().uuidString.prefix(8))"
        let mqtt = CocoaMQTT(clientID: clientId, host: host, port: port)
        mqtt.cleanSession = true
        mqtt.autoReconnect = true
        mqtt.delegate = self
        mqtt.keepAlive = 60
        self.mqtt = mqtt

        _ = mqtt.connect()
    }

    func disconnect() {
        logger.info("Disconnecting")
        stateLock.lock()
        connectionReady = false
        pendingPublishes.removeAll()
        stateLock.unlock()
        mqtt?.autoReconnect = false
        mqtt?.disconnect()
        mqtt = nil
    }

    private func publish(_ json: String, to topic: String) {
        guard let mqtt else {
            logger.error("Cannot publish: MQTT client is not initialized")
            return
        }

        stateLock.lock()
        let ready = connectionReady
        if !ready {
            let now = Date()
            pendingPublishes = pendingPublishes.filter {
                now.timeIntervalSince($0.queuedAt) < pendingPublishTTL
            }
            if pendingPublishes.count >= maxPendingPublishes {
                pendingPublishes.removeFirst()
            }
            pendingPublishes.append(PendingPublish(topic: topic, json: json, queuedAt: now))
        }
        stateLock.unlock()

        if ready {
            mqtt.publish(topic, withString: json, qos: Self.qos, retained: false)
        } else {
            logger.info("Queueing MQTT event until reconnect")
        }
    }

    func publishEvent(_ event: StationEvent) {
        let payload = event.payload()
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        logger.info("Publishing to \(self.eventTopic): \(json)")
        publish(json, to: eventTopic)
    }

    func publishRemoteSlider(value: Double, seq: Int, confirm: Bool = false) {
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "ts": Int64(Date().timeIntervalSince1970 * 1000),
            "src": StationMqttClient.source,
            "event": "remote_slider",
            "data": [
                "value": min(1, max(0, value)),
                "seq": seq,
                "confirm": confirm,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        logger.info("Publishing slider to \(self.eventTopic): \(json)")
        publish(json, to: eventTopic)
    }

    func publishRemoteOperator(_ action: String) {
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "ts": Int64(Date().timeIntervalSince1970 * 1000),
            "src": StationMqttClient.source,
            "event": "operator_\(action)",
            "data": [:],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        logger.info("Publishing operator to \(self.eventTopic): \(json)")
        publish(json, to: eventTopic)
    }

    func publishRemoteKey(
        key: String? = nil,
        special: String? = nil,
        alt: Bool = false,
        shift: Bool = false
    ) {
        var data: [String: Any] = [:]
        if let key, !key.isEmpty {
            data["key"] = key
        }
        if let special, !special.isEmpty {
            data["special"] = special
        }
        if alt { data["alt"] = true }
        if shift { data["shift"] = true }
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "ts": Int64(Date().timeIntervalSince1970 * 1000),
            "src": StationMqttClient.source,
            "event": "remote_key",
            "data": data,
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: encoded, encoding: .utf8) else { return }
        logger.info("Publishing remote key to \(self.eventTopic): \(json)")
        publish(json, to: eventTopic)
    }

    // MARK: - CocoaMQTTDelegate

    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        logger.info("Connect ack: \(ack)")
        guard ack == .accept else {
            stateLock.lock()
            connectionReady = false
            stateLock.unlock()
            return
        }

        stateLock.lock()
        connectionReady = true
        let now = Date()
        let queued = pendingPublishes.filter {
            now.timeIntervalSince($0.queuedAt) < pendingPublishTTL
        }
        pendingPublishes.removeAll()
        stateLock.unlock()

        logger.info("Subscribing to \(self.controlTopic) and \(self.eventTopic)")
        mqtt.subscribe(controlTopic, qos: Self.qos)
        mqtt.subscribe(eventTopic, qos: Self.qos)
        for item in queued {
            logger.info("Flushing queued MQTT event")
            mqtt.publish(item.topic, withString: item.json, qos: Self.qos, retained: false)
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        logger.info("Subscribed: \(success), failed: \(failed)")
    }

    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        logger.info("Unsubscribed: \(topics)")
    }

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        logger.info("Received on \(message.topic)")
        guard let jsonData = message.string?.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: jsonData),
              let payload = Self.dictionary(raw)
        else { return }

        if message.topic == controlTopic || message.topic.hasSuffix("/ui/control") {
            if payload["ts"] == nil || !(payload["src"] is String) || !(payload["action"] is String) {
                return
            }
            listener?.onControlMessage(payload)
            return
        }

        if message.topic == eventTopic || message.topic.hasSuffix("/ui/event") {
            guard let control = Self.keyboardFocusControl(from: payload) else { return }
            listener?.onControlMessage(control)
        }
    }

    /// Maps a kiosk `keyboard_focus` event onto the same control actions the
    /// remote already understands (letters / yes-no / slider / hidden).
    static func keyboardFocusControl(from payload: [String: Any]) -> [String: Any]? {
        guard (payload["event"] as? String) == "keyboard_focus" else { return nil }
        guard let ts = payload["ts"], let src = payload["src"] as? String else { return nil }
        let data = dictionary(payload["data"]) ?? [:]
        let mode = (data["mode"] as? String) ?? (payload["mode"] as? String) ?? ""
        let action: String
        switch mode {
        case "numeric": action = "textFocused" // number row lives on the letter keyboard
        case "yesno": action = "yesNoFocused"
        case "choice": action = "choiceFocused"
        case "scale": action = "scaleFocused"
        case "hidden": action = "keyboardHidden"
        case "text": action = "textFocused"
        default: return nil
        }
        var control: [String: Any] = [
            "ts": ts,
            "src": src,
            "action": action,
        ]
        if let left = (data["left"] as? String) ?? (payload["left"] as? String), !left.isEmpty {
            control["left"] = left
        }
        if let right = (data["right"] as? String) ?? (payload["right"] as? String), !right.isEmpty {
            control["right"] = right
        }
        if let value = data["value"] ?? payload["value"] {
            control["value"] = value
        }
        if let prompt = (data["prompt"] as? String) ?? (payload["prompt"] as? String) {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                control["prompt"] = trimmed
            }
        }
        if let seq = data["seq"] ?? payload["seq"] {
            control["seq"] = seq
        }
        return control
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            return dict
        }
        if let dict = value as? NSDictionary {
            var result: [String: Any] = [:]
            for (key, val) in dict {
                if let key = key as? String {
                    result[key] = val
                }
            }
            return result
        }
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            return dictionary(obj)
        }
        return nil
    }

    func mqttDidPing(_ mqtt: CocoaMQTT) {}

    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        stateLock.lock()
        connectionReady = false
        stateLock.unlock()
        logger.error("Disconnected: \(err?.localizedDescription ?? "no error")")
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}

    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}

    func mqtt(_ mqtt: CocoaMQTT, didReceiveTrust trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

/// Suppresses retained-control + ui/event duplicates and stale MQTT delivery.
/// The station bridge publishes a control message and the corresponding
/// keyboard_focus event separately; both describe the same displayed state.
struct StationFocusControlGate {
    private(set) var lastSignature: String = ""
    private(set) var lastTimestamp: Int64?

    mutating func accept(_ control: [String: Any]) -> Bool {
        let signature = Self.signature(for: control)
        guard !signature.isEmpty else { return false }
        let timestamp = Self.int64(control["ts"])
        if let lastTimestamp, let timestamp, timestamp < lastTimestamp {
            return false
        }
        guard signature != lastSignature else {
            if let timestamp, timestamp > (lastTimestamp ?? 0) {
                lastTimestamp = timestamp
            }
            return false
        }
        lastSignature = signature
        if let timestamp {
            lastTimestamp = max(timestamp, lastTimestamp ?? timestamp)
        }
        return true
    }

    static func signature(for control: [String: Any]) -> String {
        let action = control["action"] as? String ?? ""
        guard !action.isEmpty else { return "" }
        let left = control["left"] as? String ?? ""
        let right = control["right"] as? String ?? ""
        let prompt = (control["prompt"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return [action, left, right, prompt].joined(separator: "\u{1}")
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        return nil
    }
}

/// HTTP loopback used on the Simulator: the local Vite kiosk at :5176
/// publishes `keyboard_focus` and receives remote keys. Production iPads
/// keep using MQTT + KDE Connect and never hit this path.
final class StationKioskLoopback {
    private let baseURL: URL
    private let stationId: String
    private let onControl: ([String: Any]) -> Void
    private var timer: Timer?
    private var lastFocusJSON: String = ""

    static func baseURL(from brokerUri: String) -> URL? {
        guard let url = URL(string: brokerUri), let host = url.host else { return nil }
        let loopback = host == "127.0.0.1" || host == "localhost" || host == "::1"
        guard loopback else { return nil }
        return URL(string: "http://127.0.0.1:5176")
    }

    init(baseURL: URL, stationId: String, onControl: @escaping ([String: Any]) -> Void) {
        self.baseURL = baseURL
        self.stationId = stationId
        self.onControl = onControl
    }

    func start() {
        stop()
        poll()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func sendKey(_ key: String, alt: Bool = false, shift: Bool = false) {
        var payload: [String: Any] = ["station": stationId, "key": key]
        if alt {
            payload["alt"] = true
        }
        if shift {
            payload["shift"] = true
        }
        post(payload)
    }

    func sendSpecial(_ name: String) {
        post(["station": stationId, "special": name])
    }

    func sendSlider(_ value: Double, seq: Int) {
        post(["station": stationId, "slider": min(1, max(0, value)), "seq": seq])
    }

    private func poll() {
        guard let url = URL(string: "\(baseURL.absoluteString)/__hons/keyboard-focus?station=\(stationId)") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let json = String(data: data, encoding: .utf8) else { return }
            guard json != self.lastFocusJSON else { return }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let envelope: [String: Any] = [
                "event": "keyboard_focus",
                "ts": Int64(Date().timeIntervalSince1970 * 1000),
                "src": "loopback",
                "data": obj,
            ]
            guard let control = StationMqttClient.keyboardFocusControl(from: envelope) else { return }
            self.lastFocusJSON = json
            DispatchQueue.main.async {
                self.onControl(control)
            }
        }.resume()
    }

    private func post(_ payload: [String: Any]) {
        guard let url = URL(string: "\(baseURL.absoluteString)/__hons/remote-key") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: request).resume()
    }
}
