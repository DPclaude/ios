import XCTest
@testable import PlannerCore

final class TaskPolishTests: XCTestCase {
    func testJustCompletedPlanStaysVisibleWhenCompletedSectionIsFull() {
        var doc = PlannerDocument()
        doc.tasks = [PlannerTask(id: "open", text: "继续做", date: day.rawValue),
                     PlannerTask(id: "old", text: "旧完成", date: day.rawValue, done: true, order: 0, doneAt: 1),
                     PlannerTask(id: "new", text: "刚完成", date: day.rawValue, done: true, order: 2, doneAt: 2)]
        XCTAssertEqual(WidgetProjection(document: doc, day: day).visibleItems(limit: 2).map(\.text), ["继续做", "刚完成"])
    }
    func testJustCompletedDailyPlanAlsoGetsCompletedWidgetSlot() throws {
        var doc = PlannerDocument()
        doc.tasks = [PlannerTask(id: "old", text: "旧完成", date: day.rawValue, done: true, doneAt: 100)]
        doc.repeats = [RepeatRule(id: "r", text: "刚完成的每日计划", from: day.rawValue)]
        doc.toggle(.repeating(ruleID: "r", day: day), now: day.date())
        let reopened = try BackupCodec.decode(BackupCodec.encode(doc))
        XCTAssertEqual(WidgetProjection(document: reopened, day: day).visibleItems(limit: 1).first?.text, "刚完成的每日计划")
    }
    private let day = Day(rawValue: "2026-09-29")!
    func testLegacyBackupDefaultsAndFilteredMixedReordering() throws {
        var doc = try BackupCodec.decode(Data(#"{"tasks":[{"id":"a","text":"A","date":"2026-09-29","cat":1},{"id":"hidden","text":"H","date":"2026-09-29","cat":2},{"id":"b","text":"B","date":"2026-09-29","cat":1}],"repeats":[{"id":"r","text":"R","from":"2026-09-29","cat":1}]}"#.utf8))
        XCTAssertFalse(doc.tasks[0].important)
        XCTAssertFalse(doc.repeats[0].important)
        let visible = doc.snapshot(day: day, category: 1).open
        doc.reorder(Array(visible.reversed()).map(\.reference), day: day, completed: false)
        let reopened = try BackupCodec.decode(BackupCodec.encode(doc))
        XCTAssertEqual(reopened.snapshot(day: day, category: 1).open.map(\.text), ["B", "A", "R"])
        XCTAssertEqual(reopened.snapshot(day: day, category: nil).open.map(\.text), ["B", "A", "H", "R"])
        let before = doc
        doc.reorder([.task("a"), .task("a")], day: day, completed: false)
        XCTAssertEqual(before, doc)
        doc.reorder([.task("missing")], day: day, completed: false)
        XCTAssertEqual(before, doc)
    }
    func testCompletedWidgetPlansAreRetainedAndSeparate() {
        var doc = PlannerDocument()
        doc.tasks = [PlannerTask(id: "a", text: "待完成", date: day.rawValue, important: true),
                     PlannerTask(id: "b", text: "已完成", date: day.rawValue, done: true)]
        let widget = WidgetProjection(document: doc, day: day)
        XCTAssertEqual(widget.items.map(\.text), ["待完成"])
        XCTAssertTrue(widget.items[0].important)
        XCTAssertEqual(widget.completedItems.map(\.text), ["已完成"])
        XCTAssertEqual(widget.visibleItems(limit: 2).map(\.text), ["待完成", "已完成"])
        doc.tasks[0].done = true
        XCTAssertEqual(WidgetProjection(document: doc, day: day).visibleItems(limit: 2).count, 2)
    }
    func testCompletedReorderPersistsWithoutMixingOpenPlans() throws {
        var doc = PlannerDocument()
        doc.tasks = [PlannerTask(id: "a", text: "A", date: day.rawValue, done: true, order: 1),
                     PlannerTask(id: "b", text: "B", date: day.rawValue, done: true, order: 2),
                     PlannerTask(id: "c", text: "C", date: day.rawValue, order: 3)]
        doc.reorder([.task("b"), .task("a")], day: day, completed: true)
        let reopened = try BackupCodec.decode(BackupCodec.encode(doc))
        XCTAssertEqual(reopened.snapshot(day: day, category: nil).completed.map(\.text), ["B", "A"])
        XCTAssertEqual(reopened.snapshot(day: day, category: nil).open.map(\.text), ["C"])
    }
    func testNewFieldsSurviveBackupAndRepeatConversions() throws {
        let data = Data(#"{"tasks":[{"id":"t","text":"重要任务","date":"2026-09-29","important":true,"order":8}],"repeats":[{"id":"r","text":"每日重要","from":"2026-09-29","important":true,"order":5}]}"#.utf8)
        var doc = try BackupCodec.decode(data)
        doc.convertToRepeat(taskID: "t", ruleID: "converted")
        doc.cancelRepeat(ruleID: "r", day: Day(rawValue: "2026-09-29")!, taskID: "regular", now: .now)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupCodec.encode(doc)) as? [String: Any])
        let tasks = try XCTUnwrap(json["tasks"] as? [[String: Any]])
        let repeats = try XCTUnwrap(json["repeats"] as? [[String: Any]])
        XCTAssertEqual(tasks[0]["important"] as? Bool, true)
        XCTAssertEqual(repeats[0]["important"] as? Bool, true)
        XCTAssertEqual(tasks[0]["order"] as? Double, 5)
        XCTAssertEqual(repeats[0]["order"] as? Double, 8)
    }
}
