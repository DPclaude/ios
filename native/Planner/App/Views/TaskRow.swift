import SwiftUI
import PlannerCore

enum PlannerCategory {
    static let names = ["", "工作", "私事", "学习"]
    static func color(_ value: Int) -> Color { [.secondary, .blue, .pink, .green][value] }
}

struct TaskRow: View {
    let item: TaskItem
    let toggle: () -> Void
    let edit: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button(action: toggle) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(item.done ? Color.orange : .secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "标为未完成：\(item.text)" : "完成：\(item.text)")
            .accessibilityIdentifier("toggle-\(item.text)")
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.text).font(.body).foregroundStyle(item.done ? Color.secondary : (item.important ? .red : .primary))
                        .strikethrough(item.done).multilineTextAlignment(.leading)
                    if let goalTitle = item.goalTitle { Label(goalTitle, systemImage: "target").font(.caption).foregroundStyle(.secondary) }
                    HStack(spacing: 10) {
                        if item.important { Label("重要", systemImage: "exclamationmark").foregroundStyle(.red) }
                        if item.cat > 0 { Text(PlannerCategory.names[item.cat]).foregroundStyle(PlannerCategory.color(item.cat)) }
                        if item.reference.isRepeating { Label("每天", systemImage: "repeat") }
                        if item.rolled { Label("顺延", systemImage: "arrow.turn.down.right") }
                    }.font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("edit-\(item.text)")
            .accessibilityHint("编辑计划")
        }.accessibilityElement(children: .contain)
    }
}
