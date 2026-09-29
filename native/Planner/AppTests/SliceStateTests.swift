import XCTest
import PlannerCore
import PlannerStore
@testable import Planner

@MainActor final class SliceStateTests: XCTestCase {
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
