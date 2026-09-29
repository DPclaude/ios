import SwiftUI
import WidgetKit
import PlannerCore
import PlannerStore

struct PlannerEntry: TimelineEntry {
    let date: Date
    let projection: WidgetProjection?
    let message: String?
}
struct PlannerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlannerEntry { PlannerEntry(date: .now, projection: nil, message: "今天的计划，就在这里") }
    func getSnapshot(in context: Context, completion: @escaping (PlannerEntry) -> Void) { completion(entry(at: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlannerEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? midnight
        completion(Timeline(entries: [entry(at: now), entry(at: nextDay)], policy: .after(now.addingTimeInterval(15 * 60))))
    }
    private func entry(at date: Date) -> PlannerEntry {
        guard let file = PlannerWidgetBridge.archiveURL else {
            return PlannerEntry(date: date, projection: nil, message: "组件尚未连接。请保留小组件扩展安装，再打开计划本。")
        }
        do {
            let document = try WidgetArchive.read(from: file)
            return PlannerEntry(date: date, projection: WidgetProjection(document: document, day: .today(now: date)), message: nil)
        } catch {
            return PlannerEntry(date: date, projection: nil, message: "暂时无法读取计划，请点开 App 完成同步。")
        }
    }
}
struct PlannerWidgetView: View {
    let entry: PlannerEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        PlannerWidgetContent(projection: entry.projection, message: entry.message, compact: family == .systemMedium)
            .containerBackground(.background, for: .widget)
            .widgetURL(PlannerWidgetBridge.deepLink)
    }
}
@main struct PlannerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PlannerWidgetBridge.kind, provider: PlannerProvider()) { PlannerWidgetView(entry: $0) }
            .configurationDisplayName("计划本 · 今天")
            .description("桌面看计划，点开全屏划切完成。")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
