import XCTest
import PlannerCore
@testable import PlannerStore

final class WidgetArchiveTests: XCTestCase {
    func testArchiveReplacementIsReadableAndCorruptionRejected() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("widget.json")
        var doc = PlannerDocument()
        doc.tasks = [PlannerTask(id: "a", text: "保留", date: "2026-09-29")]
        try WidgetArchive.write(document: doc, to: file)
        XCTAssertEqual(try WidgetArchive.read(from: file), doc)
        doc.tasks[0].done = true
        try WidgetArchive.write(document: doc, to: file)
        XCTAssertTrue(try WidgetArchive.read(from: file).tasks[0].done)
        try Data("broken".utf8).write(to: file)
        XCTAssertThrowsError(try WidgetArchive.read(from: file))
    }
}
