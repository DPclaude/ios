import Foundation
import WidgetKit
import PlannerCore
import PlannerStore

enum PlannerWidgetBridge {
    static let kind = "PlannerToday"
    static let deepLink = URL(string: "planner://slice")!
    static var archiveURL: URL? {
        // SideStore rewrites group identifiers and publishes the signed list in ALTAppGroups.
        let signed = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        let groups = signed.filter { $0.contains("com.dpclaude.planner") } + ["group.com.dpclaude.planner"]
        for group in groups {
            if let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                return directory.appendingPathComponent("planner-widget.json")
            }
        }
        return nil
    }
    static func publish(_ document: PlannerDocument) -> String? {
        guard let file = archiveURL else { return "组件共享空间不可用。请在 SideStore 安装时保留小组件扩展，再重新打开计划本。" }
        do {
            try WidgetArchive.write(document: document, to: file)
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
            return nil
        } catch { return "组件同步未成功：\(error.localizedDescription)" }
    }
}
