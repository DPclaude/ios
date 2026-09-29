import XCTest
import PlannerCore
import PlannerStore
@testable import Planner

private actor GatedStorage: PlannerStorage {
    let backing: PlannerFileStore
    private var gated = false
    private var gate: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    init(directory: URL) { backing = PlannerFileStore(directory: directory) }
    func arm() { gated = true }
    func waitForWrite() async {
        if gate != nil { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func releaseWrite() { let old = gate; gate = nil; old?.resume() }
    func load() async throws -> StoreSnapshot { try await backing.load() }
    func save(_ snapshot: StoreSnapshot) async throws {
        if gated {
            await withCheckedContinuation { continuation in
                gate = continuation; arrival?.resume(); arrival = nil
            }
        }
        try await backing.save(snapshot)
    }
    func replace(with document: PlannerDocument) async throws -> StoreSnapshot { try await backing.replace(with: document) }
    func recoverPreviousImport() async throws -> StoreSnapshot { try await backing.recoverPreviousImport() }
    func decodeBackup(_ data: Data) async throws -> PlannerDocument { try await backing.decodeBackup(data) }
    func readBackup(url: URL) async throws -> PlannerDocument { try await backing.readBackup(url: url) }
    func encodeBackup(_ document: PlannerDocument) async throws -> Data { try await backing.encodeBackup(document) }
}

@MainActor final class PersistenceDrainTests: XCTestCase {
    func testWidgetCompletionWaitsForConcurrentNewerSave() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = GatedStorage(directory: dir)
        var normalPublications = 0, widgetPublications: [PlannerDocument] = []
        let subject = PlannerViewModel(store: store,
            onSnapshotPersist: { _ in normalPublications += 1; return nil },
            onWidgetSnapshotPersist: { widgetPublications.append($0.document); return nil })
        await subject.load()
        subject.perform(.add(text: "桌面完成", category: 0, day: .today(), repeating: false)); await subject.flush()
        normalPublications = 0
        let saved = try await store.load(), reference = subject.snapshot.open[0].reference
        await store.arm()
        var returned = false
        let completion = Task { @MainActor in
            defer { returned = true }
            try await subject.completeFromWidget(reference, generation: saved.generation, day: .today())
        }
        await store.waitForWrite()
        subject.perform(.add(text: "同时新增", category: 0, day: .today(), repeating: false))
        await store.releaseWrite()
        await store.waitForWrite()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(returned, "Intent returned while its publishing revision was still saving")
        await store.releaseWrite()
        try await completion.value
        XCTAssertEqual(subject.saveState, .saved)
        let actual = try await store.load()
        XCTAssertEqual(actual.document.tasks.count, 2)
        XCTAssertTrue(actual.document.tasks[0].done)
        XCTAssertEqual(normalPublications, 0)
        XCTAssertEqual(widgetPublications, [actual.document], "Only the final durable revision should be published")
    }
}
