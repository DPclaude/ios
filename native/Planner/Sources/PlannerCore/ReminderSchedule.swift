import Foundation

public struct ReminderEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let day: Day
    public let date: Date
    public let reference: TaskReference
}

public struct ReminderSchedule: Sendable {
    public let entries: [ReminderEntry]
    public let omittedCount: Int
    public let dailyThrough: Day
    public init(document: PlannerDocument, now: Date = .now, timeZone: TimeZone = .current) {
        let today = Day.today(now: now, timeZone: timeZone)
        dailyThrough = today.adding(days: 29, timeZone: timeZone)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        var candidates: [ReminderEntry] = []
        func append(_ reference: TaskReference, text: String, day: Day, minute: Int?) {
            guard let minute, (0..<1440).contains(minute),
                  let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0,
                                           of: day.date(timeZone: timeZone), matchingPolicy: .nextTime,
                                           repeatedTimePolicy: .first, direction: .forward), date > now else { return }
            // JSON encodes the full reference, avoiding collisions from arbitrary imported IDs.
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let encoded = (try? encoder.encode(reference).base64EncodedString()) ?? ""
            candidates.append(ReminderEntry(id: "planner.reminder.\(encoded).\(day.rawValue)", text: text, day: day, date: date, reference: reference))
        }
        for task in document.tasks where !task.done {
            if let day = Day(rawValue: task.date), day >= today {
                append(.task(task.id), text: task.text, day: day, minute: task.reminderMinute)
            }
        }
        for offset in 0..<30 {
            let day = today.adding(days: offset, timeZone: timeZone)
            for rule in document.repeats where rule.from <= day.rawValue && !(document.repeatDone[day.rawValue] ?? []).contains(rule.id) {
                append(.repeating(ruleID: rule.id, day: day), text: rule.text, day: day, minute: rule.reminderMinute)
            }
        }
        candidates.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        entries = Array(candidates.prefix(60)); omittedCount = max(0, candidates.count - entries.count)
    }
}

extension PlannerDocument {
    public func reminderMinute(for reference: TaskReference) -> Int? {
        switch reference {
        case .task(let id): return tasks.first(where: { $0.id == id })?.reminderMinute
        case .repeating(let id, _): return repeats.first(where: { $0.id == id })?.reminderMinute
        }
    }
    public mutating func setReminder(_ minute: Int?, for reference: TaskReference) {
        guard minute == nil || (0..<1440).contains(minute!) else { return }
        switch reference {
        case .task(let id):
            if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].reminderMinute = minute }
        case .repeating(let id, _):
            if let i = repeats.firstIndex(where: { $0.id == id }) { repeats[i].reminderMinute = minute }
        }
    }
}
