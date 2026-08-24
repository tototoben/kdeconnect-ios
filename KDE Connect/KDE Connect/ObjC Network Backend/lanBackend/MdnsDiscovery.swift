/*
 * SPDX-FileCopyrightText: 2023 Albert Vaca Cintora <albertvaka@gmail.com>
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import Foundation
import Network

@objc
public class MDNSDiscovery: NSObject, NetServiceDelegate {
    private static let serviceType = "_kdeconnect._udp"
    private static let domain = ""
    private var browser: NWBrowser?
    private var service: NetService?
    private var tcpPort: UInt16 = 0

    private static let logger = Logger()

    @objc
    public func startDiscovering() {
        if (self.browser != nil) {
            Self.logger.debug("MDNS Already discovering")
            return
        }
        Self.logger.debug("MDNS Start discovering")
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: Self.domain), using: parameters)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                Self.logger.error("MDNS Discovery failed with \(error)")
            case .ready:
                Self.logger.info("MDNS Discovery ready with \(browser.browseResults.count) results")
                self.processBrowserResults(browser.browseResults)
            case .cancelled:
                Self.logger.info("MDNS Discovery cancelled")
            case .waiting(let error):
                Self.logger.info("MDNS Discovery waiting: \(error)")
            case .setup:
                break
            @unknown default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Self.logger.info("MDNS Discovery found \(results.count) results")
            self?.processBrowserResults(results)
        }

        browser.start(queue: .main)
    }

    @objc
    public func startAnnouncing(tcpPort: UInt16) {
        if (self.service != nil) {
            Self.logger.debug("MDNS Already announcing")
            return
        }
        Self.logger.debug("MDNS Start announcing")

        self.tcpPort = tcpPort

        let ownDeviceInfo = DeviceInfo.getOwn()
        // We can't use NWListener until allowLocalEndpointReuse is fixed
        // https://developer.apple.com/forums/thread/129452
        // https://openradar.appspot.com/FB8658821
        let service = NetService(
            domain: Self.domain,
            type: Self.serviceType,
            name: ownDeviceInfo.id,
            port: Int32(tcpPort)
        )
        self.service = service
        service.setTXTRecord(Self.deviceInfoToMdnsData(ownDeviceInfo: ownDeviceInfo))
        service.includesPeerToPeer = true
        service.delegate = self
        service.publish()
    }

    @objc
    public func stopDiscovering() {
        Self.logger.debug("MDNS Stop discovering")
        browser?.cancel()
        browser = nil
    }

    @objc
    public func stopAnnouncing() {
        Self.logger.debug("MDNS Stop announcing")
        service?.stop()
        service = nil
    }

    deinit {
        stopDiscovering()
        stopAnnouncing()
    }

    public func netServiceDidPublish(_ sender: NetService) {
        Self.logger.debug("MDNS announced \(sender.name)")
    }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        Self.logger.fault("MDNS announcing failed with \(NetService.error(from: errorDict))")
    }

    public func netServiceDidStop(_ sender: NetService) {
        Self.logger.debug("MDNS stopped anouncing")
    }

    private var resolvedConnections: Set<String> = []
    private var activeResolvers: [String: DnsResolver] = [:]

    private func processBrowserResults(_ results: Set<NWBrowser.Result>) {
        let ownDeviceId = KdeConnectSettings.getUUID()
        for result in results {
            if case let .service(name: name, type: _, domain: domain, interface: _) = result.endpoint {
                if name == ownDeviceId {
                    Self.logger.info("MDNS ignoring myself")
                    continue
                }
                Self.logger.info("MDNS found \(name)")
                resolveService(name: name, type: Self.serviceType, domain: domain)
            }
        }
    }

    private func resolveService(name: String, type: String, domain: String) {
        if resolvedConnections.contains(name) {
            Self.logger.debug("MDNS already resolving \(name), skipping")
            return
        }
        resolvedConnections.insert(name)

        let service = NetService(domain: domain, type: type, name: name)
        let resolver = DnsResolver(service: service, tcpPort: self.tcpPort) { [weak self] in
            self?.resolvedConnections.remove(name)
            self?.activeResolvers.removeValue(forKey: name)
        }
        activeResolvers[name] = resolver
        resolver.resolve()
    }

    fileprivate static func deviceInfoToMdnsData(ownDeviceInfo: DeviceInfo) -> Data {
        let record = [
            "id": Data(ownDeviceInfo.id.utf8),
            "name": Data(ownDeviceInfo.name.utf8),
            "type": Data(ownDeviceInfo.getTypeAsString().utf8),
            "protocol": Data("\(ownDeviceInfo.protocolVersion)".utf8),
        ]
        let data = NetService.data(fromTXTRecord: record)
        switch data.count {
        case ...512:
            logger.debug("TXT record size: \(data.count) bytes, okay")
        case ...65535:
            logger.error("TXT record size: \(data.count) bytes, exceeds the maximum RECOMMENDED size of 512 bytes")
        default:
            logger.fault("TXT record size: \(data.count) bytes, exceeds the maximum size of 65535 bytes")
        }
        return data
    }
}

extension NetService {
    static func error(from errorDict: [String: NSNumber]) -> NSError {
        let code = errorDict[NetService.errorCode]
            .flatMap { NetService.ErrorCode(rawValue: $0.intValue) }
            ?? .unknownError
        return NSError(domain: NetService.errorDomain, code: code.rawValue)
    }
}

/// Resolves a Bonjour service to an IP address and sends a KDE Connect identity
/// packet via a direct NWConnection. This avoids the NECP flow failures that
/// occur when connecting directly to a bonjour endpoint.
private class DnsResolver: NSObject, NetServiceDelegate {
    private static let logger = Logger(category: "DnsResolver")

    private let service: NetService
    private let tcpPort: UInt16
    private let onComplete: () -> Void

    init(service: NetService, tcpPort: UInt16, onComplete: @escaping () -> Void) {
        self.service = service
        self.tcpPort = tcpPort
        self.onComplete = onComplete
        super.init()
    }

    func resolve() {
        Self.logger.info("Resolving \(self.service.name)")
        self.service.delegate = self
        self.service.resolve(withTimeout: 5.0)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        Self.logger.info("Resolved \(sender.name) to \(sender.hostName ?? "?") port \(sender.port)")
        guard let hostName = sender.hostName, sender.port > 0 else {
            Self.logger.error("Resolved \(sender.name) but no host/port")
            onComplete()
            return
        }

        let np = NetworkPacket.createIdentity()
        np.setInteger(Int(tcpPort), forKey: "tcpPort")
        let data = np.serialize()

        let host = NWEndpoint.Host(hostName)
        let port = NWEndpoint.Port(integerLiteral: UInt16(sender.port))
        let connection = NWConnection(host: host, port: port, using: .udp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Self.logger.info("Sending identity to \(hostName):\(sender.port)")
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error = error {
                        Self.logger.error("Send failed: \(error)")
                    } else {
                        Self.logger.info("Identity sent successfully")
                    }
                    connection.cancel()
                })
            case .failed(let error):
                Self.logger.error("Connection failed: \(error)")
                connection.cancel()
            case .waiting(let error):
                Self.logger.info("Connection waiting: \(error)")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Self.logger.error("Failed to resolve \(sender.name): \(NetService.error(from: errorDict))")
        onComplete()
    }

    deinit {
        service.delegate = nil
    }
}
