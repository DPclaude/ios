import Foundation

public enum BackupError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let field): return "备份中的\(field)无效，原有数据未被覆盖。" }
    }
}
public enum BackupCodec {
    public static func decode(_ data: Data) throws -> PlannerDocument {
        var doc = try JSONDecoder().decode(PlannerDocument.self, from: data)
        try validate(doc)
        let ids = Set(doc.repeats.map(\.id))
        for day in Array(doc.repeatDone.keys) {
            var seen = Set<String>()
            doc.repeatDone[day] = doc.repeatDone[day]?.filter { ids.contains($0) && seen.insert($0).inserted }
        }
        return doc
    }
    public static func encode(_ document: PlannerDocument) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }
    public static func validate(_ document: PlannerDocument) throws {
        guard Set(document.tasks.map(\.id)).count == document.tasks.count,
              Set(document.repeats.map(\.id)).count == document.repeats.count else { throw BackupError.invalid("任务编号") }
        for t in document.tasks {
            if let minute = t.reminderMinute, !(0..<1440).contains(minute) { throw BackupError.invalid("提醒时间") }
            guard !t.id.isEmpty, !t.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Day(rawValue: t.date) != nil, (0...3).contains(t.cat), t.order.isFinite, t.doneAt.isFinite else { throw BackupError.invalid("任务") }
        }
        for r in document.repeats {
            if let minute = r.reminderMinute, !(0..<1440).contains(minute) { throw BackupError.invalid("提醒时间") }
            guard !r.id.isEmpty, !r.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Day(rawValue: r.from) != nil, (0...3).contains(r.cat) else { throw BackupError.invalid("重复规则") }
        }
        guard document.notes.keys.allSatisfy({ Day(rawValue: $0) != nil }),
              document.repeatDone.keys.allSatisfy({ Day(rawValue: $0) != nil }) else { throw BackupError.invalid("日期") }
    }
}
