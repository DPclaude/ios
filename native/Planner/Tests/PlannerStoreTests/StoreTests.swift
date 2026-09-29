import Foundation
import XCTest
import PlannerCore
@testable import PlannerStore

final class StoreTests: XCTestCase, @unchecked Sendable {
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testLatestRevisionWinsAndSurvivesReopen() async throws {
        let url = try directory(), store = PlannerFileStore(directory: url)
        var snapshot = try await store.load()
        snapshot.revision = 2; snapshot.document.notes["2026-09-29"] = "最新"
        try await store.save(snapshot)
        snapshot.revision = 1; snapshot.document.notes["2026-09-29"] = "旧"
        do { try await store.save(snapshot); XCTFail("stale write accepted") } catch {}
        let reopened = try await PlannerFileStore(directory: url).load()
        XCTAssertEqual(reopened.document.notes["2026-09-29"], "最新")
    }
    func testImportRejectsOldGenerationAndCanRecover() async throws {
        let url = try directory(), store = PlannerFileStore(directory: url)
        var old = try await store.load(); old.revision = 1
        old.document.notes["2026-09-29"] = "原有"
        try await store.save(old)
        var imported = PlannerDocument(); imported.notes["2026-09-29"] = "导入"
        _ = try await store.replace(with: imported)
        old.revision = 100
        do { try await store.save(old); XCTFail("old generation accepted") } catch {}
        let result = try await store.recoverPreviousImport()
        XCTAssertEqual(result.document.notes["2026-09-29"], "原有")
    }
    func testCorruptFileIsNotOverwritten() async throws {
        let url = try directory(), file = url.appendingPathComponent("planner.json")
        let corrupt = Data("not json".utf8); try corrupt.write(to: file)
        let store = PlannerFileStore(directory: url)
        do { _ = try await store.load(); XCTFail("corruption ignored") } catch {}
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
    func testFailedBackupLeavesCurrentFileUnchanged() async throws {
        let url = try directory(), store = PlannerFileStore(directory: url)
        var snapshot = try await store.load(); snapshot.revision = 1
        snapshot.document.notes["2026-09-29"] = "不能丢"
        try await store.save(snapshot)
        let before = try Data(contentsOf: url.appendingPathComponent("planner.json"))
        try FileManager.default.createDirectory(at: url.appendingPathComponent("before-import.json"), withIntermediateDirectories: true)
        do { _ = try await store.replace(with: PlannerDocument()); XCTFail("backup failure ignored") } catch {}
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("planner.json")), before)
    }
    func testInvalidImportDoesNotTouchFile() async throws {
        let url = try directory(), store = PlannerFileStore(directory: url)
        var snapshot = try await store.load(); snapshot.revision = 1
        try await store.save(snapshot)
        var invalid = PlannerDocument(); invalid.notes["bad-date"] = "x"
        do { _ = try await store.replace(with: invalid); XCTFail("invalid imported") } catch {}
        let loaded = try await store.load()
        XCTAssertEqual(loaded, snapshot)
    }
}
