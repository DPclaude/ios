import Foundation
import XCTest
@testable import PlannerCore

final class CoreTests: XCTestCase {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    func day(_ value: String) -> Day { Day(rawValue: value)! }
    func task(_ id: String = "legacy-1", date: String = "2026-09-28", done: Bool = false, order: Double = 1) -> PlannerTask {
        PlannerTask(id: id, text: id, date: date, done: done, cat: 0, order: order)
    }

    // Catches UTC arithmetic, lenient calendar parsing, and non-leap day normalization.
    func testCalendarBoundaries() {
        XCTAssertEqual(day("2026-09-30").adding(days: 1, timeZone: zone).rawValue, "2026-10-01")
        XCTAssertEqual(day("2026-12-31").adding(days: 1, timeZone: zone).rawValue, "2027-01-01")
        XCTAssertEqual(day("2028-02-28").adding(days: 1, timeZone: zone).rawValue, "2028-02-29")
        XCTAssertNil(Day(rawValue: "2026-02-30"))
        XCTAssertNil(Day(rawValue: "2026-2-03"))
        XCTAssertEqual(day("2026-03-08").adding(days: 1, timeZone: TimeZone(identifier: "America/Los_Angeles")!).rawValue, "2026-03-09")
    }

    func testLegacyDefaultsAndStringIDs() throws {
        let data = Data(#"{"tasks":[{"id":"old-task-1","text":"旧计划","date":"2026-09-29","done":false,"order":1}]}"#.utf8)
        let decoded = try BackupCodec.decode(data)
        XCTAssertEqual(decoded.tasks[0].id, "old-task-1")
        XCTAssertEqual(decoded.tasks[0].cat, 0)
        XCTAssertTrue(decoded.notes.isEmpty)
        XCTAssertTrue(decoded.repeats.isEmpty)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(decoded)), decoded)
    }

    func testRejectsMalformedBackups() {
        let cases = [
            #"{"tasks":[{"id":"x","text":"a","date":"2026-02-30","done":false,"cat":0,"order":1}]}"#,
            #"{"tasks":[{"id":"x","text":"a","date":"2026-09-29","done":false,"cat":4,"order":1}]}"#,
            #"{"tasks":[{"id":"x","text":"a","date":"2026-09-29","done":"false","order":1}]}"#,
            #"{"tasks":[],"notes":{"yesterday":"bad key"}}"#,
            #"{"notes":{}}"#
        ]
        for json in cases { XCTAssertThrowsError(try BackupCodec.decode(Data(json.utf8)), json) }
        var doc = PlannerDocument(); doc.tasks = [task(), task()]
        XCTAssertThrowsError(try BackupCodec.encode(doc))
    }

    func testRolloverIsIdempotentAndPreservesHistory() {
        var doc = PlannerDocument()
        doc.tasks = [task("open"), task("done", done: true), task("future", date: "2026-10-01")]
        doc.repeatDone = ["2026-01-01": ["r"], "2026-09-29": ["r"]]
        doc.rollover(today: day("2026-09-29"), timeZone: zone)
        XCTAssertEqual(doc.tasks.map(\.date), ["2026-09-29", "2026-09-28", "2026-10-01"])
        XCTAssertTrue(doc.tasks[0].rolled)
        XCTAssertNil(doc.repeatDone["2026-01-01"])
        let once = doc
        doc.rollover(today: day("2026-09-29"), timeZone: zone)
        XCTAssertEqual(doc, once)
    }

    func testRepeatedCompletionIsPerDayAndConvertsWithoutLoss() {
        var doc = PlannerDocument(); doc.tasks = [task(date: "2026-09-29", done: true)]
        doc.convertToRepeat(taskID: "legacy-1", ruleID: "r")
        XCTAssertTrue(doc.tasks.isEmpty)
        XCTAssertEqual(doc.repeatDone["2026-09-29"], ["r"])
        XCTAssertEqual(doc.snapshot(day: day("2026-09-30"), category: nil).completedCount, 0)
        doc.toggle(.repeating(ruleID: "r", day: day("2026-09-30")), now: Date())
        XCTAssertEqual(doc.snapshot(day: day("2026-09-30"), category: nil).completedCount, 1)
        doc.cancelRepeat(ruleID: "r", day: day("2026-09-29"), taskID: "normal", now: Date())
        XCTAssertTrue(doc.repeats.isEmpty)
        XCTAssertEqual(doc.tasks.first?.id, "normal")
        XCTAssertEqual(doc.tasks.first?.done, true)
    }

    func testDeleteUndoPreservesConcurrentAdditionAndRuleHistory() {
        var doc = PlannerDocument()
        doc.repeats = [RepeatRule(id: "r", text: "喝水", cat: 0, from: "2026-09-01")]
        doc.repeatDone = ["2026-09-28": ["r"]]
        let removed = doc.remove(.repeating(ruleID: "r", day: day("2026-09-29")))!
        doc.add(text: "新增", category: 1, day: day("2026-09-29"), id: "new")
        doc.restore(removed, today: day("2026-09-29"), timeZone: zone)
        XCTAssertEqual(doc.tasks.first?.text, "新增")
        XCTAssertEqual(doc.repeats.first?.text, "喝水")
        XCTAssertEqual(doc.repeatDone["2026-09-28"], ["r"])
    }

    func testFilterProgressSortingPinAndMove() {
        var doc = PlannerDocument()
        doc.tasks = [task("a", date: "2026-09-29"), task("b", date: "2026-09-29", done: true)]
        doc.tasks[1].cat = 1
        let filtered = doc.snapshot(day: day("2026-09-29"), category: 0)
        XCTAssertEqual(filtered.totalCount, 2)
        XCTAssertEqual(filtered.completedCount, 1)
        XCTAssertTrue(filtered.completed.isEmpty)
        doc.add(text: "新", category: 0, day: day("2026-09-29"), id: "c")
        doc.pin(taskID: "c")
        XCTAssertEqual(doc.snapshot(day: day("2026-09-29"), category: nil).open.first?.reference, .task("c"))
        doc.moveToNextDay(taskID: "a", timeZone: zone)
        XCTAssertEqual(doc.tasks.first?.date, "2026-09-30")
    }

    func testOrphanRepeatCompletionsDoNotDestroyValidHistory() throws {
        let json = #"{"tasks":[],"repeats":[{"id":"r","text":"每天","cat":0,"from":"2026-09-01"}],"repeatDone":{"2026-09-29":["deleted","r","r"]}}"#
        let doc = try BackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(doc.repeatDone["2026-09-29"], ["r"])
    }

    func testLargeHistorySnapshotDoesNotMutateHistory() throws {
        var doc = PlannerDocument()
        doc.tasks = (0..<10_000).map { task("t\($0)", date: $0 < 300 ? "2026-09-29" : "2026-10-01", order: Double($0)) }
        doc.repeats = (0..<30).map { RepeatRule(id: "r\($0)", text: "每天\($0)", cat: 0, from: "2026-09-01") }
        let original = doc
        let selected = day("2026-09-29")
        measure {
            let result = doc.snapshot(day: selected, category: nil)
            XCTAssertEqual(result.open.count, 330)
            XCTAssertEqual(result.completedCount, 0)
        }
        XCTAssertEqual(doc, original)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(doc)), original)
    }
}
