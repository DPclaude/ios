import SwiftUI
import PlannerCore

struct TaskEditor: View {
    let model: PlannerViewModel
    let item: TaskItem?
    @State private var originalDay: Day
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var category: Int
    @State private var date: Date
    @State private var repeating = false
    @State private var keepAdding = false
    @State private var confirmDelete = false
    @State private var confirmCancelRepeat = false
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var important: Bool
    @FocusState private var focused: Bool
    init(model: PlannerViewModel, item: TaskItem?) {
        self.model = model; self.item = item
        _originalDay = State(initialValue: model.selectedDay)
        _text = State(initialValue: item?.text ?? "")
        _important = State(initialValue: item?.important ?? false)
        _category = State(initialValue: item?.cat ?? model.category ?? 0)
        _date = State(initialValue: model.selectedDay.date())
        let minute = item.flatMap { model.document.reminderMinute(for: $0.reference) }
        _reminderEnabled = State(initialValue: minute != nil)
        _reminderTime = State(initialValue: Calendar.current.date(bySettingHour: (minute ?? 540) / 60, minute: (minute ?? 540) % 60, second: 0, of: .now) ?? .now)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("计划内容") {
                    TextEditor(text: $text).frame(minHeight: 72).focused($focused)
                        .foregroundStyle(important ? Color.red : .primary)
                        .accessibilityLabel("计划内容").accessibilityIdentifier("taskText")
                    Toggle("重要计划", isOn: $important).tint(.red).accessibilityIdentifier("importantToggle")
                }
                Section {
                    Toggle("提醒我", isOn: $reminderEnabled).accessibilityIdentifier("reminderToggle")
                    if reminderEnabled {
                        DatePicker("提醒时间", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("reminderTime")
                        if !PlannerRuntime.shared.reminders.authorized {
                            Text("需要允许通知，才能收到提醒。可以在设置中开启。")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                } header: { Text("通知提醒") } footer: {
                    Text(item?.reference.isRepeating == true || repeating ? "每天在此时间提醒，完成当天计划后取消当天提醒。" : "在计划日期的这个时间提醒。已过去的时间不会补发；完成后取消提醒。")
                }
                Section("分类") {
                    HStack(spacing: 12) {
                        ForEach(1..<4) { value in
                            Button { category = category == value ? 0 : value } label: {
                                Text(PlannerCategory.names[value]).frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .foregroundStyle(category == value ? Color.white : PlannerCategory.color(value))
                                    .background(category == value ? PlannerCategory.color(value) : PlannerCategory.color(value).opacity(0.1), in: Capsule())
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(category == value ? .isSelected : [])
                        }
                    }
                }
                Section {
                    if item?.reference.isRepeating != true { DatePicker("日期", selection: $date, displayedComponents: .date) }
                    if item == nil {
                        Toggle("每天重复", isOn: $repeating)
                        Toggle("保存后继续添加", isOn: $keepAdding)
                    }
                } footer: {
                    if item?.reference.isRepeating == true { Text("这是每日计划。修改内容和分类会应用到整条重复规则。") }
                }
                if let item {
                    Section {
                        if case .task(let id) = item.reference {
                            Button("置顶", systemImage: "pin") { model.perform(.pin(id)); dismiss() }
                            Button("移到下一天", systemImage: "arrow.right") { model.perform(.tomorrow(id)); dismiss() }
                            if item.goalTitle == nil { Button("改为每天重复", systemImage: "repeat") { save(makeDaily: true) } }
                        } else {
                            Button("取消每天重复", systemImage: "repeat") { confirmCancelRepeat = true }
                        }
                        Button(item.reference.isRepeating ? "删除整条重复规则" : "删除计划", role: .destructive) {
                            if item.reference.isRepeating { confirmDelete = true }
                            else { model.perform(.delete(item.reference)); dismiss() }
                        }.accessibilityIdentifier("deleteTask")
                    }
                }
            }
            .disabled(!model.canEdit)
            .navigationTitle(item == nil ? "添加计划" : "编辑计划").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.bold().accessibilityIdentifier("saveTask")
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.canEdit)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focused = false }.accessibilityIdentifier("dismissKeyboard")
                }
            }
            .task { if item == nil { focused = true } }
            .onChange(of: reminderEnabled) { _, enabled in
                if enabled && !ProcessInfo.processInfo.arguments.contains("--uitesting") {
                    Task { await PlannerRuntime.shared.reminders.requestAuthorization() }
                }
            }
            .confirmationDialog("删除整条重复规则？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除整条规则", role: .destructive) {
                    if let item { model.perform(.delete(item.reference)) }; dismiss()
                }
            } message: { Text("所有日期的该计划和完成记录都会移除，删除后可在 7 秒内撤销。") }
            .confirmationDialog("取消每天重复？", isPresented: $confirmCancelRepeat, titleVisibility: .visible) {
                Button("取消重复，保留当天计划", role: .destructive) {
                    if let item, case .repeating(let id, let day) = item.reference { model.perform(.cancelDaily(ruleID: id, day: day)) }
                    dismiss()
                }
            } message: { Text("移除整条规则，在当前日期保留一条普通计划。其他日期的完成记录也会移除。") }
        }
    }
    private func save(makeDaily: Bool = false) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let day = Day.today(now: date)
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let minute = reminderEnabled ? (components.hour ?? 9) * 60 + (components.minute ?? 0) : nil
        if let item {
            model.saveEditor(item.reference, text: value, category: category, originalDay: originalDay, editedDay: day, makeDaily: makeDaily, reminderMinute: .some(minute), important: important)
            dismiss()
        } else {
            model.perform(.add(text: value, category: category, day: day, repeating: repeating, reminderMinute: minute, important: important))
            model.select(day: day)
            if keepAdding { text = ""; important = false; focused = true } else { dismiss() }
        }
    }
}
