import SwiftUI

struct ReminderSettingsSection: View {
    private var reminders: ReminderCoordinator { PlannerRuntime.shared.reminders }
    @Environment(\.openURL) private var openURL
    var body: some View {
        Section {
            LabeledContent("通知权限", value: reminders.authorized ? "已允许" : "未开启")
            Text(reminders.summary).font(.footnote).foregroundStyle(.secondary)
            if let error = reminders.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
            if !reminders.authorized {
                Button("允许通知") { Task { await reminders.requestAuthorization() } }
                Button("打开系统通知设置") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            }
            Button(reminders.busy ? "正在更新提醒…" : "重新检查提醒") { Task { await reminders.refresh() } }
                .disabled(reminders.busy)
        } header: { Text("通知提醒") } footer: {
            Text("在每条计划中设置提醒时间。每日提醒预排未来 30 天，最多保留最近 60 条；打开 App 或桌面完成计划时补充。专注模式、静音和通知摘要可能影响提醒显示及声音。")
        }
        .task {
            if !ProcessInfo.processInfo.arguments.contains("--uitesting") { await reminders.refresh() }
        }
    }
}
