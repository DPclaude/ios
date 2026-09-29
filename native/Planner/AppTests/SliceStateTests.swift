import XCTest
import PlannerCore
import PlannerStore
@testable import Planner

@MainActor final class SliceStateTests: XCTestCase {
    func testUndoAcrossMidnightRollsOrdinaryPlanIntoToday() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let yesterday = Day(rawValue: "2026-09-29")!
        let today = Day(rawValue: "2026-09-30")!
        var clock = yesterday.date(timeZone: zone)
        let model = PlannerViewModel(store: PlannerFileStore(directory: dir), now: { clock }, timeZone: { zone })
        await model.load()
        model.perform(.add(text: "跨天撤销", category: 0, day: yesterday, repeating: false))
        XCTAssertTrue(model.completeForSlice(model.snapshot.open[0].reference))
        clock = today.date(timeZone: zone)
        await model.refreshCalendar()
        model.undoSliceCompletion()
        XCTAssertEqual(model.snapshot.open.map(\.text), ["跨天撤销"])
        XCTAssertEqual(model.document.tasks.first?.date, today.rawValue)
        XCTAssertEqual(WidgetProjection(document: model.document, day: today, timeZone: zone).titles, ["跨天撤销"])
        await model.flush()
    }
    func testRepeatedSliceDoesNotUncompleteAndUndoPreservesOtherEdits() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = PlannerViewModel(store: PlannerFileStore(directory: dir))
        await model.load()
        model.perform(.add(text: "划切", category: 0, day: model.selectedDay, repeating: true))
        let ref = model.snapshot.open[0].reference
        XCTAssertTrue(model.completeForSlice(ref))
        XCTAssertFalse(model.completeForSlice(ref))
        XCTAssertEqual(model.snapshot.completedCount, 1)
        model.perform(.add(text: "后来新增", category: 0, day: model.selectedDay, repeating: false))
        model.undoSliceCompletion()
        XCTAssertEqual(Set(model.snapshot.open.map(\.text)), ["划切", "后来新增"])
        XCTAssertFalse(model.sliceUndoAvailable)
        await model.flush()
    }
    func testFailedPrivateSaveDoesNotPublishUnsavedWidgetData() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let privateDir = dir.appendingPathComponent("private")
        let widget = dir.appendingPathComponent("shared/widget.json")
        let model = PlannerViewModel(store: PlannerFileStore(directory: privateDir), onPersist: { document in
            do { try WidgetArchive.write(document: document, to: widget); return nil }
            catch { return error.localizedDescription }
        })
        await model.load()
        model.perform(.add(text: "已保存", category: 0, day: model.selectedDay, repeating: false))
        await model.flush()
        XCTAssertEqual(try WidgetArchive.read(from: widget).tasks.count, 1)
        try FileManager.default.removeItem(at: privateDir)
        try Data("block directory".utf8).write(to: privateDir)
        model.perform(.add(text: "未保存", category: 0, day: model.selectedDay, repeating: false))
        await model.flush()
        guard case .failed = model.saveState else { return XCTFail("Expected save failure") }
        XCTAssertEqual(try WidgetArchive.read(from: widget).tasks.map(\.text), ["已保存"])
        XCTAssertEqual(model.document.tasks.count, 2)
    }
}
