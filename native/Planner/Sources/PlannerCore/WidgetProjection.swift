import Foundation

public struct WidgetProjection: Sendable {
    public let day: Day
    public let titles: [String]
    public let items: [TaskItem]
    public let completedItems: [TaskItem]
    public let total: Int
    public let completed: Int
    private let lastCompleted: TaskReference?
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
        lastCompleted = current.lastCompleted
    }
    public func visibleItems(limit: Int) -> [TaskItem] {
        guard limit > 0 else { return [] }
        // Reserve room below open plans for a completed plan on both supported widget sizes.
        let openLimit = completedItems.isEmpty ? limit : max(0, limit - 1)
        let open = Array(items.prefix(openLimit))
        let recent = completedItems.enumerated().sorted {
            if ($0.element.reference == lastCompleted) != ($1.element.reference == lastCompleted) {
                return $0.element.reference == lastCompleted
            }
            return $0.element.doneAt == $1.element.doneAt ? $0.offset < $1.offset : $0.element.doneAt > $1.element.doneAt
        }.map(\.element)
        return open + recent.prefix(limit - open.count)
    }
}
