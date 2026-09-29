import Foundation
import UserNotifications
import PlannerStore

// Both UI and background intents resolve this same model; there is only one private-store writer.
@MainActor final class PlannerRuntime {
    static let shared = PlannerRuntime()
    let model: PlannerViewModel
    let reminders: ReminderCoordinator
    private let notificationDelegate = ReminderPresentationDelegate()
    private init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        var directory = URL.applicationSupportDirectory.appendingPathComponent("Planner", isDirectory: true)
        #if DEBUG
        if testing {
            directory = URL.applicationSupportDirectory.appendingPathComponent("PlannerUITests", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("--reset-data") { try? FileManager.default.removeItem(at: directory) }
        }
        #endif
        let coordinator = ReminderCoordinator(client: SystemReminderClient())
        reminders = coordinator
        model = PlannerViewModel(store: PlannerFileStore(directory: directory), onSnapshotPersist: { snapshot in
            guard !testing else { return nil }
            coordinator.enqueue(snapshot.document)
            return PlannerWidgetBridge.publish(snapshot)
        })
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }
}
