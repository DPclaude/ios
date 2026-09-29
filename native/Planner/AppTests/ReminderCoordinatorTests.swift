import XCTest
import PlannerCore
@testable import Planner

@MainActor private final class MemoryNotificationClient: ReminderNotificationClient {
    var requests: [String: ReminderEntry] = [:]
    var denied = false
    var fail = false
    func permission(request: Bool) async throws -> Bool { !denied }
    func pendingIDs() async -> [String] { Array(requests.keys) }
    func remove(_ ids: [String]) { for id in ids { requests.removeValue(forKey: id) } }
    func add(_ entry: ReminderEntry) async throws {
        if fail { throw NSError(domain: "ScheduleFailure", code: 1) }
        requests[entry.id] = entry
    }
}

@MainActor final class ReminderCoordinatorTests: XCTestCase {
    func testCompletionReconcilesPendingSystemRequestsAndUndoRestores() async {
        let client = MemoryNotificationClient(), zone = TimeZone(secondsFromGMT: 0)!
        let day = Day(rawValue: "2026-09-29")!, now = Day(rawValue: "2026-09-29")!.date(timeZone: zone).addingTimeInterval(-3600 * 12)
        let coordinator = ReminderCoordinator(client: client, now: { now }, timeZone: { zone })
        var document = PlannerDocument()
        document.tasks = [PlannerTask(id: "t", text: "学习", date: day.rawValue, reminderMinute: 600)]
        coordinator.enqueue(document); await coordinator.flush()
        XCTAssertEqual(client.requests.count, 1)
        document.toggle(.task("t"), now: now)
        coordinator.enqueue(document); await coordinator.flush()
        XCTAssertTrue(client.requests.isEmpty)
        document.toggle(.task("t"), now: now)
        coordinator.enqueue(document); await coordinator.flush()
        XCTAssertEqual(client.requests.count, 1)
    }
    func testDeniedAndSchedulingFailureAreVisibleAndRetryable() async {
        let client = MemoryNotificationClient(), day = Day.today().adding(days: 1, timeZone: .current)
        let coordinator = ReminderCoordinator(client: client)
        var doc = PlannerDocument()
        doc.tasks = [PlannerTask(id: "t", text: "学习", date: day.rawValue, reminderMinute: 600)]
        client.denied = true
        coordinator.enqueue(doc); await coordinator.flush()
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertFalse(coordinator.authorized)
        client.denied = false; client.fail = true
        coordinator.enqueue(doc); await coordinator.flush()
        XCTAssertNotNil(coordinator.errorMessage)
        client.fail = false
        coordinator.enqueue(doc); await coordinator.flush()
        XCTAssertNil(coordinator.errorMessage)
        XCTAssertEqual(client.requests.count, 1)
    }
    func testRapidReplacementLeavesOnlyLatestRequests() async {
        let client = MemoryNotificationClient()
        let queue = ReminderCoordinator(client: client)
        let tomorrow = Day.today().adding(days: 1, timeZone: .current)
        var old = PlannerDocument()
        old.tasks = [PlannerTask(id: "old", text: "已删除", date: tomorrow.rawValue, reminderMinute: 600)]
        var latest = PlannerDocument()
        latest.tasks = [PlannerTask(id: "new", text: "保留", date: tomorrow.rawValue, reminderMinute: 600)]
        queue.enqueue(old); queue.enqueue(latest); await queue.flush()
        XCTAssertEqual(client.requests.values.map(\.text), ["保留"])
    }
}
