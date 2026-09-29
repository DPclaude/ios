import XCTest
@testable import PlannerCore

final class GoalTests: XCTestCase {
    private let today = Day(rawValue: "2026-09-29")!
    func testGoalEditingPreservesCompletionAndStageScheduling() throws {
        var doc = PlannerDocument()
        let end = Day(rawValue: "2026-12-31")!
        let stage = GoalStageDraft(id: "s", text: "草图", deadline: today)
        try doc.saveGoal(id: "g", title: "作品", deadline: end, stages: [stage], creating: true, today: today)
        doc.toggle(.task("s"), now: today.date())
        var draft = try XCTUnwrap(doc.goalStages("g").first).goalDraft
        draft.text = "修订草图"
        try doc.saveGoal(id: "g", title: "完整作品", deadline: end, stages: [draft], creating: false, today: today)
        XCTAssertTrue(doc.tasks[0].done)
        XCTAssertEqual(doc.tasks[0].text, "修订草图")
        XCTAssertEqual(doc.goalProgress("g").completed, 1)
        XCTAssertTrue(doc.goalProgress("g").isComplete)
        doc.convertToRepeat(taskID: "s", ruleID: "daily")
        XCTAssertTrue(doc.repeats.isEmpty)
        XCTAssertEqual(doc.tasks.count, 1)
    }
    func testDeletedStageCannotBeResurrectedByStaleGoalEditor() throws {
        var doc = PlannerDocument()
        try doc.saveGoal(id: "g", title: "作品", deadline: today, stages: [GoalStageDraft(id: "s", text: "草图", deadline: today)], creating: true, today: today)
        let draft = doc.tasks[0].goalDraft
        let removed = try XCTUnwrap(doc.remove(.task("s")))
        XCTAssertThrowsError(try doc.saveGoal(id: "g", title: "作品", deadline: today, stages: [draft], creating: false, today: today))
        doc.restore(removed, today: today, timeZone: .current)
        XCTAssertEqual(doc.goalStages("g").count, 1)
        doc.deleteGoal("g")
        doc.restore(removed, today: today, timeZone: .current)
        XCTAssertTrue(doc.tasks.isEmpty)
        XCTAssertTrue(doc.goals.isEmpty)
    }
    func testInvalidGoalEditIsAtomicAndOldBackupsStillLoad() throws {
        var doc = try BackupCodec.decode(Data(#"{"tasks":[]}"#.utf8))
        XCTAssertTrue(doc.goals.isEmpty)
        let before = doc
        XCTAssertThrowsError(try doc.saveGoal(id: "g", title: "作品", deadline: today, stages: [GoalStageDraft(id: "s", text: "草图", deadline: today.adding(days: 1))], creating: true, today: today))
        XCTAssertEqual(doc, before)
        XCTAssertThrowsError(try doc.saveGoal(id: "g", title: "作品", deadline: today, stages: [], creating: true, today: today))
        XCTAssertEqual(doc, before)
    }
    func testUnchangedDeadlinePreservesRolledScheduleAndReminder() throws {
        var doc = PlannerDocument()
        let yesterday = today.adding(days: -1)
        try doc.saveGoal(id: "g", title: "作品", deadline: today, stages: [GoalStageDraft(id: "s", text: "草图", deadline: yesterday)], creating: true, today: yesterday)
        doc.setReminder(600, for: .task("s")); doc.setImportant(true, for: .task("s"))
        let draft = doc.tasks[0].goalDraft
        doc.rollover(today: today, timeZone: .current)
        try doc.saveGoal(id: "g", title: "作品", deadline: today, stages: [draft], creating: false, today: today)
        XCTAssertEqual(doc.tasks[0].date, today.rawValue)
        XCTAssertEqual(doc.tasks[0].deadline, yesterday.rawValue)
        XCTAssertEqual(doc.tasks[0].reminderMinute, 600)
        XCTAssertTrue(doc.tasks[0].important)
        XCTAssertTrue(doc.tasks[0].rolled)
    }
    func testGoalAndStageDeadlineSurviveBackupAndRollover() throws {
        let data = Data(#"{"goals":[{"id":"g","title":"完成作品","deadline":"2026-12-31"}],"tasks":[{"id":"s","text":"完成草图","date":"2026-09-01","goalID":"g","deadline":"2026-09-01"}]}"#.utf8)
        var doc = try BackupCodec.decode(data)
        doc.rollover(today: Day(rawValue: "2026-09-29")!, timeZone: TimeZone(secondsFromGMT: 0)!)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupCodec.encode(doc)) as? [String: Any])
        XCTAssertEqual((json["goals"] as? [[String: Any]])?.first?["title"] as? String, "完成作品")
        let task = try XCTUnwrap((json["tasks"] as? [[String: Any]])?.first)
        XCTAssertEqual(task["goalID"] as? String, "g")
        XCTAssertEqual(task["deadline"] as? String, "2026-09-01")
        XCTAssertEqual(task["date"] as? String, "2026-09-29")
    }
    func testInvalidStageCannotOverwriteBackup() {
        for fields in [#""goalID":"missing","deadline":"2026-09-01""#,
                       #""goalID":"g","deadline":"2027-01-01""#] {
            let data = Data((#"{"goals":[{"id":"g","title":"作品","deadline":"2026-12-31"}],"tasks":[{"id":"s","text":"草图","date":"2026-09-01","# + fields + "}]}").utf8)
            XCTAssertThrowsError(try BackupCodec.decode(data))
        }
    }
}
