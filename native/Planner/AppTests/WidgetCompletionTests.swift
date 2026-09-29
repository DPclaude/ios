import XCTest
import PlannerCore
import PlannerStore
@testable import Planner

@MainActor final class WidgetCompletionTests: XCTestCase {
    func testWidgetUsesOneFinalPublicationWithoutRequestingAnotherReload() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PlannerFileStore(directory: dir)
        var normal = 0, interactive: [Bool] = []
        let model = PlannerViewModel(store: store, onSnapshotPersist: { _ in normal += 1; return nil },
                                     onWidgetSnapshotPersist: { snapshot in interactive.append(snapshot.document.tasks[0].done); return nil })
        await model.load()
        model.perform(.add(text: "完成一次", category: 0, day: .today(), repeating: false)); await model.flush()
        let saved = try await store.load(), ref = model.snapshot.open[0].reference
        normal = 0
        try await model.completeFromWidget(ref, generation: saved.generation, day: .today())
        try await model.completeFromWidget(ref, generation: saved.generation, day: .today())
        XCTAssertEqual(normal, 0)
        XCTAssertEqual(interactive, [true])
    }
    func testColdWidgetCompletionPublishesOnlyFinalState() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PlannerFileStore(directory: dir)
        var doc = PlannerDocument()
        doc.add(text: "只刷新最终状态", category: 0, day: .today(), id: "one")
        let saved = try await store.replace(with: doc)
        var emitted: [Bool] = []
        let model = PlannerViewModel(store: store, onSnapshotPersist: { snapshot in
            emitted.append(snapshot.document.tasks[0].done); return nil
        })
        try await model.completeFromWidget(.task("one"), generation: saved.generation, day: .today())
        XCTAssertEqual(emitted, [true], "Cold loading must not publish the unchecked state before completion")
    }
    func testWidgetAddRouteLoadsColdModelAndChoosesToday() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = PlannerViewModel(store: PlannerFileStore(directory: dir))
        await model.handleURL(URL(string: "planner://add")!)
        XCTAssertTrue(model.isLoaded)
        XCTAssertTrue(model.isShowingAdd)
        XCTAssertEqual(model.selectedDay, .today())
        XCTAssertFalse(model.isShowingSlice)
        model.isShowingAdd = false
        model.select(day: Day.today().adding(days: -1))
        await model.handleURL(URL(string: "planner://add")!)
        XCTAssertTrue(model.isShowingAdd)
        XCTAssertEqual(model.selectedDay, .today())
        await model.handleURL(URL(string: "https://add")!)
        XCTAssertTrue(model.isShowingAdd)
    }
    func testReorderingAndImportancePersistToWidgetArchive() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PlannerFileStore(directory: dir), model = PlannerViewModel(store: PlannerFileStore(directory: dir))
        await model.load()
        model.perform(.add(text: "A", category: 1, day: .today(), repeating: false, important: true))
        model.perform(.add(text: "B", category: 1, day: .today(), repeating: true))
        model.movePlans(from: IndexSet(integer: 0), to: 2, completed: false)
        await model.flush()
        let saved = try await store.load()
        let projected = WidgetProjection(document: saved.document, day: .today())
        XCTAssertEqual(projected.items.map(\.text), ["B", "A"])
        XCTAssertTrue(projected.items[1].important)
    }
    func testRetapRetriesFailedWidgetPublicationWithoutTogglingAgain() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PlannerFileStore(directory: dir)
        var fail = false, publications = 0
        let model = PlannerViewModel(store: store, onSnapshotPersist: { _ in
            publications += 1
            return fail ? "共享副本写入失败" : nil
        })
        await model.load()
        model.perform(.add(text: "重试", category: 0, day: .today(), repeating: false)); await model.flush()
        let state = try await store.load(), ref = model.snapshot.open[0].reference
        fail = true
        do { try await model.completeFromWidget(ref, generation: state.generation, day: .today()); XCTFail("publication failure hidden") } catch {}
        XCTAssertTrue(model.document.tasks[0].done)
        let attempts = publications
        fail = false
        try await model.completeFromWidget(ref, generation: state.generation, day: .today())
        XCTAssertGreaterThan(publications, attempts)
        XCTAssertTrue(model.document.tasks[0].done)
        XCTAssertNil(model.widgetMessage)
    }
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
    func testYesterdayWidgetCannotCompleteTodaysDailyOccurrence() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let zone = TimeZone(secondsFromGMT: 0)!, yesterday = Day(rawValue: "2026-09-29")!
        var clock = yesterday.date(timeZone: zone)
        let store = PlannerFileStore(directory: dir)
        let model = PlannerViewModel(store: store, now: { clock }, timeZone: { zone })
        await model.load()
        model.perform(.add(text: "每天", category: 0, day: yesterday, repeating: true)); await model.flush()
        let state = try await store.load(), ref = model.snapshot.open[0].reference
        clock = yesterday.adding(days: 1, timeZone: zone).date(timeZone: zone)
        do { try await model.completeFromWidget(ref, generation: state.generation, day: yesterday); XCTFail("stale day accepted") } catch {}
        XCTAssertEqual(model.snapshot.completedCount, 0)
        XCTAssertEqual(model.snapshot.open.count, 1)
        await model.flush()
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
