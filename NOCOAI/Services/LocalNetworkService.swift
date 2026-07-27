import Foundation
import Network

/// Löst den iOS-Lokalnetz-Dialog aus (Einstellungen → NOCO AI → Lokales Netzwerk).
enum LocalNetworkService {
    private static var keepAlive: [AnyObject] = []

    static func warmUp(targetHost: String, port: Int) {
        triggerBonjourBrowse()
        triggerTCPProbe(host: targetHost, port: port)
    }

    private static func triggerBonjourBrowse() {
        let browser = NWBrowser(for: .bonjour(type: "_noco._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { _ in }
        browser.browseResultsChangedHandler = { _, _ in }
        browser.start(queue: .global(qos: .utility))
        keepAlive.append(browser)

        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            browser.cancel()
            keepAlive.removeAll { $0 === browser }
        }
    }

    private static func triggerTCPProbe(host: String, port: Int) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection.stateUpdateHandler = { _ in }
        connection.start(queue: .global(qos: .utility))
        keepAlive.append(connection)

        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            connection.cancel()
            keepAlive.removeAll { $0 === connection }
        }
    }
}
