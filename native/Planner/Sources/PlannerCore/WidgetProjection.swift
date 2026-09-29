import Foundation

public struct WidgetProjection: Sendable {
    public let day: Day
    public let titles: [String]
    public let items: [TaskItem]
    public let completedItems: [TaskItem]
    public let total: Int
    public let completed: Int
    public init(document: PlannerDocument, day: Day, timeZone: TimeZone = .current) {
        var current = document
        current.rollover(today: day, timeZone: timeZone)
        let snapshot = current.snapshot(day: day, category: nil)
        self.day = day
        titles = snapshot.open.map(\.text)
        items = snapshot.open
        completedItems = snapshot.completed
        total = snapshot.totalCount
        completed = snapshot.completedCount
    }
    public func visibleItems(limit: Int) -> [TaskItem] {
        guard limit > 0 else { return [] }
        // Reserve room below open plans for a completed plan on both supported widget sizes.
        let openLimit = completedItems.isEmpty ? limit : max(0, limit - 1)
        let open = Array(items.prefix(openLimit))
        return open + completedItems.prefix(limit - open.count)
    }
}
