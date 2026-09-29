import Foundation

public struct PlannerDocument: Codable, Equatable, Sendable {
    public var tasks: [PlannerTask] = []
    public var notes: [String: String] = [:]
    public var repeats: [RepeatRule] = []
    public var repeatDone: [String: [String]] = [:]
    public var goals: [PlannerGoal] = []
    public var lastCompleted: TaskReference?
    public init() {}
    enum CodingKeys: String, CodingKey { case tasks, notes, repeats, repeatDone, goals, lastCompleted }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decode([PlannerTask].self, forKey: .tasks)
        notes = try c.decodeIfPresent([String: String].self, forKey: .notes) ?? [:]
        repeats = try c.decodeIfPresent([RepeatRule].self, forKey: .repeats) ?? []
        repeatDone = try c.decodeIfPresent([String: [String]].self, forKey: .repeatDone) ?? [:]
        goals = try c.decodeIfPresent([PlannerGoal].self, forKey: .goals) ?? []
        lastCompleted = try c.decodeIfPresent(TaskReference.self, forKey: .lastCompleted)
    }
    public func snapshot(day: Day, category: Int?) -> DaySnapshot {
        let completedIDs = Set(repeatDone[day.rawValue] ?? [])
        let repeating = repeats.filter { $0.from <= day.rawValue }.map {
            TaskItem(reference: .repeating(ruleID: $0.id, day: day), text: $0.text, cat: $0.cat,
                     done: completedIDs.contains($0.id), rolled: false, order: $0.order, doneAt: 0, important: $0.important)
        }
        let regular = tasks.filter { $0.date == day.rawValue }.map {
            TaskItem(reference: .task($0.id), text: $0.text, cat: $0.cat, done: $0.done, rolled: $0.rolled, order: $0.order, doneAt: $0.doneAt, important: $0.important, goalTitle: goal(for: $0)?.title)
        }
        let all = repeating + regular
        let visible = all.enumerated().filter { category == nil || $0.element.cat == category }
        var result = DaySnapshot()
        result.totalCount = all.count; result.completedCount = all.filter(\.done).count
        result.open = visible.filter { !$0.element.done }.sorted {
            $0.element.order == $1.element.order ? $0.offset < $1.offset : $0.element.order < $1.element.order
        }.map(\.element)
        result.completed = visible.filter { $0.element.done }.sorted {
            $0.element.order == $1.element.order ? $0.offset < $1.offset : $0.element.order < $1.element.order
        }.map(\.element)
        return result
    }
    public mutating func add(text: String, category: Int, day: Day, id: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, (0...3).contains(category), !tasks.contains(where: { $0.id == id }) else { return }
        let order = ((tasks.filter { $0.date == day.rawValue }.map(\.order) + repeats.map(\.order)).max() ?? 0) + 1
        tasks.append(PlannerTask(id: id, text: value, date: day.rawValue, cat: category, order: order))
    }
    public mutating func toggle(_ reference: TaskReference, now: Date) {
        switch reference {
        case .task(let id):
            guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
            tasks[i].done.toggle(); tasks[i].doneAt = tasks[i].done ? now.timeIntervalSince1970 * 1000 : 0
            if tasks[i].done { tasks[i].rolled = false }
            if tasks[i].done { lastCompleted = reference }
            else if lastCompleted == reference { lastCompleted = nil }
        case .repeating(let id, let day):
            guard repeats.contains(where: { $0.id == id && $0.from <= day.rawValue }) else { return }
            var ids = repeatDone[day.rawValue] ?? []
            if ids.contains(id) { ids.removeAll { $0 == id } } else { ids.append(id) }
            repeatDone[day.rawValue] = ids
            if ids.contains(id) { lastCompleted = reference }
            else if lastCompleted == reference { lastCompleted = nil }
        }
    }
    public mutating func edit(_ reference: TaskReference, text: String, category: Int) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, (0...3).contains(category) else { return }
        switch reference {
        case .task(let id):
            guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
            tasks[i].text = value; tasks[i].cat = category
        case .repeating(let id, _):
            guard let i = repeats.firstIndex(where: { $0.id == id }) else { return }
            repeats[i].text = value; repeats[i].cat = category
        }
    }
    public mutating func pin(taskID: String) {
        guard let i = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let minimum = (tasks.filter { $0.date == tasks[i].date }.map(\.order) + repeats.map(\.order)).min() ?? 0
        tasks[i].order = min(minimum, -1) - 1
    }
    public mutating func moveToNextDay(taskID: String, timeZone: TimeZone) {
        guard let i = tasks.firstIndex(where: { $0.id == taskID }), let day = Day(rawValue: tasks[i].date) else { return }
        tasks[i].date = day.adding(days: 1, timeZone: timeZone).rawValue
        tasks[i].done = false; tasks[i].doneAt = 0; tasks[i].rolled = false
    }
    public mutating func convertToRepeat(taskID: String, ruleID: String) {
        guard let i = tasks.firstIndex(where: { $0.id == taskID }), tasks[i].goalID == nil, !repeats.contains(where: { $0.id == ruleID }) else { return }
        let t = tasks.remove(at: i)
        repeats.append(RepeatRule(id: ruleID, text: t.text, cat: t.cat, from: t.date, reminderMinute: t.reminderMinute, important: t.important, order: t.order))
        if t.done { repeatDone[t.date, default: []].append(ruleID) }
    }
    public mutating func cancelRepeat(ruleID: String, day: Day, taskID: String, now: Date) {
        guard let rule = repeats.first(where: { $0.id == ruleID }) else { return }
        let done = (repeatDone[day.rawValue] ?? []).contains(ruleID)
        _ = remove(.repeating(ruleID: ruleID, day: day))
        tasks.append(PlannerTask(id: taskID, text: rule.text, date: day.rawValue, done: done, cat: rule.cat, order: rule.order, doneAt: done ? now.timeIntervalSince1970 * 1000 : 0, reminderMinute: rule.reminderMinute, important: rule.important))
    }
    public mutating func rollover(today: Day, timeZone: TimeZone) {
        for i in tasks.indices where !tasks[i].done && tasks[i].date < today.rawValue {
            tasks[i].date = today.rawValue; tasks[i].rolled = true
        }
        let cutoff = today.adding(days: -90, timeZone: timeZone).rawValue
        repeatDone = repeatDone.filter { $0.key >= cutoff }
    }
    public mutating func setImportant(_ value: Bool, for reference: TaskReference) {
        switch reference {
        case .task(let id):
            if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].important = value }
        case .repeating(let id, _):
            if let i = repeats.firstIndex(where: { $0.id == id }) { repeats[i].important = value }
        }
    }
    public mutating func reorder(_ ordered: [TaskReference], day: Day, completed: Bool) {
        let state = snapshot(day: day, category: nil)
        let all = (completed ? state.completed : state.open).map(\.reference)
        let selected = Set(ordered)
        guard !ordered.isEmpty, selected.count == ordered.count, selected.isSubset(of: Set(all)) else { return }
        var iterator = ordered.makeIterator()
        let combined = all.map { selected.contains($0) ? iterator.next()! : $0 }
        for (rank, ref) in combined.enumerated() {
            switch ref {
            case .task(let id):
                if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].order = Double(rank) }
            case .repeating(let id, _):
                if let i = repeats.firstIndex(where: { $0.id == id }) { repeats[i].order = Double(rank) }
            }
        }
    }
    public mutating func remove(_ reference: TaskReference) -> RemovedItem? {
        switch reference {
        case .task(let id):
            guard let i = tasks.firstIndex(where: { $0.id == id }) else { return nil }
            return .task(tasks.remove(at: i))
        case .repeating(let id, _):
            guard let i = repeats.firstIndex(where: { $0.id == id }) else { return nil }
            let dates = repeatDone.filter { $0.value.contains(id) }.map(\.key)
            for key in Array(repeatDone.keys) { repeatDone[key]?.removeAll { $0 == id } }
            return .repeating(repeats.remove(at: i), completedDays: dates)
        }
    }
    public mutating func restore(_ removed: RemovedItem, today: Day, timeZone: TimeZone) {
        switch removed {
        case .task(let task):
            if let goalID = task.goalID, !goals.contains(where: { $0.id == goalID }) { return }
            if !tasks.contains(where: { $0.id == task.id }) { tasks.append(task) }
        case .repeating(let rule, let dates):
            if !repeats.contains(where: { $0.id == rule.id }) { repeats.append(rule) }
            for date in dates where !(repeatDone[date] ?? []).contains(rule.id) { repeatDone[date, default: []].append(rule.id) }
        }
        rollover(today: today, timeZone: timeZone)
    }
}
