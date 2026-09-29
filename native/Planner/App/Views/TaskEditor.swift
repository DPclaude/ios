import SwiftUI
import PlannerCore

struct TaskEditor: View {
    let model: PlannerViewModel
    let item: TaskItem?
    private let originalDay: Day
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var category: Int
    @State private var date: Date
    @State private var repeating = false
    @State private var keepAdding = false
    @State private var confirmDelete = false
    @State private var confirmCancelRepeat = false
    @FocusState private var focused: Bool
    init(model: PlannerViewModel, item: TaskItem?) {
        self.model = model; self.item = item; originalDay = model.selectedDay
        _text = State(initialValue: item?.text ?? "")
        _category = State(initialValue: item?.cat ?? model.category ?? 0)
        _date = State(initialValue: model.selectedDay.date())
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("计划内容") {
                    TextEditor(text: $text).frame(minHeight: 100).focused($focused)
                        .accessibilityLabel("计划内容").accessibilityIdentifier("taskText")
                }
                Section {
                    Picker("分类", selection: $category) { ForEach(0..<4) { Text(PlannerCategory.names[$0]).tag($0) } }
                    if item?.reference.isRepeating != true {
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                    }
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
                            Button("改为每天重复", systemImage: "repeat") { save(makeDaily: true) }
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
            }
            .task { if item == nil { focused = true } }
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
        if let item {
            model.saveEditor(item.reference, text: value, category: category, originalDay: originalDay, editedDay: day, makeDaily: makeDaily)
            dismiss()
        } else {
            model.perform(.add(text: value, category: category, day: day, repeating: repeating))
            model.select(day: day)
            if keepAdding { text = ""; focused = true } else { dismiss() }
        }
    }
}
