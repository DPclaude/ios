import SwiftUI
import PlannerCore

struct PlannerWidgetContent: View {
    let projection: WidgetProjection?
    let message: String?
    let compact: Bool
    var generation: UUID? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack {
                Text("今天的计划").font(.headline)
                Spacer(minLength: 4)
                if let projection {
                    Text(projection.day.date(), format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
                }
                if message != nil, projection != nil {
                    Button(intent: RefreshPlannerIntent()) { Image(systemName: "exclamationmark.circle") }
                        .buttonStyle(.plain).foregroundStyle(.orange)
                        .accessibilityLabel("同步未完成，轻点重试").accessibilityHint(message ?? "")
                }
            }
            if let projection {
                Text("\(projection.items.count) 件待完成").font(.caption).foregroundStyle(.secondary)
                    .contentTransition(.numericText()).invalidatableContent()
                let visible = projection.visibleItems(limit: compact ? 2 : 6)
                if visible.isEmpty {
                    Text("今天想做点什么？").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(visible.filter { !$0.done }) { item in
                    if let generation {
                        Toggle(isOn: false, intent: CompletePlanIntent(reference: item.reference, generation: generation, day: projection.day)) {
                            Text(item.text).lineLimit(1)
                        }
                        .toggleStyle(PlannerCircleToggleStyle(important: item.important, compact: compact))
                        .accessibilityLabel("完成：\(item.text)")
                    } else { staticRow(item) }
                }
                if visible.contains(where: \.done) {
                    if !compact { Text("已完成").font(.caption2).foregroundStyle(.secondary) }
                    ForEach(visible.filter(\.done)) { item in staticRow(item) }
                }
                Spacer(minLength: 0)
            } else {
                Text(message ?? "轻点添加今天的计划").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }
    private func staticRow(_ item: TaskItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.done ? Color.secondary : .orange).font(.system(size: 21))
            Text(item.text).font(.subheadline).lineLimit(1).strikethrough(item.done)
                .foregroundStyle(item.done ? Color.secondary : (item.important ? .red : .primary))
            Spacer(minLength: 0)
        }.frame(minHeight: compact ? 24 : 30)
            .accessibilityLabel("\(item.done ? "已完成" : "待完成")：\(item.text)")
    }
}

// WidgetKit updates isOn immediately, before the background save finishes.
private struct PlannerCircleToggleStyle: ToggleStyle {
    let important: Bool
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21)).foregroundStyle(configuration.isOn ? Color.secondary : .orange)
                configuration.label.font(.subheadline).strikethrough(configuration.isOn)
                    .foregroundStyle(configuration.isOn ? Color.secondary : (important ? .red : .primary))
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: compact ? 24 : 30, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
