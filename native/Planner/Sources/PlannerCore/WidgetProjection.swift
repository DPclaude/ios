import Foundation

public struct WidgetProjection: Sendable {
    public let day: Day
    public let titles: [String]
    public let items: [TaskItem]
    public let total: Int
    public let completed: Int
    public init(document: PlannerDocument, day: Day, timeZone: TimeZone = .current) {
        var current = document
        current.rollover(today: day, timeZone: timeZone)
        let snapshot = current.snapshot(day: day, category: nil)
        self.day = day
        titles = snapshot.open.map(\.text)
        items = snapshot.open
        total = snapshot.totalCount
        completed = snapshot.completedCount
    }
}
