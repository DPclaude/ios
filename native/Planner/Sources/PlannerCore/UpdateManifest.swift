import Foundation

public struct UpdateManifest: Decodable, Sendable {
    public let version: String
    public let downloadURL: URL
    public let notes: String
    public static let endpoint = URL(string: "https://github.com/DPclaude/ios/releases/latest/download/planner-update.json")!
    public static let sourceURL = URL(string: "https://github.com/DPclaude/ios/releases/latest/download/planner-source.json")!
    public static func validated(data: Data) throws -> Self {
        guard data.count <= 100_000 else { throw UpdateError.invalid }
        let value = try JSONDecoder().decode(Self.self, from: data)
        let url = value.downloadURL
        guard components(value.version) != nil, url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              url.path.hasPrefix("/DPclaude/ios/releases/download/"), url.pathExtension == "ipa",
              !url.pathComponents.contains(".."), value.notes.count <= 10_000 else { throw UpdateError.invalid }
        return value
    }
    public func isNewer(than installed: String) -> Bool {
        guard let remote = Self.components(version), let local = Self.components(installed) else { return false }
        return local.lexicographicallyPrecedes(remote)
    }
    public var sideStoreURL: URL { Self.sideStore(action: "install", url: downloadURL) }
    public static var addSourceURL: URL { sideStore(action: "source", url: sourceURL) }
    private static func sideStore(action: String, url: URL) -> URL {
        var components = URLComponents()
        components.scheme = "sidestore"; components.host = action
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components.url!
    }
    private static func components(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } && ($0.count == 1 || $0.first != "0") }) else { return nil }
        let values = parts.compactMap { Int($0) }
        return values.count == 3 ? values : nil
    }
}
public enum UpdateError: LocalizedError {
    case invalid
    public var errorDescription: String? { "更新信息无效，请稍后重试。当前版本仍可继续使用。" }
}
