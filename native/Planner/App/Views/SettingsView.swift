import SwiftUI
import UniformTypeIdentifiers
import PlannerCore

struct SettingsView: View {
    let model: PlannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exporting = false
    @State private var export: BackupDocument?
    @State private var preview: ImportPreview?
    @State private var error: String?
    @State private var recovering = false
    @State private var working = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { prepareExport() } label: { Label("导出备份", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("exportBackup").disabled(!model.isLoaded)
                    Button { importing = true } label: { Label("导入旧版备份", systemImage: "square.and.arrow.down") }.disabled(!model.canEdit)
                    Button("恢复导入前的副本", systemImage: "clock.arrow.circlepath") { recovering = true }
                } header: { Text("你的数据") } footer: {
                    Text("计划保存在本机。请定期将 JSON 备份存到「文件」或其他设备；卸载 App 会删除本机数据和恢复副本。")
                }
                UpdateSection()
                Section("桌面小组件") {
                    Text("长按手机桌面 → 编辑 → 添加小组件 → 搜索「计划本」→ 选择大号。点组件即可进入全屏划切。")
                    Text("可以把大组件和中组件放在同一页。组件更新时间由 iOS 调度，刚保存后可能需要片刻显示。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let message = model.widgetMessage { Text(message).font(.footnote).foregroundStyle(.orange) }
                    NavigationLink("预览大组件") {
                        PlannerWidgetContent(projection: WidgetProjection(document: model.document, day: .today()), message: nil, compact: false)
                            .padding(20).frame(height: 340)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
                            .padding().navigationTitle("组件预览")
                    }
                }
                Section("安装与续签") {
                    Text("免费签名需定期刷新，请在 SideStore 中确认计划本和 SideStore 的剩余有效期。")
                    Link("Windows 安装与自动续签说明", destination: URL(string: "https://github.com/DPclaude/ios/blob/codex/native-ios/docs/ios-install.md")!)
                    Text("首次安装、Apple 登录和设备信任需要你在自己的设备上完成。") .font(.footnote).foregroundStyle(.secondary)
                }
                Section("关于") {
                    LabeledContent("计划本", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                    Text("SwiftUI 原生界面 · 离线使用").foregroundStyle(.secondary)
                    Link("查看源代码", destination: URL(string: "https://github.com/DPclaude/ios/tree/codex/native-ios/native/Planner")!)
                }
            }
            .disabled(working || model.isBusy)
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .overlay { if working || model.isBusy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    working = true
                    Task { defer { working = false }; do { preview = try await model.prepareImport(url: url) } catch { self.error = error.localizedDescription } }
                case .failure(let error): self.error = error.localizedDescription
                }
            }
            .fileExporter(isPresented: $exporting, document: export, contentType: .json, defaultFilename: "计划本备份-\(model.selectedDay.rawValue)") { result in
                if case .failure(let failure) = result { error = failure.localizedDescription }
            }
            .sheet(item: $preview) { candidate in importPreview(candidate) }
            .alert("未能完成操作", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .confirmationDialog("恢复导入前的数据？", isPresented: $recovering, titleVisibility: .visible) {
                Button("恢复副本", role: .destructive) {
                    working = true
                    Task { defer { working = false }; do { try await model.recoverPreviousImport() } catch { self.error = error.localizedDescription } }
                }
            } message: { Text("当前数据将被替换，导入后新增或修改的内容不会保留。建议先导出当前备份。") }
        }
    }
    private func prepareExport() {
        working = true
        Task {
            defer { working = false }
            do { export = BackupDocument(data: try await model.exportData()); exporting = true }
            catch { self.error = error.localizedDescription }
        }
    }
    private func importPreview(_ candidate: ImportPreview) -> some View {
        NavigationStack {
            Form {
                Section("备份内容") {
                    LabeledContent("普通计划", value: "\(candidate.document.tasks.count)")
                    LabeledContent("每日规则", value: "\(candidate.document.repeats.count)")
                    LabeledContent("备忘天数", value: "\(candidate.document.notes.count)")
                }
                Section {
                    Text("导入会覆盖当前全部计划和备忘。继续后会先保存当前数据的恢复副本；任何保存失败都会中止导入。")
                    Button("确认覆盖并导入", role: .destructive) {
                        working = true
                        Task {
                            defer { working = false; preview = nil }
                            do { try await model.confirmImport(candidate) } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(working)
                }
            }.navigationTitle("确认导入").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { preview = nil }.disabled(working) } }
                .interactiveDismissDisabled(working)
        }
    }
}
