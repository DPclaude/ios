import SwiftUI
import PlannerCore

struct PlannerWidgetContent: View {
    let projection: WidgetProjection?
    let message: String?
    let compact: Bool
    var generation: UUID? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("今天的计划", systemImage: "sun.max.fill")
                    .font(.headline).foregroundStyle(.orange)
                Spacer(minLength: 4)
                if let projection { Text(projection.day.date(), format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary) }
            }
            if let projection {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(projection.titles.count)").font(.system(size: compact ? 26 : 36, weight: .bold, design: .rounded))
                    Text("件待完成").font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Text("\(projection.completed) / \(projection.total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if projection.titles.isEmpty {
                    Label(projection.total == 0 ? "从一件小事开始" : "今天的计划已完成", systemImage: projection.total == 0 ? "pencil" : "checkmark.seal.fill")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(projection.items.prefix(compact ? 1 : 4))) { item in
                        if let generation {
                            Button(intent: CompletePlanIntent(reference: item.reference, generation: generation, day: projection.day)) {
                                row(item.text)
                            }.buttonStyle(.plain)
                                .accessibilityLabel("完成：\(item.text)")
                        } else {
                            row(item.text)
                        }
                    }
                }
                Spacer(minLength: 0)
                ProgressView(value: Double(projection.completed), total: Double(max(1, projection.total))).tint(.orange)
                HStack {
                    Text(message ?? "点计划直接完成 · 点空白处打开")
                        .font(.caption2).foregroundStyle(message == nil ? Color.secondary : Color.orange).lineLimit(compact ? 1 : 2)
                    if message != nil {
                        Button(intent: RefreshPlannerIntent()) { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.plain).accessibilityLabel("重试组件同步")
                    }
                }
            } else {
                Text(message ?? "打开计划本，开始今天的计划").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Label("打开计划本", systemImage: "arrow.up.forward").font(.caption).foregroundStyle(.orange)
            }
        }
    }
    private func row(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle").font(.title3).foregroundStyle(.orange)
            Text(text).font(.subheadline).lineLimit(1)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, minHeight: compact ? 30 : 34, alignment: .leading)
            .contentShape(Rectangle())
    }
}
