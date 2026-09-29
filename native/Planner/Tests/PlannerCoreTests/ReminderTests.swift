import Foundation
import XCTest
import PlannerCore

final class ReminderTests: XCTestCase {
    func testReminderSurvivesBackupAndDailyConversion() throws {
        let data = Data(#"{"tasks":[{"id":"t","text":"喝水","date":"2026-09-29","reminderMinute":570}]}"#.utf8)
        var doc = try BackupCodec.decode(data)
        let encoded = try JSONSerialization.jsonObject(with: BackupCodec.encode(doc)) as! [String: Any]
        XCTAssertEqual((encoded["tasks"] as! [[String: Any]])[0]["reminderMinute"] as? Int, 570)
        doc.convertToRepeat(taskID: "t", ruleID: "r")
        let daily = try JSONSerialization.jsonObject(with: BackupCodec.encode(doc)) as! [String: Any]
        XCTAssertEqual((daily["repeats"] as! [[String: Any]])[0]["reminderMinute"] as? Int, 570)
        doc.cancelRepeat(ruleID: "r", day: Day(rawValue: "2026-09-29")!, taskID: "t2", now: .now)
        let regular = try JSONSerialization.jsonObject(with: BackupCodec.encode(doc)) as! [String: Any]
        XCTAssertEqual((regular["tasks"] as! [[String: Any]])[0]["reminderMinute"] as? Int, 570)
    }
    func testInvalidReminderDoesNotImport() throws {
        for minute in [-1, 1440] {
            let data = Data("{\"tasks\":[{\"id\":\"t\",\"text\":\"x\",\"date\":\"2026-09-29\",\"reminderMinute\":\(minute)}]}".utf8)
            XCTAssertThrowsError(try BackupCodec.decode(data))
        }
    }
}
