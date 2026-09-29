import Foundation

public struct PlannerTask: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var date: String
    public var done: Bool
    public var cat: Int
    public var order: Double
    public var doneAt: Double
    public var rolled: Bool
    public var reminderMinute: Int?
    public var important: Bool
    public var goalID: String?
    public var deadline: String?
    public init(id: String, text: String, date: String, done: Bool = false, cat: Int = 0, order: Double = 0, doneAt: Double = 0, rolled: Bool = false, reminderMinute: Int? = nil, important: Bool = false) {
        self.id = id; self.text = text; self.date = date; self.done = done
        self.cat = cat; self.order = order; self.doneAt = doneAt; self.rolled = rolled
        self.reminderMinute = reminderMinute
        self.important = important
    }
    enum CodingKeys: String, CodingKey { case id, text, date, done, cat, order, doneAt, rolled, reminderMinute, important, goalID, deadline }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); text = try c.decode(String.self, forKey: .text)
        date = try c.decode(String.self, forKey: .date)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        cat = try c.decodeIfPresent(Int.self, forKey: .cat) ?? 0
        order = try c.decodeIfPresent(Double.self, forKey: .order) ?? 0
        doneAt = try c.decodeIfPresent(Double.self, forKey: .doneAt) ?? 0
        rolled = try c.decodeIfPresent(Bool.self, forKey: .rolled) ?? false
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute)
        important = try c.decodeIfPresent(Bool.self, forKey: .important) ?? false
        goalID = try c.decodeIfPresent(String.self, forKey: .goalID)
        deadline = try c.decodeIfPresent(String.self, forKey: .deadline)
    }
}

public struct RepeatRule: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var cat: Int
    public var from: String
    public var reminderMinute: Int?
    public var important: Bool
    public var order: Double
    public init(id: String, text: String, cat: Int = 0, from: String, reminderMinute: Int? = nil, important: Bool = false, order: Double = -1) {
        self.id = id; self.text = text; self.cat = cat; self.from = from
        self.reminderMinute = reminderMinute
        self.important = important; self.order = order
    }
    enum CodingKeys: String, CodingKey { case id, text, cat, from, reminderMinute, important, order }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); text = try c.decode(String.self, forKey: .text)
        from = try c.decode(String.self, forKey: .from); cat = try c.decodeIfPresent(Int.self, forKey: .cat) ?? 0
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute)
        important = try c.decodeIfPresent(Bool.self, forKey: .important) ?? false
        order = try c.decodeIfPresent(Double.self, forKey: .order) ?? -1
    }
}

public enum TaskReference: Codable, Hashable, Sendable {
    case task(String)
    case repeating(ruleID: String, day: Day)
    public var isRepeating: Bool { if case .repeating = self { return true }; return false }
}
public struct TaskItem: Equatable, Sendable, Identifiable {
    public var reference: TaskReference
    public var id: TaskReference { reference }
    public var text: String
    public var cat: Int
    public var done: Bool
    public var rolled: Bool
    public var order: Double
    public var doneAt: Double
    public var important: Bool = false
    public var goalTitle: String? = nil
}
public struct DaySnapshot: Equatable, Sendable {
    public var open: [TaskItem] = []
    public var completed: [TaskItem] = []
    public var totalCount: Int = 0
    public var completedCount: Int = 0
    public init() {}
}
public enum RemovedItem: Sendable {
    case task(PlannerTask)
    case repeating(RepeatRule, completedDays: [String])
}
