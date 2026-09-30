import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers
import AVFoundation
import CoreTransferable

@main struct QuickTransferApp: App {
    @StateObject private var store = TransferStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            HomeView().environmentObject(store)
                .onChange(of: phase) { _, value in store.foreground(value == .active) }
                .onAppear { store.foreground(true) }
        }
    }
}
struct ImportedPhoto: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: url)
            return ImportedPhoto(url: url)
        }
    }
}
struct HomeView: View {
    @EnvironmentObject var store: TransferStore
    @State private var scan = false
    @State private var files = false
    @State private var settings = false
    @State private var textSheet = false
    @State private var text = ""
    @State private var photos: [PhotosPickerItem] = []
    @State private var imports: [URL] = []
    @State private var confirm = false
    var body: some View {
        TabView {
            NavigationStack {
                List {
                    Section {
                        HStack(spacing: 16) {
                            Image(systemName: "desktopcomputer").font(.system(size: 36)).foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(store.peer?.name ?? "连接我的电脑").font(.title3.bold())
                                Label(store.status, systemImage: store.connected ? "checkmark.circle.fill" : "circle").font(.footnote).foregroundStyle(store.connected ? .green : .secondary)
                            }
                        }.padding(.vertical, 12)
                        if store.peer == nil { Button("扫描电脑二维码", systemImage: "qrcode.viewfinder") { scan = true } }
                    }
                    if store.peer != nil {
                        Section {
                            HStack {
                                PhotosPicker(selection: $photos, maxSelectionCount: 30, matching: .images) { Label("照片", systemImage: "photo") }
                                Spacer()
                                Button("文件", systemImage: "doc") { files = true }
                                Spacer()
                                Button("文字", systemImage: "text.bubble") { textSheet = true }
                            }.buttonStyle(.borderless).padding(.vertical, 10)
                        } footer: { Text("请保持 App 在前台。收到的文件保存在 App 中，可预览、分享或存入相册。") }
                    }
                    if let error = store.error { Section { Text(error).foregroundStyle(.orange); Button("重试连接") { store.foreground(true) } } }
                    if let receiving = store.receiving { Section("正在接收") { HStack { ProgressView(); Text(receiving) }; Text("下载完成后校验并保存").font(.caption).foregroundStyle(.secondary) } }
                    if !store.outgoing.isEmpty {
                        Section("发送任务") {
                            ForEach(store.outgoing.reversed()) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack { Text(item.name).lineLimit(2); Spacer(); if !item.cancelled && item.status != "已保存到电脑" { Button("取消") { store.cancel(item.id) }.font(.caption) } }
                                    if !item.cancelled { ProgressView(value: item.progress) }
                                    Text(item.status).font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                    Section("最近收到") {
                        if store.receipts.isEmpty { Text("文件和文字收到后会出现在这里").foregroundStyle(.secondary) }
                        ForEach(Array(store.receipts.prefix(8))) { receipt in ReceiptRow(receipt: receipt) }
                    }
                }.navigationTitle("快捷互传")
                    .toolbar { Button("设置", systemImage: "gearshape") { settings = true } }
            }.tabItem { Label("互传", systemImage: "arrow.left.arrow.right") }
            NavigationStack {
                List(store.receipts) { ReceiptRow(receipt: $0) }.navigationTitle("收到的文件")
                    .overlay { if store.receipts.isEmpty { ContentUnavailableView("还没有收到文件", systemImage: "tray", description: Text("电脑发送的文件会保存在这里，重启后仍可查看。")) } }
            }.tabItem { Label("文件", systemImage: "folder") }
        }
        .sheet(isPresented: $scan) { ScannerView { result in scan = false; store.pair(result) } }
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(isPresented: $textSheet) {
            NavigationStack { TextEditor(text: $text).padding().navigationTitle("发送文字").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { textSheet = false } }
                ToolbarItem(placement: .confirmationAction) { Button("发送") { let value = text; textSheet = false; Task { await store.sendText(value) }; text = "" }.disabled(text.isEmpty || !store.connected) }
            } }
        }
        .fileImporter(isPresented: $files, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            do { imports = try result.get(); confirm = true } catch { store.error = error.localizedDescription }
        }
        .confirmationDialog("发送 \(imports.count) 个文件给\(store.peer?.name ?? "电脑")？", isPresented: $confirm, titleVisibility: .visible) {
            Button("确认发送") { let urls = imports; imports = []; Task { for url in urls { await store.importFile(url) } } }
            Button("取消", role: .cancel) { imports = [] }
        } message: { Text(imports.map(\.lastPathComponent).joined(separator: "\n")) }
        .onChange(of: photos) { _, items in Task {
            for item in items {
                do { if let photo = try await item.loadTransferable(type: ImportedPhoto.self) { await store.importFile(photo.url); try? FileManager.default.removeItem(at: photo.url) } }
                catch { store.error = error.localizedDescription }
            }
            photos = []
        } }
    }
}
struct ReceiptRow: View {
    @EnvironmentObject var store: TransferStore
    let receipt: Receipt
    @State private var share = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(receipt.name, systemImage: receipt.text == nil ? "doc.fill" : "text.bubble.fill").font(.headline)
            if let text = receipt.text { Text(text).lineLimit(4); Button("复制文字") { UIPasteboard.general.string = text } }
            if let url = store.fileURL(receipt) {
                HStack {
                    ShareLink(item: url) { Label("预览 / 分享", systemImage: "square.and.arrow.up") }
                    if ["jpg", "jpeg", "png", "heic", "gif"].contains(url.pathExtension.lowercased()) {
                        Button("存入相册") { Task {
                            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                            guard permission == .authorized || permission == .limited else { store.error = "相册写入权限未开启，文件仍保存在 App 中"; return }
                            do { try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) } }
                            catch { store.error = error.localizedDescription }
                        } }
                    }
                }.font(.caption).buttonStyle(.borderless)
            }
            Text("已保存到 App · " + receipt.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: TransferStore
    @Environment(\.dismiss) private var dismiss
    @State private var disconnect = false
    @State private var computerName = ""
    @State private var scan = false
    var body: some View {
        NavigationStack { Form {
            Section("设备") {
                TextField("手机名称（下次配对时使用）", text: $store.phoneName).onChange(of: store.phoneName) { _, _ in store.settingsChanged() }
                if store.peer != nil {
                    TextField("电脑名称", text: $computerName).onSubmit { store.renameComputer(computerName) }
                    Button("扫码更新电脑地址") { scan = true }
                    Button("断开此电脑", role: .destructive) { disconnect = true }
                }
            }
            Section { Toggle("自动接收已配对电脑的文件", isOn: $store.autoReceive).onChange(of: store.autoReceive) { _, _ in store.settingsChanged() } } footer: { Text("仅在 App 前台接收。锁屏或切到后台后可能暂停，回到 App 后重试。当前版本支持同一局域网。") }
            Section("关于") { Text("快捷互传 1.0.0"); Text("连接验证使用二维码中的电脑证书指纹。接收文件校验并保存后才发送完成回执。").font(.footnote) }
        }.navigationTitle("设置").toolbar { Button("完成") { store.renameComputer(computerName); dismiss() } }
            .onAppear { computerName = store.peer?.name ?? "" }
            .confirmationDialog("断开电脑？收到的文件将保留。电脑端可在设备管理中移除此手机的授权。", isPresented: $disconnect, titleVisibility: .visible) { Button("断开电脑", role: .destructive) { store.disconnect(); dismiss() } }
            .sheet(isPresented: $scan) { ScannerView { raw in scan = false; store.pair(raw) } }
        }
    }
}
struct ScannerView: UIViewControllerRepresentable {
    let scanned: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController { let c = ScannerController(); c.scanned = scanned; return c }
    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}
}
final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var scanned: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var finished = false
    private let label = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        label.text = "扫描电脑上的快捷互传二维码"; label.textColor = .white; label.textAlignment = .center; label.numberOfLines = 0
        view.addSubview(label)
        AVCaptureDevice.requestAccess(for: .video) { granted in DispatchQueue.main.async {
            guard granted else { self.label.text = "请在 iPhone 设置中允许快捷互传使用相机，然后重新打开扫描。"; return }
            self.configure()
        } }
    }
    private func configure() {
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else { label.text = "无法打开相机"; return }
        session.addInput(input); let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }; session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
        let p = AVCaptureVideoPreviewLayer(session: session); p.videoGravity = .resizeAspectFill; view.layer.insertSublayer(p, at: 0); preview = p; p.frame = view.bounds
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds; label.frame = CGRect(x: 24, y: view.safeAreaInsets.top + 30, width: view.bounds.width - 48, height: 90) }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); DispatchQueue.global().async { self.session.stopRunning() } }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !finished, let raw = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        guard (try? Peer.parse(raw)) != nil else { label.text = "请扫描快捷互传电脑端的配对二维码"; return }
        finished = true; scanned?(raw)
    }
}
