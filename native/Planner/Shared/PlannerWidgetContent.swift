import SwiftUI
import PlannerCore

struct PlannerWidgetContent: View {
    let projection: WidgetProjection?
    let message: String?
    let compact: Bool
    var generation: UUID? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    .contentTransition(.identity)
                let visible = projection.visibleItems(limit: compact ? 2 : 5)
                if visible.isEmpty { Text("今天想做点什么？").font(.subheadline).foregroundStyle(.secondary) }
                // One identity per task across both groups; completion changes position, not view identity.
                ForEach(visible) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        if !compact, item.done, item.id == visible.first(where: \.done)?.id {
                            Text("已完成").font(.caption2).foregroundStyle(.secondary).transition(.identity)
                        }
                        if let generation {
                            Button(intent: CompletePlanIntent(reference: item.reference, generation: generation, day: projection.day)) {
                                row(item)
                            }.buttonStyle(.plain).disabled(item.done)
                                .accessibilityLabel("\(item.done ? "已完成" : "完成")：\(item.text)")
                        } else { row(item) }
                    }.id(item.id).transition(.identity)
                }
                .animation(nil, value: visible)
                Spacer(minLength: 0)
            } else {
                Text(message ?? "轻点添加今天的计划").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }.contentTransition(.identity)
    }
    private func row(_ item: TaskItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.done ? Color.secondary : .orange).font(.system(size: 21))
                .contentTransition(.identity)
            Text(item.text).font(.subheadline).lineLimit(1).strikethrough(item.done)
                .foregroundStyle(item.done ? Color.secondary : (item.important ? .red : .primary))
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, minHeight: compact ? 24 : 30, alignment: .leading)
            .contentShape(Rectangle()).contentTransition(.identity).transition(.identity)
            .accessibilityLabel("\(item.done ? "已完成" : "待完成")：\(item.text)")
    }
}
