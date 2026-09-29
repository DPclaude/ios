import SwiftUI
import PlannerCore
import PlannerStore

@main struct PlannerApp: App {
    @State private var model: PlannerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundSave = BackgroundSave()
    private let arguments = ProcessInfo.processInfo.arguments
    init() {
        _model = State(initialValue: PlannerRuntime.shared.model)
    }
    var body: some Scene {
        WindowGroup {
            PlannerDayView(model: model)
                .tint(.orange)
                .task { await model.load() }
                .onOpenURL { url in
                    guard url.scheme == "planner", url.host == "slice" else { return }
                    Task { await model.load(); await model.refreshCalendar(); model.openSlice() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refreshCalendar(); await PlannerRuntime.shared.reminders.refresh() } }
                    else { backgroundSave.flush(model) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    Task { await model.refreshCalendar() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    Task { await model.refreshCalendar() }
                }
                #if DEBUG
                .preferredColorScheme(arguments.contains("--dark") ? .dark : nil)
                .dynamicTypeSize(...(arguments.contains("--large-text") ? .accessibility3 : .accessibility5))
                .modifier(TestTextSize(enabled: arguments.contains("--large-text")))
                #endif
        }
    }
}

@MainActor private final class BackgroundSave {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    func flush(_ model: PlannerViewModel) {
        guard identifier == .invalid else { return }
        identifier = UIApplication.shared.beginBackgroundTask(withName: "保存计划") { [weak self] in
            Task { @MainActor in self?.finish() }
        }
        Task { await model.flush(); await PlannerRuntime.shared.reminders.flush(); finish() }
    }
    private func finish() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier); identifier = .invalid
    }
}
#if DEBUG
private struct TestTextSize: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.dynamicTypeSize(.accessibility3) } else { content }
    }
}
#endif
