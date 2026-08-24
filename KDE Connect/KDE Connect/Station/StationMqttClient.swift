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
    case yes
    // swiftlint:disable:next identifier_name
    case no
    case visitorEntered(side: String, distance: StationDistance)
    case visitorDistanceChanged(distance: StationDistance)
    case visitorApproached
    case visitorLeft

    var name: String {
        switch self {
        case .yes: return "yes"
        case .no: return "no"
        case .visitorEntered: return "visitor_entered"
        case .visitorDistanceChanged: return "visitor_distance_changed"
        case .visitorApproached: return "visitor_approached"
        case .visitorLeft: return "visitor_left"
        }
    }

    func payload() -> [String: Any] {
        var payload: [String: Any] = [
            "ts": Int64(Date().timeIntervalSince1970 * 1000),
            "src": StationMqttClient.source,
            "event": name,
        ]
        switch self {
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

    private var mqtt: CocoaMQTT?
    private weak var listener: StationMqttListener?
    private let stationId: String
    private let brokerUri: String
    private let logger = Logger(category: "StationMqttClient")

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
        mqtt?.disconnect()
        mqtt = nil
    }

    func publishEvent(_ event: StationEvent) {
        guard let mqtt = mqtt else {
            logger.error("Cannot publish: mqtt is nil")
            return
        }
        let payload = event.payload()
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        logger.info("Publishing to \(self.eventTopic): \(json)")
        mqtt.publish(eventTopic, withString: json, qos: Self.qos, retained: false)
    }

    // MARK: - CocoaMQTTDelegate

    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        logger.info("Connect ack: \(ack)")
        if ack == .accept {
            logger.info("Subscribing to \(self.controlTopic)")
            mqtt.subscribe(controlTopic, qos: Self.qos)
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
        guard message.topic == controlTopic else { return }
        guard let data = message.string,
              let jsonData = data.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return }

        if payload["ts"] == nil || payload["src"] == nil || payload["action"] == nil {
            return
        }
        listener?.onControlMessage(payload)
    }

    func mqttDidPing(_ mqtt: CocoaMQTT) {}

    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        logger.error("Disconnected: \(err?.localizedDescription ?? "no error")")
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}

    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}

    func mqtt(_ mqtt: CocoaMQTT, didReceiveTrust trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}
