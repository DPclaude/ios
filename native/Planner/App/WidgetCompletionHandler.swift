import Foundation
import PlannerCore

@MainActor enum WidgetCompletionHandler {
    static func complete(_ reference: TaskReference, generation: UUID, day: Day,
                         model: PlannerViewModel, reminders: ReminderCoordinator) async -> String? {
        do {
            try await model.completeFromWidget(reference, generation: generation, day: day)
            await reminders.refresh()
            return reminders.errorMessage
        } catch { return error.localizedDescription }
    }
    static func refresh(model: PlannerViewModel, reminders: ReminderCoordinator) async -> String? {
        do {
            await model.load()
            try await model.synchronizeWidget()
            await reminders.refresh()
            return reminders.errorMessage
        } catch { return error.localizedDescription }
    }
}
