import Foundation
import Observation
import UserNotifications
import PlannerCore

@MainActor protocol ReminderNotificationClient {
    func permission(request: Bool) async throws -> Bool
    func pendingIDs() async -> [String]
    func remove(_ ids: [String])
    func add(_ entry: ReminderEntry) async throws
}

@MainActor final class SystemReminderClient: ReminderNotificationClient {
    private let center = UNUserNotificationCenter.current()
    func permission(request: Bool) async throws -> Bool {
        var settings = await center.notificationSettings()
        if request && settings.authorizationStatus == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        return [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    }
    func pendingIDs() async -> [String] {
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let delivered = await center.deliveredNotifications().map { $0.request.identifier }
        return Array(Set(pending + delivered)).filter { $0.hasPrefix("planner.reminder.") }
    }
    func remove(_ ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
    func add(_ entry: ReminderEntry) async throws {
        let content = UNMutableNotificationContent()
        content.title = "计划本提醒"; content.body = entry.text; content.sound = .default
        content.userInfo = ["day": entry.day.rawValue]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: entry.date)
        components.calendar = calendar; components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: entry.id, content: content, trigger: trigger))
    }
}

@MainActor @Observable final class ReminderCoordinator {
    private(set) var authorized = false
    private(set) var errorMessage: String?
    private(set) var summary = "在添加或编辑计划中打开提醒，选择时间。"
    private(set) var busy = false
    @ObservationIgnored private let client: any ReminderNotificationClient
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: () -> TimeZone
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var latest = PlannerDocument()
    @ObservationIgnored private var sequence = 0
    init(client: any ReminderNotificationClient, now: @escaping () -> Date = { .now }, timeZone: @escaping () -> TimeZone = { .current }) {
        self.client = client; self.now = now; self.timeZone = timeZone
    }
    func requestAuthorization() async {
        do { authorized = try await client.permission(request: true); errorMessage = nil }
        catch { errorMessage = "无法开启通知：\(error.localizedDescription)"; return }
        enqueue(latest); await flush()
    }
    func enqueue(_ document: PlannerDocument) {
        latest = document; sequence += 1
        let revision = sequence, previous = tail
        busy = true
        tail = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.sequence == revision else { return }
            await self.reconcile(document)
            if self.sequence == revision { self.busy = false }
        }
    }
    func flush() async {
        while true {
            let revision = sequence
            await tail?.value
            if revision == sequence { return }
        }
    }
    func refresh() async { enqueue(latest); await flush() }
    private func reconcile(_ document: PlannerDocument) async {
        do {
            authorized = try await client.permission(request: false)
            let plan = ReminderSchedule(document: document, now: now(), timeZone: timeZone())
            let desired = authorized ? plan.entries : []
            let identifiers = Set(desired.map(\.id))
            let obsolete = await client.pendingIDs().filter { !identifiers.contains($0) }
            client.remove(obsolete)
            for entry in desired { try await client.add(entry) }
            errorMessage = nil
            if !authorized {
                summary = "通知尚未允许。计划和提醒时间已保存，请开启系统通知权限。"
            } else if plan.omittedCount > 0 {
                summary = "已安排最近 \(desired.count) 条提醒，另有 \(plan.omittedCount) 条待补充。请经常打开计划本，或在桌面完成计划后自动补充。"
            } else {
                summary = "已安排 \(desired.count) 条提醒。每日计划已预排至 \(plan.dailyThrough.rawValue)，下次打开计划本或桌面完成时继续补充。"
            }
        } catch { errorMessage = "提醒未能全部安排，请重试：\(error.localizedDescription)" }
    }
}

final class ReminderPresentationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
