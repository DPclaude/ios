import Foundation

public struct PlannerGoal: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var deadline: String
    public init(id: String, title: String, deadline: String) {
        self.id = id; self.title = title; self.deadline = deadline
    }
}

public struct GoalStageDraft: Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var deadline: Day
    public var isNew: Bool
    public init(id: String = UUID().uuidString, text: String = "", deadline: Day, isNew: Bool = true) {
        self.id = id; self.text = text; self.deadline = deadline; self.isNew = isNew
    }
}
public struct GoalProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public var isComplete: Bool { total > 0 && completed == total }
    public var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
}
public enum GoalError: LocalizedError {
    case invalid(String), stale
    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .stale: return "目标或阶段已被修改或删除，请关闭编辑页后重新打开。"
        }
    }
}
extension PlannerTask {
    public var goalDraft: GoalStageDraft {
        GoalStageDraft(id: id, text: text, deadline: Day(rawValue: deadline ?? date) ?? .today(), isNew: false)
    }
}
extension PlannerDocument {
    public func goal(for task: PlannerTask) -> PlannerGoal? { goals.first { $0.id == task.goalID } }
    public func goalStages(_ id: String) -> [PlannerTask] {
        tasks.enumerated().filter { $0.element.goalID == id }.sorted {
            let a = $0.element.deadline ?? $0.element.date, b = $1.element.deadline ?? $1.element.date
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }
    public func goalProgress(_ id: String) -> GoalProgress {
        let stages = goalStages(id)
        return GoalProgress(completed: stages.filter(\.done).count, total: stages.count)
    }
    public mutating func saveGoal(id: String, title: String, deadline: Day, stages: [GoalStageDraft], creating: Bool, today: Day) throws {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw GoalError.invalid("请填写目标名称。") }
        guard !stages.isEmpty else { throw GoalError.invalid("请至少添加一个阶段。") }
        guard Set(stages.map(\.id)).count == stages.count else { throw GoalError.invalid("阶段编号重复，请重新打开编辑页。") }
        guard creating ? !goals.contains(where: { $0.id == id }) : goals.contains(where: { $0.id == id }) else { throw GoalError.stale }
        var candidate = self
        let goal = PlannerGoal(id: id, title: name, deadline: deadline.rawValue)
        if let index = candidate.goals.firstIndex(where: { $0.id == id }) { candidate.goals[index] = goal }
        else { candidate.goals.append(goal) }
        let kept = Set(stages.map(\.id))
        candidate.tasks.removeAll { $0.goalID == id && !kept.contains($0.id) }
        for stage in stages {
            let text = stage.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw GoalError.invalid("请填写每个阶段的内容。") }
            guard stage.deadline <= deadline else { throw GoalError.invalid("阶段截止日期不能晚于目标截止日期。") }
            if stage.isNew {
                guard !candidate.tasks.contains(where: { $0.id == stage.id }) else { throw GoalError.stale }
                let execution = max(stage.deadline, today)
                candidate.add(text: text, category: 0, day: execution, id: stage.id)
                let index = candidate.tasks.count - 1
                candidate.tasks[index].goalID = id
                candidate.tasks[index].deadline = stage.deadline.rawValue
                candidate.tasks[index].rolled = stage.deadline < today
            } else {
                guard let index = candidate.tasks.firstIndex(where: { $0.id == stage.id && $0.goalID == id }) else { throw GoalError.stale }
                candidate.tasks[index].text = text
                if candidate.tasks[index].deadline != stage.deadline.rawValue {
                    // Completed records keep their execution date; changing a due date never unchecks them.
                    if !candidate.tasks[index].done {
                        candidate.tasks[index].date = max(stage.deadline, today).rawValue
                        candidate.tasks[index].rolled = stage.deadline < today
                    }
                    candidate.tasks[index].deadline = stage.deadline.rawValue
                }
            }
        }
        try BackupCodec.validate(candidate)
        self = candidate
    }
    public mutating func deleteGoal(_ id: String) {
        goals.removeAll { $0.id == id }
        tasks.removeAll { $0.goalID == id }
    }
}
