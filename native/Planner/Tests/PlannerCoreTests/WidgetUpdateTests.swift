import XCTest
@testable import PlannerCore

final class WidgetUpdateTests: XCTestCase {
    func testSliceRejectsScrollAndShortMovement() {
        XCTAssertFalse(SliceRules.accepts(horizontal: 18, vertical: 2, width: 320))
        XCTAssertFalse(SliceRules.accepts(horizontal: 100, vertical: 130, width: 320))
        XCTAssertFalse(SliceRules.accepts(horizontal: 150, vertical: 10, width: 0))
        XCTAssertTrue(SliceRules.accepts(horizontal: 160, vertical: 12, width: 320))
        XCTAssertTrue(SliceRules.accepts(horizontal: -160, vertical: -12, width: 320))
    }
    func testWidgetProjectsTomorrowWithoutMutatingSavedHistory() {
        var doc = PlannerDocument()
        doc.tasks = [PlannerTask(id: "old", text: "顺延", date: "2026-09-29"), PlannerTask(id: "done", text: "昨天完成", date: "2026-09-29", done: true)]
        doc.repeats = [RepeatRule(id: "daily", text: "每天", from: "2026-09-29")]
        let projection = WidgetProjection(document: doc, day: Day(rawValue: "2026-09-30")!, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(Set(projection.titles), ["顺延", "每天"])
        XCTAssertEqual(projection.total, 2)
        XCTAssertEqual(projection.completed, 0)
        XCTAssertEqual(doc.tasks[0].date, "2026-09-29")
    }
    func testUpdateComparesNumericVersionsAndKeepsURL() throws {
        let data = Data(#"{"version":"1.10.0","downloadURL":"https://github.com/DPclaude/ios/releases/download/native-v1.10.0/Planner.ipa","notes":"修复"}"#.utf8)
        let manifest = try UpdateManifest.validated(data: data)
        XCTAssertTrue(manifest.isNewer(than: "1.9.0"))
        XCTAssertFalse(manifest.isNewer(than: "1.10.0"))
        XCTAssertFalse(manifest.isNewer(than: "2.0.0"))
        XCTAssertEqual(URLComponents(url: manifest.sideStoreURL, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, manifest.downloadURL.absoluteString)
    }
    func testUpdateRejectsForeignURLAndMalformedVersion() {
        for (version, url) in [("1.2.0", "http://github.com/DPclaude/ios/releases/download/v1/Planner.ipa"), ("1.2.0", "https://example.com/Planner.ipa"), ("1.2.0", "https://github.com/Other/ios/releases/download/v1/Planner.ipa"), ("bad", "https://github.com/DPclaude/ios/releases/download/v1/Planner.ipa")] {
            let json = "{\"version\":\"\(version)\",\"downloadURL\":\"\(url)\",\"notes\":\"\"}"
            XCTAssertThrowsError(try UpdateManifest.validated(data: Data(json.utf8)))
        }
    }
}
