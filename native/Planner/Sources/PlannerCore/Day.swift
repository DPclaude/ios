import Foundation

public struct Day: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    public let rawValue: String
    public init?(rawValue: String) {
        let bytes = Array(rawValue.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }) else { return nil }
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...9999).contains(parts[0]) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == parts[0],
              calendar.component(.month, from: date) == parts[1],
              calendar.component(.day, from: date) == parts[2] else { return nil }
        self.rawValue = rawValue
    }
    public static func today(now: Date = Date(), timeZone: TimeZone = .current) -> Day {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return Day(rawValue: String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!))!
    }
    public func date(timeZone: TimeZone = .current) -> Date {
        let p = rawValue.split(separator: "-").map { Int($0)! }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
    }
    public func adding(days: Int, timeZone: TimeZone = .current) -> Day {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let shifted = calendar.date(byAdding: .day, value: days, to: date(timeZone: timeZone))!
        return Self.today(now: shifted, timeZone: timeZone)
    }
    public static func < (lhs: Day, rhs: Day) -> Bool { lhs.rawValue < rhs.rawValue }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let day = Day(rawValue: value) else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "无效日期") }
        self = day
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer(); try container.encode(rawValue)
    }
}
