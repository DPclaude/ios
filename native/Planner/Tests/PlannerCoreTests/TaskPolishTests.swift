import XCTest
@testable import PlannerCore

final class TaskPolishTests: XCTestCase {
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
