import AppIntents
import Foundation
import PlannerCore
import WidgetKit

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
            try await runtime.model.completeFromWidget(reference, generation: generation, day: day)
            await runtime.reminders.flush()
            PlannerWidgetBridge.setInteractionError(nil)
        } catch { PlannerWidgetBridge.setInteractionError(error.localizedDescription) }
        #endif
        WidgetCenter.shared.reloadTimelines(ofKind: PlannerWidgetBridge.kind)
        return .result()
    }
}
