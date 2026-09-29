import XCTest
import PlannerCore
import PlannerStore
@testable import Planner

@MainActor final class WidgetCompletionTests: XCTestCase {
    func testWidgetCompletionIgnoresSelectedPageAndRepeatedTaps() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PlannerFileStore(directory: dir)
        let model = PlannerViewModel(store: store)
        await model.load()
        let today = Day.today()
        model.perform(.add(text: "桌面完成", category: 0, day: today, repeating: false))
        await model.flush()
        let saved = try await store.load(), ref = model.snapshot.open[0].reference
        model.select(day: today.adding(days: -1, timeZone: .current))
        try await model.completeFromWidget(ref, generation: saved.generation, day: today)
        try await model.completeFromWidget(ref, generation: saved.generation, day: today)
        XCTAssertTrue(model.document.tasks[0].done)
        XCTAssertFalse(model.isShowingSlice)
        XCTAssertEqual(model.selectedDay, today.adding(days: -1, timeZone: .current))
        let reopened = try await PlannerFileStore(directory: dir).load()
        XCTAssertTrue(reopened.document.tasks[0].done)
    }
    func testStaleWidgetCannotCompleteImportedOrPreviousDayPlans() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PlannerFileStore(directory: dir), model = PlannerViewModel(store: PlannerFileStore(directory: dir))
        await model.load()
        model.perform(.add(text: "保留", category: 0, day: .today(), repeating: true))
        await model.flush()
        let old = try await store.load(), ref = model.snapshot.open[0].reference
        let preview = try await model.prepareImport(data: try BackupCodec.encode(model.document))
        try await model.confirmImport(preview)
        do { try await model.completeFromWidget(ref, generation: old.generation, day: .today()); XCTFail("stale generation accepted") } catch {}
        XCTAssertEqual(model.snapshot.completedCount, 0)
    }
    func testColdConcurrentLoadsShareOneState() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = PlannerViewModel(store: PlannerFileStore(directory: dir))
        async let first: Void = model.load()
        async let second: Void = model.load()
        _ = await (first, second)
        model.perform(.add(text: "加载后", category: 0, day: .today(), repeating: false))
        await model.flush()
        XCTAssertEqual(model.document.tasks.count, 1)
    }
}
