import SwiftUI
import PlannerCore

struct WeekStrip: View {
    let day: Day
    let select: (Day) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var days: [Day] {
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: day.date())
        let monday = day.adding(days: -((weekday + 5) % 7))
        return (0..<7).map { monday.adding(days: $0) }
    }
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { value in
                    Button { select(value) } label: {
                        VStack(spacing: 9) {
                            Text(value.date(), format: .dateTime.weekday(.narrow)).font(.caption)
                            Text(value.date(), format: .dateTime.day()).font(.headline)
                        }
                        .frame(minWidth: typeSize.isAccessibilitySize ? 64 : 40, minHeight: 62)
                        .foregroundStyle(value == day ? Color.white : .primary)
                        .background(value == day ? Color.orange : .clear, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(value.date().formatted(date: .complete, time: .omitted))
                        .accessibilityAddTraits(value == day ? .isSelected : [])
                }
            }.frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
    }
}
