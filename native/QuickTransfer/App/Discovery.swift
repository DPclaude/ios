import Foundation

@MainActor final class Discovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var hostname = ""
    private var resolved: ((String) -> Void)?
    func start(hostname: String, resolved: @escaping (String) -> Void) {
        stop(); self.hostname = hostname.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")); self.resolved = resolved
        browser.delegate = self; browser.searchForServices(ofType: "_quicktransfer._tcp.", inDomain: "local.")
    }
    func stop() { browser.stop(); services.forEach { $0.stop() }; services = [] }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service); service.delegate = self; service.resolve(withTimeout: 5)
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName, host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == hostname else { return }
        resolved?(host)
    }
}
