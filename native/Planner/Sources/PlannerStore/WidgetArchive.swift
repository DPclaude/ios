import Foundation
import PlannerCore

public enum WidgetArchive {
    private struct Envelope: Codable { var schemaVersion = 1; let document: PlannerDocument; var generation: UUID? }
    // Only the main app writes this derived copy. The widget never mutates private storage.
    public static func write(document: PlannerDocument, generation: UUID? = nil, to file: URL) throws {
        try BackupCodec.validate(document)
        let data = try JSONEncoder().encode(Envelope(document: document, generation: generation))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
    public static func read(from file: URL) throws -> PlannerDocument {
        try readState(from: file).document
    }
    public static func readState(from file: URL) throws -> (document: PlannerDocument, generation: UUID?) {
        let value = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file))
        guard value.schemaVersion == 1 else { throw StoreError.unsupportedVersion }
        try BackupCodec.validate(value.document)
        return (value.document, value.generation)
    }
}
