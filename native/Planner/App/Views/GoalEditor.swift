import SwiftUI
import PlannerCore

struct GoalEditor: View {
    let model: PlannerViewModel
    let goal: PlannerGoal?
    @Environment(\.dismiss) private var dismiss
    @State private var identifier: String
    @State private var title: String
    @State private var deadline: Date
    @State private var stages: [GoalStageDraft]
    @State private var errorMessage: String?
    @State private var removing: GoalStageDraft?
    @FocusState private var focusedField: String?
    init(model: PlannerViewModel, goal: PlannerGoal?) {
        self.model = model; self.goal = goal
        _identifier = State(initialValue: goal?.id ?? UUID().uuidString)
        _title = State(initialValue: goal?.title ?? "")
        _deadline = State(initialValue: Day(rawValue: goal?.deadline ?? "")?.date() ?? Day.today().adding(days: 30).date())
        let existing = goal.map { model.document.goalStages($0.id).map(\.goalDraft) } ?? []
        _stages = State(initialValue: existing.isEmpty ? [GoalStageDraft(deadline: .today())] : existing)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("长期目标") {
                    TextField("想完成什么？", text: $title)
                        .focused($focusedField, equals: "title").accessibilityIdentifier("goalTitle")
                    DatePicker("目标截止日期", selection: $deadline, displayedComponents: .date)
                }
                Section {
                    Text("分成 \(stages.count) 个阶段").font(.headline)
                } footer: { Text("每个阶段都有自己的截止日期。到期会出现在当天计划，完成状态与桌面组件同步。") }
                ForEach($stages) { $stage in
                    let index = stages.firstIndex(where: { $0.id == stage.id }) ?? 0
                    Section("阶段 \(index + 1)") {
                        TextField("这个阶段要完成什么？", text: $stage.text)
                            .focused($focusedField, equals: stage.id).accessibilityIdentifier("stageTitle-\(index)")
                        DatePicker("阶段截止日期", selection: Binding(get: { stage.deadline.date() }, set: { stage.deadline = .today(now: $0) }), displayedComponents: .date)
                        if stages.count > 1 {
                            Button("移除这个阶段", role: .destructive) {
                                if stage.isNew { stages.removeAll { $0.id == stage.id } }
                                else { removing = stage }
                            }
                        }
                    }
                }
                Section {
                    Button("添加阶段", systemImage: "plus.circle") {
                        stages.append(GoalStageDraft(deadline: min(stages.last?.deadline ?? .today(), .today(now: deadline))))
                    }.accessibilityIdentifier("addStage")
                }
                if let validation { Section { Text(validation).font(.footnote).foregroundStyle(.orange) } }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .scrollDismissesKeyboard(.interactively).disabled(!model.canEdit)
            .navigationTitle(goal == nil ? "新增长期目标" : "编辑长期目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try model.saveGoal(id: identifier, title: title, deadline: .today(now: deadline), stages: stages, creating: goal == nil)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }.bold().accessibilityIdentifier("saveGoal").disabled(validation != nil || !model.canEdit)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }.accessibilityIdentifier("goalDismissKeyboard")
                }
            }
            .confirmationDialog("移除这个阶段？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("移除阶段", role: .destructive) {
                    if let removing { stages.removeAll { $0.id == removing.id } }; removing = nil
                }
            } message: { Text("保存目标后，对应的计划、提醒和完成记录会一起删除。取消编辑则保留原内容。") }
        }
    }
    private var validation: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "先为目标起个名字。" }
        if stages.contains(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return "请填写每个阶段的内容。" }
        if stages.contains(where: { $0.deadline > .today(now: deadline) }) { return "阶段截止日期不能晚于目标截止日期。" }
        return nil
    }
}
