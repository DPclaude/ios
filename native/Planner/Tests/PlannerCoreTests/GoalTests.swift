import XCTest
@testable import PlannerCore

final class GoalTests: XCTestCase {
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
