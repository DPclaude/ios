import Foundation
import CryptoKit
import Security

struct TransferError: LocalizedError {
    let message: String
    var statusCode: Int? = nil
    var terminalTask: Bool = false
    var errorDescription: String? { message }
}
struct Peer: Codable, Equatable {
    var host: String
    var port: Int
    var pin: String
    var secret: String
    var name: String
    var hostname: String
    var token: String = ""
    static func parse(_ raw: String) throws -> Peer {
        guard let c = URLComponents(string: raw), c.scheme == "quicktransfer", c.host == "pair" else { throw TransferError(message: "这不是快捷互传配对码") }
        let items = c.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count else { throw TransferError(message: "配对码包含重复字段") }
        let q = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        let host = q["host"] ?? "", pin = (q["pin"] ?? "").lowercased()
        guard !host.isEmpty, !host.contains("/"), !host.contains("@"), let port = Int(q["port"] ?? "39278"), (1...65535).contains(port), pin.count == 64, pin.allSatisfy({ $0.isHexDigit && $0.isASCII }), !(q["secret"] ?? "").isEmpty else { throw TransferError(message: "配对码内容不完整") }
        return Peer(host: host, port: port, pin: pin, secret: q["secret"]!, name: q["name"] ?? "我的电脑", hostname: q["hostname"] ?? "")
    }
}
struct RemoteTask: Codable, Identifiable {
    var id: String
    var direction: String
    var kind: String
    var name: String
    var text: String?
    var size: Int64
    var offset: Int64
    var hash: String?
    var state: String
}
struct RemoteState: Decodable { var tasks: [RemoteTask] }
struct Receipt: Codable, Identifiable {
    var id: String
    var peerPin: String
    var name: String
    var filename: String?
    var text: String?
    var date: Date
    var acknowledged: Bool
    var needsRecovery: Bool? = nil
    var retryStoppedReason: String? = nil
}
struct Outgoing: Codable, Identifiable {
    var id: String = UUID().uuidString
    var peerPin: String
    var name: String
    var filename: String
    var size: Int64
    var hash: String
    var remoteID: String?
    var status: String = "等待连接"
    var progress: Double = 0
    var cancelled: Bool = false
    var cancelConfirmed: Bool? = nil
    var retryStoppedReason: String? = nil
}
enum QueuePolicy {
    static func isGlobal(_ error: Error) -> Bool {
        if error is CancellationError || error is URLError { return true }
        guard let code = (error as? TransferError)?.statusCode else { return false }
        return code == 401 || code == 403 || code >= 500
    }
    static func isTerminal(_ error: Error) -> Bool {
        guard let e = error as? TransferError else { return false }
        return e.terminalTask || e.statusCode == 404 || (e.statusCode == 400 && e.message.contains("任务不存在"))
    }
    // Global connection/auth failures stop the pass; an individual task failure cannot starve later tasks.
    @MainActor static func run<Item>(_ items: [Item], operation: (Item) async throws -> Void, failed: (Item, Error) throws -> Void) async throws {
        for item in items {
            try Task.checkCancellation()
            do { try await operation(item) }
            catch { if isGlobal(error) { throw error }; try failed(item, error) }
        }
    }
}
enum FilePolicy {
    static func safeName(_ raw: String) -> String {
        var s = String(raw.map { "/\\:\0".contains($0) || $0.asciiValue.map({ $0 < 32 }) == true ? Character("_") : $0 }.prefix(160)).trimmingCharacters(in: .whitespacesAndNewlines)
        while s.utf8.count > 180 { s.removeLast() }
        return s.isEmpty || s == "." || s == ".." ? "未命名文件" : s
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
enum CredentialStore {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.pandong.quicktransfer.peer", kSecAttrAccount as String: "current"]
    static func load() throws -> Peer? {
        var q = query; q[kSecReturnData as String] = true
        var item: CFTypeRef?
        let code = SecItemCopyMatching(q as CFDictionary, &item)
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess, let data = item as? Data else { throw TransferError(message: "无法读取配对凭据（\(code)）") }
        return try JSONDecoder().decode(Peer.self, from: data)
    }
    static func save(_ peer: Peer) throws {
        let data = try JSONEncoder().encode(peer)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecSuccess { return }
        guard result == errSecItemNotFound else { throw TransferError(message: "无法更新配对凭据（\(result)）") }
        var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw TransferError(message: "无法保存配对凭据（\(status)）") }
    }
    static func clear() throws {
        let s = SecItemDelete(query as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw TransferError(message: "无法移除配对凭据") }
    }
}
final class PinnedDelegate: NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    let pin: String
    var progress: ((Double) -> Void)?
    init(pin: String) { self.pin = pin }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let cert = SecTrustGetCertificateAtIndex(trust, 0),
              FilePolicy.digest(SecCertificateCopyData(cert) as Data) == pin else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
}
final class Transport {
    let peer: Peer
    let session: URLSession
    let delegate: PinnedDelegate
    init(_ peer: Peer) {
        self.peer = peer; delegate = PinnedDelegate(pin: peer.pin)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 3600
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    func request(_ path: String, method: String = "GET", body: Data? = nil, query: [String: String] = [:]) throws -> URLRequest {
        var c = URLComponents(); c.scheme = "https"; c.host = peer.host; c.port = peer.port; c.path = path
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = c.url else { throw TransferError(message: "电脑地址无效") }
        var r = URLRequest(url: url); r.httpMethod = method; r.httpBody = body
        if !peer.token.isEmpty { r.setValue("qt_device=\(peer.token)", forHTTPHeaderField: "Cookie") }
        if body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return r
    }
    func raw(_ path: String, method: String = "GET", json: [String: Any]? = nil, query: [String: String] = [:]) async throws -> (Data, Int) {
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        let (data, response) = try await session.data(for: request(path, method: method, body: body, query: query))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        try Self.check(code, data: data)
        return (data, code)
    }
    static func check(_ code: Int, data: Data = Data()) throws {
        guard (200...299).contains(code) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
            throw TransferError(message: object?["error"] ?? (code == 401 ? "配对授权已失效，请在设置中重新连接" : "电脑返回错误 \(code)"), statusCode: code)
        }
    }
    func get<T: Decodable>(_ type: T.Type, _ path: String, method: String = "GET", json: [String: Any]? = nil, query: [String: String] = [:]) async throws -> T {
        let (data, _) = try await raw(path, method: method, json: json, query: query)
        return try JSONDecoder().decode(type, from: data)
    }
}
