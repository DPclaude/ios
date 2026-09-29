import XCTest
import PlannerCore
import PlannerStore
@testable import Planner

@MainActor final class GoalViewModelTests: XCTestCase {
    func testReopeningCompletedPastStageImmediatelyReturnsToToday() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let zone = TimeZone(secondsFromGMT: 0)!, day = Day(rawValue: "2026-09-29")!
        var clock = day.date(timeZone: zone)
        let model = PlannerViewModel(store: PlannerFileStore(directory: dir), now: { clock }, timeZone: { zone })
        await model.load()
        try model.saveGoal(id: "g", title: "作品", deadline: day, stages: [GoalStageDraft(id: "s", text: "草图", deadline: day)], creating: true)
        model.perform(.toggle(.task("s"))); await model.flush()
        clock = day.adding(days: 1, timeZone: zone).date(timeZone: zone)
        await model.refreshCalendar()
        model.perform(.toggle(.task("s"))); await model.flush()
        XCTAssertEqual(model.snapshot.open.map(\.text), ["草图"])
        XCTAssertEqual(model.document.tasks[0].deadline, "2026-09-29")
        XCTAssertEqual(model.document.tasks[0].date, "2026-09-30")
    }
    func testStageCompletionUpdatesGoalAndSurvivesReopen() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PlannerFileStore(directory: dir)
        let model = PlannerViewModel(store: store)
        await model.load()
        try model.saveGoal(id: "g", title: "完成作品", deadline: .today(), stages: [GoalStageDraft(id: "s", text: "交付初稿", deadline: .today())], creating: true)
        await model.flush()
        let saved = try await store.load()
        try await model.completeFromWidget(.task("s"), generation: saved.generation, day: .today())
        XCTAssertTrue(model.document.goalProgress("g").isComplete)
        let reopened = PlannerViewModel(store: PlannerFileStore(directory: dir))
        await reopened.load()
        XCTAssertEqual(reopened.document.goals.first?.title, "完成作品")
        XCTAssertTrue(reopened.document.goalProgress("g").isComplete)
        reopened.perform(.toggle(.task("s"))); await reopened.flush()
        XCTAssertFalse(reopened.document.goalProgress("g").isComplete)
    }
}
