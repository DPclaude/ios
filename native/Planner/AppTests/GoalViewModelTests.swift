import XCTest
import PlannerCore
import PlannerStore
@testable import Planner

@MainActor final class GoalViewModelTests: XCTestCase {
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
