import AppIntents
import Foundation
import PlannerCore

// This protocol guarantees app-process execution while openAppWhenRun keeps the Home Screen visible.
struct CompletePlanIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "完成计划"
    static let openAppWhenRun = false
    static let isDiscoverable = false
    @Parameter(title: "计划") var reference: String
    @Parameter(title: "数据版本") var generation: String
    @Parameter(title: "日期") var day: String
    init() {}
    init(reference: TaskReference, generation: UUID, day: Day) {
        self.reference = (try? JSONEncoder().encode(reference).base64EncodedString()) ?? ""
        self.generation = generation.uuidString; self.day = day.rawValue
    }
    @MainActor func perform() async throws -> some IntentResult {
        #if PLANNER_APP
        do {
            guard let data = Data(base64Encoded: reference), let generation = UUID(uuidString: generation),
                  let day = Day(rawValue: day) else { throw WidgetCompletionError.stale }
            let reference = try JSONDecoder().decode(TaskReference.self, from: data)
            let runtime = PlannerRuntime.shared
            let message = await WidgetCompletionHandler.complete(reference, generation: generation, day: day,
                                                                  model: runtime.model, reminders: runtime.reminders)
            PlannerWidgetBridge.setInteractionError(message)
        } catch { PlannerWidgetBridge.setInteractionError(error.localizedDescription) }
        #endif
        return .result()
    }
}

struct RefreshPlannerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "重试组件同步"
    static let openAppWhenRun = false
    static let isDiscoverable = false
    @MainActor func perform() async throws -> some IntentResult {
        #if PLANNER_APP
        let runtime = PlannerRuntime.shared
        let message = await WidgetCompletionHandler.refresh(model: runtime.model, reminders: runtime.reminders)
        PlannerWidgetBridge.setInteractionError(message)
        #endif
        return .result()
    }
}
