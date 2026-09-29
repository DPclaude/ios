import SwiftUI
import PlannerCore

struct PlannerWidgetContent: View {
    let projection: WidgetProjection?
    let message: String?
    let compact: Bool
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
                    ForEach(Array(projection.titles.prefix(compact ? 1 : 4).enumerated()), id: \.offset) { _, title in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle").font(.caption).foregroundStyle(.orange).padding(.top, 3)
                            Text(title).font(.subheadline).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                Spacer(minLength: 0)
                ProgressView(value: Double(projection.completed), total: Double(max(1, projection.total))).tint(.orange)
                Text("轻点打开 · 划掉已完成的事").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(message ?? "打开计划本，开始今天的计划").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Label("打开计划本", systemImage: "arrow.up.forward").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
