import XCTest
import SwiftUI
import PlannerCore
@testable import Planner

@MainActor final class WidgetLayoutTests: XCTestCase {
    func testPopulatedWidgetRendersBothSizesForVisualReview() throws {
        var document = PlannerDocument()
        let day = Day.today()
        document.tasks = (0..<8).map { index in
            PlannerTask(id: "layout-\(index)", text: ["准备明天的证件", "读书二十分钟", "散步并买好水果", "整理工作资料", "练习英语", "给家人打电话", "完成今天复习", "收拾房间"][index],
                        date: day.rawValue, done: index >= 6, order: Double(index), important: index == 0)
        }
        for compact in [true, false] {
            let content = PlannerWidgetContent(projection: WidgetProjection(document: document, day: day), message: nil, compact: compact)
                .frame(width: 306, height: compact ? 137 : 297, alignment: .topLeading)
                .padding(16).background(Color.white).environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content); renderer.scale = 3
            let rendered = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: rendered)
            attachment.name = compact ? "Widget-medium-populated" : "Widget-large-populated"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    func testCompletionFeedbackRendersBeforeConfirmedSnapshotForVisualReview() throws {
        var document = PlannerDocument()
        let day = Day.today()
        document.tasks = [PlannerTask(id: "feedback", text: "准备明天的证件和出行资料", date: day.rawValue, important: true)]
        let item = try XCTUnwrap(WidgetProjection(document: document, day: day).items.first)
        for compact in [true, false] {
            let content = VStack(spacing: 12) {
                PlannerWidgetTaskRow(item: item, isOn: false, compact: compact)
                // The same unconfirmed snapshot must already render visible feedback when Toggle turns on.
                PlannerWidgetTaskRow(item: item, isOn: true, compact: compact)
            }.frame(width: 306).padding(16).background(Color.white).environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content); renderer.scale = 3
            let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
            attachment.name = compact ? "Widget-medium-immediate-feedback" : "Widget-large-immediate-feedback"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }

}
