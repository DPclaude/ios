import XCTest
import PlannerCore

final class ReminderScheduleTests: XCTestCase {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    var day: Day { Day(rawValue: "2026-09-29")! }
    func testCompletionCancelsTodayOnlyAndUndoRestoresIt() throws {
        var doc = PlannerDocument()
        doc.repeats = [RepeatRule(id: "r", text: "阅读", from: day.rawValue, reminderMinute: 600)]
        let now = day.date(timeZone: zone).addingTimeInterval(-12 * 3600)
        let before = ReminderSchedule(document: doc, now: now, timeZone: zone)
        XCTAssertEqual(before.entries.count, 30)
        doc.toggle(.repeating(ruleID: "r", day: day), now: now)
        let after = ReminderSchedule(document: doc, now: now, timeZone: zone)
        XCTAssertEqual(after.entries.count, 29)
        XCTAssertEqual(after.entries.first?.day, day.adding(days: 1, timeZone: zone))
        doc.toggle(.repeating(ruleID: "r", day: day), now: now)
        XCTAssertEqual(ReminderSchedule(document: doc, now: now, timeZone: zone).entries, before.entries)
    }
    func testOverdueDoneAndDisabledRemindersAreNotScheduled() {
        var doc = PlannerDocument()
        doc.tasks = [PlannerTask(id: "past", text: "过时", date: day.rawValue, reminderMinute: 1),
                     PlannerTask(id: "done", text: "完成", date: day.rawValue, done: true, reminderMinute: 600),
                     PlannerTask(id: "none", text: "关闭", date: day.rawValue),
                     PlannerTask(id: "future", text: "未来", date: "2026-12-01", reminderMinute: 600)]
        let plan = ReminderSchedule(document: doc, now: day.date(timeZone: zone).addingTimeInterval(-12 * 3600).addingTimeInterval(120), timeZone: zone)
        XCTAssertEqual(plan.entries.map(\.text), ["未来"])
    }
    func testCapacityUsesNearestSixtyAndReportsOverflow() {
        var doc = PlannerDocument()
        doc.tasks = (0..<70).map { PlannerTask(id: "t\($0)", text: "事项\($0)", date: day.rawValue, reminderMinute: 600 + $0) }
        let plan = ReminderSchedule(document: doc, now: day.date(timeZone: zone).addingTimeInterval(-12 * 3600), timeZone: zone)
        XCTAssertEqual(plan.entries.count, 60)
        XCTAssertEqual(plan.omittedCount, 10)
        XCTAssertEqual(plan.entries.last?.text, "事项59")
    }
    func testDSTUsesCalendarDaysAndUniqueOccurrenceIDs() {
        let zone = TimeZone(identifier: "America/New_York")!, start = Day(rawValue: "2026-03-07")!
        var doc = PlannerDocument()
        doc.repeats = [RepeatRule(id: "r", text: "起床", from: start.rawValue, reminderMinute: 150)]
        let plan = ReminderSchedule(document: doc, now: start.date(timeZone: zone).addingTimeInterval(-12 * 3600), timeZone: zone)
        XCTAssertEqual(plan.entries.count, 30)
        XCTAssertEqual(Set(plan.entries.map(\.id)).count, 30)
        XCTAssertEqual(plan.entries[1].day.rawValue, "2026-03-08")
        XCTAssertGreaterThan(plan.entries[1].date, plan.entries[0].date)
    }
}

