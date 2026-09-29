import SwiftUI
import PlannerCore

struct UpdateSection: View {
    @Environment(\.openURL) private var openURL
    @State private var checking = false
    @State private var message: String?
    @State private var available: UpdateManifest?
    private var installed: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }
    var body: some View {
        Section {
            Button { Task { await check() } } label: {
                HStack {
                    Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if checking { ProgressView() }
                }
            }.disabled(checking).accessibilityIdentifier("checkUpdate")
            if let available {
                Text("新版本 \(available.version)").font(.headline)
                Text(available.notes).font(.footnote)
                Button("通过 SideStore 更新", systemImage: "arrow.down.app") { launch(available.sideStoreURL) }
            }
            Button("添加计划本更新源", systemImage: "plus.circle") { launch(UpdateManifest.addSourceURL) }
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        } header: { Text("软件更新") } footer: {
            Text("首次添加更新源后，可直接在 SideStore 点更新，无需下载 ZIP。请保持 Wi-Fi 和 LocalDevVPN 连接，使用原 Apple 账户覆盖安装。续签只延长有效期，不会更新版本。")
        }
    }
    @MainActor private func launch(_ url: URL) {
        openURL(url) { accepted in
            if !accepted { message = "未能打开 SideStore。请确认已安装 SideStore，也可以在其中手动添加更新源。" }
        }
    }
    @MainActor private func check() async {
        guard !checking else { return }
        checking = true; available = nil; message = nil
        defer { checking = false }
        do {
            var request = URLRequest(url: UpdateManifest.endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                message = "暂时无法获取更新信息。请稍后重试，或在 SideStore 查看更新。"; return
            }
            let release = try UpdateManifest.validated(data: data)
            if release.isNewer(than: installed) { available = release }
            else { message = "当前已是最新版本（\(installed)）。" }
        } catch { message = "检查更新失败：\(error.localizedDescription)" }
    }
}
