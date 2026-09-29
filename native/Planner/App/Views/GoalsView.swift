import SwiftUI
import PlannerCore

struct GoalsView: View {
    let model: PlannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    private var ordered: [PlannerGoal] { model.document.goals.sorted { $0.deadline == $1.deadline ? $0.id < $1.id : $0.deadline < $1.deadline } }
    var body: some View {
        NavigationStack {
            List {
                if ordered.isEmpty {
                    ContentUnavailableView("把大目标，拆成小步", systemImage: "target", description: Text("定一个完成日期，再写下每个阶段要做什么。"))
                } else {
                    goalSection("进行中", complete: false)
                    goalSection("已完成", complete: true)
                }
                GoalSaveStatus(model: model)
            }
            .navigationTitle("长期目标")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("新增目标", systemImage: "plus") { adding = true }.accessibilityIdentifier("addGoal").disabled(!model.canEdit)
                }
            }
            .sheet(isPresented: $adding) { GoalEditor(model: model, goal: nil) }
        }
    }
    @ViewBuilder private func goalSection(_ title: String, complete: Bool) -> some View {
        let goals = ordered.filter { model.document.goalProgress($0.id).isComplete == complete }
        if !goals.isEmpty {
            Section(title) {
                ForEach(goals) { goal in
                    NavigationLink {
                        GoalDetailView(model: model, goalID: goal.id)
                    } label: {
                        GoalSummary(goal: goal, progress: model.document.goalProgress(goal.id))
                    }.accessibilityIdentifier("goal-\(goal.title)")
                }
            }
        }
    }
}

private struct GoalSummary: View {
    let goal: PlannerGoal
    let progress: GoalProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(goal.title).font(.headline).foregroundStyle(progress.isComplete ? Color.secondary : .primary)
            HStack {
                Label("\(goal.deadline) 前完成", systemImage: "calendar")
                Spacer(minLength: 4)
                Text("\(progress.completed)/\(progress.total)")
            }.font(.caption).foregroundStyle(.secondary)
            ProgressView(value: progress.fraction).tint(progress.isComplete ? .green : .orange)
        }.padding(.vertical, 6)
    }
}

private struct GoalDetailView: View {
    let model: PlannerViewModel
    let goalID: String
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var feedback = 0
    private var goal: PlannerGoal? { model.document.goals.first { $0.id == goalID } }
    var body: some View {
        Group {
            if let goal {
                let progress = model.document.goalProgress(goalID)
                List {
                    Section {
                        GoalSummary(goal: goal, progress: progress)
                        Text("已完成 \(progress.completed) / \(progress.total) 阶段")
                            .font(.subheadline).foregroundStyle(progress.isComplete ? Color.green : .secondary)
                    }
                    Section("阶段 · 按截止日期") {
                        ForEach(model.document.goalStages(goalID)) { stage in
                            HStack(alignment: .top, spacing: 12) {
                                Button {
                                    model.perform(.toggle(.task(stage.id))); feedback += 1
                                } label: {
                                    Image(systemName: stage.done ? "checkmark.circle.fill" : "circle")
                                        .font(.title2).foregroundStyle(stage.done ? Color.green : .orange)
                                        .frame(width: 44, height: 44)
                                }.buttonStyle(.plain).disabled(!model.canEdit)
                                    .accessibilityLabel("\(stage.done ? "撤销完成" : "完成阶段")：\(stage.text)")
                                    .accessibilityIdentifier("goalToggle-\(stage.text)")
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(stage.text).strikethrough(stage.done).foregroundStyle(stage.done ? Color.secondary : (stage.important ? .red : .primary))
                                    Text("\(stage.deadline ?? stage.date) 前完成").font(.caption).foregroundStyle(.secondary)
                                    if !stage.done, let deadline = stage.deadline, deadline < Day.today().rawValue {
                                        Text("已逾期 · 仍可继续完成").font(.caption).foregroundStyle(.orange)
                                    }
                                }.padding(.vertical, 8)
                            }
                        }
                    }
                    Section {
                        Text("阶段到期会显示在当天计划和桌面组件中。在任一处完成，目标进度都会同步。可在当天计划中给阶段设置提醒。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    GoalSaveStatus(model: model)
                    Section { Button("删除目标及所有阶段", role: .destructive) { confirmDelete = true }.disabled(!model.canEdit) }
                }
                .sheet(isPresented: $editing) { GoalEditor(model: model, goal: goal) }
            } else { ContentUnavailableView("目标已删除", systemImage: "target") }
        }
        .navigationTitle("目标详情").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("编辑") { editing = true }.accessibilityIdentifier("editGoal").disabled(goal == nil || !model.canEdit) }
        }
        .confirmationDialog("删除目标及所有阶段？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除目标和阶段", role: .destructive) { model.deleteGoal(goalID); dismiss() }
        } message: { Text("关联的计划、完成记录和提醒也会删除。此操作不能撤销。") }
        .sensoryFeedback(.success, trigger: feedback)
    }
}

private struct GoalSaveStatus: View {
    let model: PlannerViewModel
    var body: some View {
        if case .failed(let message) = model.saveState {
            Section("尚未保存") {
                Text(message).font(.footnote).foregroundStyle(.red)
                Button("重试保存") { Task { await model.retrySave() } }
            }
        }
    }
}
