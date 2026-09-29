import SwiftUI
import PlannerCore

struct DailyNoteView: View {
    let model: PlannerViewModel
    let day: Day
    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.document.notes[day.rawValue, default: ""].isEmpty {
                Text("记下今天的想法……").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
            }
            TextEditor(text: Binding(get: { model.document.notes[day.rawValue, default: ""] },
                                     set: { model.updateNote($0, for: day) }))
                .frame(minHeight: 110).scrollContentBackground(.hidden)
                .accessibilityLabel("当天备忘").accessibilityIdentifier("dailyNote")
        }.disabled(!model.canEdit)
    }
}
