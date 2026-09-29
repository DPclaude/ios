import Foundation
import PlannerCore

public struct StoreSnapshot: Codable, Equatable, Sendable {
    public var document: PlannerDocument
    public var generation: UUID
    public var revision: UInt64
    public init(document: PlannerDocument, generation: UUID = UUID(), revision: UInt64 = 0) {
        self.document = document; self.generation = generation; self.revision = revision
    }
}
public enum StoreError: LocalizedError {
    case staleWrite, unsupportedVersion
    public var errorDescription: String? {
        switch self {
        case .staleWrite: return "数据已更新，较旧的保存请求已停止。"
        case .unsupportedVersion: return "数据来自更新版本，请先更新计划本。"
        }
    }
}
public actor PlannerFileStore {
    private struct Envelope: Codable { var schemaVersion = 1; var snapshot: StoreSnapshot }
    private let directory: URL
    private var current: StoreSnapshot?
    private var file: URL { directory.appendingPathComponent("planner.json") }
    private var backup: URL { directory.appendingPathComponent("before-import.json") }
    public init(directory: URL) { self.directory = directory }

    public func load() throws -> StoreSnapshot {
        if let current { return current }
        let loaded: StoreSnapshot
        if FileManager.default.fileExists(atPath: file.path) {
            loaded = try decodeEnvelope(Data(contentsOf: file))
        } else {
            loaded = StoreSnapshot(document: PlannerDocument())
        }
        current = loaded
        return loaded
    }
    public func save(_ snapshot: StoreSnapshot) throws {
        let existing = try load()
        guard snapshot.generation == existing.generation, snapshot.revision >= existing.revision else { throw StoreError.staleWrite }
        try write(snapshot, to: file)
        current = snapshot
    }
    public func replace(with document: PlannerDocument) throws -> StoreSnapshot {
        try BackupCodec.validate(document)
        let old = try load()
        let replacement = StoreSnapshot(document: document)
        let encoded = try encodeEnvelope(replacement)
        try write(old, to: backup)
        try encoded.write(to: file, options: .atomic)
        current = replacement
        return replacement
    }
    public func recoverPreviousImport() throws -> StoreSnapshot {
        let original = try decodeEnvelope(Data(contentsOf: backup))
        let restored = StoreSnapshot(document: original.document)
        try write(restored, to: file)
        current = restored
        return restored
    }
    public func decodeBackup(_ data: Data) throws -> PlannerDocument { try BackupCodec.decode(data) }
    public func readBackup(url: URL) throws -> PlannerDocument { try BackupCodec.decode(Data(contentsOf: url)) }
    public func encodeBackup(_ document: PlannerDocument) throws -> Data { try BackupCodec.encode(document) }
    private func decodeEnvelope(_ data: Data) throws -> StoreSnapshot {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.schemaVersion == 1 else { throw StoreError.unsupportedVersion }
        try BackupCodec.validate(envelope.snapshot.document)
        return envelope.snapshot
    }
    private func encodeEnvelope(_ snapshot: StoreSnapshot) throws -> Data {
        try BackupCodec.validate(snapshot.document)
        return try JSONEncoder().encode(Envelope(snapshot: snapshot))
    }
    private func write(_ snapshot: StoreSnapshot, to destination: URL) throws {
        let data = try encodeEnvelope(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }
}
