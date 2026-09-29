import XCTest
import PlannerCore
import PlannerStore
@testable import Planner

@MainActor final class PlannerViewModelTests: XCTestCase {
    func model() throws -> (PlannerViewModel, PlannerFileStore) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PlannerFileStore(directory: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let now = Day(rawValue: "2026-09-29")!.date(timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        return (PlannerViewModel(store: store, now: { now }, timeZone: { TimeZone(identifier: "Asia/Shanghai")! }), store)
    }
    func testNoteRetainsItsOriginalDateAfterNavigation() async throws {
        let (model, store) = try model(); await model.load()
        let day = Day(rawValue: "2026-09-29")!
        model.updateNote("甲", for: day)
        model.select(day: Day(rawValue: "2026-09-30")!)
        await model.flush()
        let saved = try await store.load()
        XCTAssertEqual(saved.document.notes["2026-09-29"], "甲")
        XCTAssertNil(saved.document.notes["2026-09-30"])
    }
    func testRapidChangesSaveLatestState() async throws {
        let (model, store) = try model(); await model.load()
        for i in 0..<30 { model.perform(.add(text: "任务\(i)", category: 0, day: model.selectedDay, repeating: false)) }
        let rows = model.snapshot.open
        for row in rows { model.perform(.toggle(row.reference)) }
        await model.flush()
        let saved = try await store.load()
        XCTAssertEqual(saved.document.tasks.count, 30)
        XCTAssertEqual(saved.document.tasks.filter(\.done).count, 30)
        XCTAssertEqual(model.saveState, .saved)
    }
    func testUndoDoesNotLoseSubsequentEditAndExpires() async throws {
        let (model, _) = try model(); await model.load()
        model.perform(.add(text: "保留", category: 0, day: model.selectedDay, repeating: false))
        let first = model.snapshot.open[0].reference
        model.perform(.delete(first))
        model.perform(.add(text: "新增", category: 0, day: model.selectedDay, repeating: false))
        let base = model.selectedDay.date(timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        model.undoDelete(now: base.addingTimeInterval(6))
        XCTAssertEqual(Set(model.document.tasks.map(\.text)), ["保留", "新增"])
        model.perform(.delete(first))
        model.undoDelete(now: base.addingTimeInterval(8))
        XCTAssertEqual(model.document.tasks.map(\.text), ["新增"])
        await model.flush()
    }
    func testInvalidImportDoesNotChangeVisibleData() async throws {
        let (model, _) = try model(); await model.load()
        model.perform(.add(text: "原有", category: 0, day: model.selectedDay, repeating: false))
        do { _ = try await model.prepareImport(data: Data("{}".utf8)); XCTFail("invalid accepted") } catch {}
        XCTAssertEqual(model.document.tasks.map(\.text), ["原有"])
        await model.flush()
    }
    func testImportFlushesPendingNoteAndInvalidatesUndo() async throws {
        let (model, store) = try model(); await model.load()
        model.updateNote("导入前", for: model.selectedDay)
        let preview = try await model.prepareImport(data: Data(#"{"tasks":[]}"#.utf8))
        try await model.confirmImport(preview)
        XCTAssertTrue(model.document.notes.isEmpty)
        let previous = try await store.recoverPreviousImport()
        XCTAssertEqual(previous.document.notes["2026-09-29"], "导入前")
    }

    func testLoadFailureBlocksEditsAndPreservesOriginalBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("planner.json"), damaged = Data("damaged data".utf8)
        try damaged.write(to: file)
        let model = PlannerViewModel(store: PlannerFileStore(directory: directory))
        await model.load()
        XCTAssertNotNil(model.loadError)
        XCTAssertFalse(model.canEdit)
        model.perform(.add(text: "不能覆盖", category: 0, day: model.selectedDay, repeating: false))
        await model.flush()
        XCTAssertEqual(try Data(contentsOf: file), damaged)
    }

    func testMidnightRolloverFollowsTodayWithoutChangingCompletedHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        var clock = Day(rawValue: "2026-09-29")!.date(timeZone: zone)
        let model = PlannerViewModel(store: PlannerFileStore(directory: directory), now: { clock }, timeZone: { zone })
        await model.load()
        model.perform(.add(text: "未完成", category: 0, day: model.selectedDay, repeating: false))
        model.perform(.add(text: "完成", category: 0, day: model.selectedDay, repeating: false))
        model.perform(.toggle(model.snapshot.open.last!.reference))
        clock = Day(rawValue: "2026-09-30")!.date(timeZone: zone)
        await model.refreshCalendar(); await model.flush()
        XCTAssertEqual(model.selectedDay.rawValue, "2026-09-30")
        XCTAssertEqual(model.document.tasks.first?.date, "2026-09-30")
        XCTAssertEqual(model.document.tasks.last?.date, "2026-09-29")
    }

    func testFailedSaveCanRetryWithoutLosingMemory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("planner.json")
        let model = PlannerViewModel(store: PlannerFileStore(directory: directory)); await model.load()
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        model.perform(.add(text: "仍在内存", category: 0, day: model.selectedDay, repeating: false))
        await model.flush()
        guard case .failed = model.saveState else { return XCTFail("failed save not surfaced") }
        XCTAssertEqual(model.document.tasks.first?.text, "仍在内存")
        try FileManager.default.removeItem(at: file)
        await model.retrySave()
        XCTAssertEqual(model.saveState, .saved)
        let saved = try await PlannerFileStore(directory: directory).load()
        XCTAssertEqual(saved.document.tasks.first?.text, "仍在内存")
    }
}
