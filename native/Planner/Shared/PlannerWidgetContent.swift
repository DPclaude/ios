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
                            // WidgetKit pre-renders both Toggle states, so feedback doesn't wait for perform().
                            Toggle(isOn: item.done, intent: CompletePlanIntent(reference: item.reference, generation: generation, day: projection.day)) {
                                Text(item.text)
                            }.toggleStyle(PlannerWidgetTaskToggleStyle(item: item, compact: compact))
                                .disabled(item.done)
                        } else { PlannerWidgetTaskRow(item: item, isOn: item.done, compact: compact) }
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
}

struct PlannerWidgetTaskToggleStyle: ToggleStyle {
    let item: TaskItem
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        Button {
            // Completion is one-way in the widget; further taps must not undo its optimistic feedback.
            if !configuration.isOn { configuration.isOn = true }
        } label: {
            PlannerWidgetTaskRow(item: item, isOn: configuration.isOn, compact: compact)
        }
        .buttonStyle(.plain).disabled(configuration.isOn)
        .animation(.easeOut(duration: 0.16), value: configuration.isOn)
    }
}

struct PlannerWidgetTaskRow: View {
    let item: TaskItem
    let isOn: Bool
    let compact: Bool
    private var pending: Bool { isOn && !item.done }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(pending ? Color.green : (item.done ? .secondary : .orange))
                .font(.system(size: 21)).scaleEffect(pending ? 1.1 : 1)
                .contentTransition(.symbolEffect(.replace))
            Text(item.text).font(.subheadline).lineLimit(1).strikethrough(isOn)
                .foregroundStyle(isOn ? Color.secondary : (item.important ? .red : .primary))
            Spacer(minLength: 0)
            if pending {
                Text("正在完成").font(.caption2).foregroundStyle(.green).fixedSize()
                    .transition(.opacity)
            }
        }.frame(maxWidth: .infinity, minHeight: compact ? 24 : 30, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(pending ? Color.green.opacity(0.10) : .clear))
            .contentShape(Rectangle()).transition(.identity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.text)
            .accessibilityValue(pending ? "正在完成" : (item.done ? "已完成" : "待完成"))
    }
}
