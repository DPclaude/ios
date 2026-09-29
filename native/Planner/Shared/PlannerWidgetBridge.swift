import Foundation
import WidgetKit
import PlannerCore
import PlannerStore

enum PlannerWidgetBridge {
    static let kind = "PlannerToday"
    static let deepLink = URL(string: "planner://add")!
    private static var errorURL: URL? { archiveURL?.deletingLastPathComponent().appendingPathComponent("widget-interaction-error.txt") }
    static var interactionError: String? { errorURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } }
    static func setInteractionError(_ message: String?) {
        guard let file = errorURL else { return }
        if let message { try? Data(message.utf8).write(to: file, options: .atomic) }
        else if FileManager.default.fileExists(atPath: file.path) { try? FileManager.default.removeItem(at: file) }
    }
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
    static func publish(_ snapshot: StoreSnapshot, reload: Bool = true) -> String? {
        guard let file = archiveURL else { return "组件共享空间不可用。请在 SideStore 安装时保留小组件扩展，再重新打开计划本。" }
        do {
            try WidgetArchive.write(document: snapshot.document, generation: snapshot.generation, to: file)
            setInteractionError(nil)
            if reload { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
            return nil
        } catch { return "组件同步未成功：\(error.localizedDescription)" }
    }
}
