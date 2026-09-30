import Foundation
import SwiftUI
import Darwin

struct DiskIndex: Codable { var receipts: [Receipt] = []; var outgoing: [Outgoing] = [] }
final class DiskStore {
    let root: URL
    var index: DiskIndex
    init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        let path = self.root.appendingPathComponent("transfer-index.json")
        index = FileManager.default.fileExists(atPath: path.path) ? try JSONDecoder().decode(DiskIndex.self, from: Data(contentsOf: path)) : DiskIndex()
    }
    func save() throws {
        let dest = root.appendingPathComponent("transfer-index.json")
        try JSONEncoder().encode(index).write(to: dest, options: .atomic)
        let handle = try FileHandle(forWritingTo: dest); defer { try? handle.close() }; try handle.synchronize()
        let fd = open(root.path, O_RDONLY); if fd >= 0 { defer { close(fd) }; guard fsync(fd) == 0 else { throw TransferError(message: "无法保存接收目录") } }
    }
    func url(_ name: String) -> URL { root.appendingPathComponent(name) }
    func receipt(_ id: String, pin: String) -> Receipt? { index.receipts.first { $0.id == id && $0.peerPin == pin } }
    func commit(_ task: RemoteTask, pin: String, downloaded: URL?) throws {
        if receipt(task.id, pin: pin) != nil { return }
        let name = FilePolicy.safeName(task.name)
        // Stable private task path makes a crash between file move and index write recoverable.
        let filename = task.kind == "file" ? "\(String(pin.prefix(12)))-\(FilePolicy.safeName(task.id))-\(name)" : nil
        if let filename {
            let destination = url(filename)
            if !FileManager.default.fileExists(atPath: destination.path) {
                guard let downloaded else { throw TransferError(message: "接收文件不存在") }
                try FileManager.default.moveItem(at: downloaded, to: destination)
            }
            guard try FilePolicy.hashFile(destination) == task.hash else { throw TransferError(message: "文件校验失败，未发送保存回执") }
            let h = try FileHandle(forWritingTo: destination); defer { try? h.close() }; try h.synchronize()
        }
        index.receipts.append(Receipt(id: task.id, peerPin: pin, name: name, filename: filename, text: task.text, date: Date(), acknowledged: false))
        do { try save() } catch { index.receipts.removeLast(); throw error }
    }
}

@MainActor final class TransferStore: ObservableObject {
    @Published var peer: Peer?
    @Published var status = "未连接电脑"
    @Published var error: String?
    @Published var receipts: [Receipt] = []
    @Published var outgoing: [Outgoing] = []
    @Published var receiving: String?
    @Published var remoteTasks: [RemoteTask] = []
    @Published var connected = false
    @Published var autoReceive = UserDefaults.standard.object(forKey: "autoReceive") as? Bool ?? true
    @Published var phoneName = UserDefaults.standard.string(forKey: "phoneName") ?? "我的 iPhone"
    private var disk: DiskStore?
    private var transport: Transport?
    private var loop: Task<Void, Never>?
    private var pairing: Task<Void, Never>?
    private var generation = UUID()
    private let discovery = Discovery()
    init() {
        do { disk = try DiskStore(); peer = try CredentialStore.load(); refresh() }
        catch { self.error = "本地记录读取失败，原文件已保留：\(error.localizedDescription)" }
    }
    func refresh() { receipts = disk?.index.receipts.reversed() ?? []; outgoing = disk?.index.outgoing ?? [] }
    func foreground(_ active: Bool) {
        loop?.cancel(); loop = nil
        if !active { connected = false; status = "已暂停 · 回到 App 后继续"; return }
        guard let peer, disk != nil else { return }
        discovery.start(hostname: peer.hostname) { [weak self] host in
            guard let self, var p = self.peer, p.host != host else { return }
            p.host = host
            // Address is only a hint; the pinned certificate is checked on every connection.
            self.peer = p; try? CredentialStore.save(p); self.transport = Transport(p)
        }
        transport = Transport(peer)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do { try await self.cycle() }
                catch is CancellationError { return }
                catch { self.connected = false; self.status = "暂时无法连接"; self.error = error.localizedDescription
                    if let p = self.peer, !p.hostname.isEmpty, p.host != p.hostname { var alternate = p; alternate.host = p.hostname; self.transport = Transport(alternate) }
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    func pair(_ raw: String) {
        pairing?.cancel()
        pairing = Task {
            do {
                var p = try Peer.parse(raw)
                if let old = peer, old.pin == p.pin {
                    p.token = old.token; p.secret = ""; try CredentialStore.save(p); peer = p; foreground(true); return
                }
                guard peer == nil else { throw TransferError(message: "请先在设置中断开当前电脑，再连接另一台电脑") }
                status = "正在请求电脑确认"
                let t = Transport(p)
                let result = try await t.get([String: String].self, "/api/pair", method: "POST", json: ["secret": p.secret, "name": phoneName])
                guard let ticket = result["ticket"] else { throw TransferError(message: "配对响应不完整") }
                status = "请在电脑上核对：\(result["code"] ?? "") 并确认连接"
                for _ in 0..<120 {
                    try Task.checkCancellation()
                    let (data, code) = try await t.raw("/api/pair-result", method: "POST", json: ["ticket": ticket])
                    if code == 200 {
                        let answer = try JSONDecoder().decode([String: String].self, from: data)
                        guard let token = answer["recovery"], !token.isEmpty else { throw TransferError(message: "配对凭据缺失") }
                        p.token = token; p.secret = ""; try CredentialStore.save(p); peer = p; error = nil; foreground(true); return
                    }
                    try await Task.sleep(for: .seconds(1))
                }
                throw TransferError(message: "二维码已过期，请在电脑上重新生成")
            } catch { self.error = error.localizedDescription; status = "连接未完成" }
        }
    }
    func cycle() async throws {
        guard let t = transport, let disk else { return }
        let state = try await t.get(RemoteState.self, "/api/state")
        try Task.checkCancellation()
        remoteTasks = state.tasks; connected = true; status = "已连接 · 同一 Wi-Fi"; error = nil
        for item in disk.index.receipts where item.peerPin == t.peer.pin && !item.acknowledged {
            _ = try await t.raw("/api/ack", method: "POST", json: ["id": item.id])
            if let i = disk.index.receipts.firstIndex(where: { $0.id == item.id && $0.peerPin == item.peerPin }) { disk.index.receipts[i].acknowledged = true; try disk.save() }
        }
        if autoReceive {
            for item in state.tasks where item.direction == "out" && item.state != "已取消" && item.state != "正在准备" && item.state != "手机已收到" && item.state != "已保存到手机" && item.state != "完成" {
                try Task.checkCancellation()
                if disk.receipt(item.id, pin: t.peer.pin) != nil { continue }
                receiving = item.name; defer { receiving = nil }
                if item.kind == "text" { try disk.commit(item, pin: t.peer.pin, downloaded: nil) }
                else {
                    guard let hash = item.hash, hash.count == 64 else { continue }
                    let capacity = try disk.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                    guard capacity > item.size + (32 << 20) else { throw TransferError(message: "iPhone 存储空间不足，需额外保留 32 MB") }
                    let (temp, response) = try await t.session.download(for: t.request("/api/download/\(item.id)"))
                    defer { try? FileManager.default.removeItem(at: temp) }
                    try Transport.check((response as? HTTPURLResponse)?.statusCode ?? 0)
                    try Task.checkCancellation()
                    let attrs = try FileManager.default.attributesOfItem(atPath: temp.path)
                    guard (attrs[.size] as? NSNumber)?.int64Value == item.size else { throw TransferError(message: "文件大小不符，请重试") }
                    let calculated = try await Task.detached { try FilePolicy.hashFile(temp) }.value
                    guard calculated == hash else { throw TransferError(message: "文件校验失败，未发送保存回执") }
                    try disk.commit(item, pin: t.peer.pin, downloaded: temp)
                }
                refresh()
                _ = try await t.raw("/api/ack", method: "POST", json: ["id": item.id])
                if let i = disk.index.receipts.firstIndex(where: { $0.id == item.id && $0.peerPin == t.peer.pin }) { disk.index.receipts[i].acknowledged = true; try disk.save() }
            }
        }
        for item in disk.index.outgoing where item.peerPin == t.peer.pin && item.status != "已保存到电脑" {
            try Task.checkCancellation()
            if item.cancelled {
                if let id = item.remoteID { _ = try await t.raw("/api/cancel", method: "POST", json: ["id": id]) }
                continue
            }
            try await upload(item.id, transport: t)
        }
        refresh()
    }
    func importFile(_ url: URL) async {
        guard let disk, let peer else { error = "请先连接电脑"; return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let filename = ".send-\(UUID().uuidString)"
        let dest = disk.url(filename)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            let hash = try await Task.detached { try FilePolicy.hashFile(dest) }.value
            let size = (try FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? 0
            disk.index.outgoing.append(Outgoing(peerPin: peer.pin, name: FilePolicy.safeName(url.lastPathComponent), filename: filename, size: size, hash: hash))
            try disk.save(); refresh()
        } catch { try? FileManager.default.removeItem(at: dest); self.error = error.localizedDescription }
    }
    func upload(_ id: String, transport t: Transport) async throws {
        guard let disk, let index = disk.index.outgoing.firstIndex(where: { $0.id == id }) else { return }
        var item = disk.index.outgoing[index]
        var remote: RemoteTask
        if let remoteID = item.remoteID { remote = try await t.get(RemoteTask.self, "/api/task", query: ["id": remoteID]) }
        else {
            remote = try await t.get(RemoteTask.self, "/api/upload", method: "POST", json: ["name": item.name, "size": item.size, "hash": item.hash])
            item.remoteID = remote.id; disk.index.outgoing[index] = item; try disk.save()
        }
        if remote.state != "完成" {
            guard remote.state == "上传中", remote.offset >= 0, remote.offset <= item.size else { throw TransferError(message: "电脑任务已取消或不可继续，请取消后重发") }
            let h = try FileHandle(forReadingFrom: disk.url(item.filename)); defer { try? h.close() }
            try h.seek(toOffset: UInt64(remote.offset))
            while remote.offset < item.size {
                try Task.checkCancellation()
                if disk.index.outgoing[index].cancelled { return }
                guard let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty else { throw TransferError(message: "发送文件不完整") }
                var request = try t.request("/api/chunk", method: "PUT", body: chunk, query: ["id": remote.id, "offset": String(remote.offset), "hash": FilePolicy.digest(chunk)])
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                let (data, response) = try await t.session.data(for: request)
                try Transport.check((response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
                let result = try JSONDecoder().decode([String: Int64].self, from: data)
                guard result["offset"] == remote.offset + Int64(chunk.count) else { throw TransferError(message: "电脑接收进度不一致") }
                remote.offset += Int64(chunk.count)
                disk.index.outgoing[index].progress = item.size == 0 ? 1 : Double(remote.offset) / Double(item.size)
                disk.index.outgoing[index].status = "正在发送"; refresh()
            }
            disk.index.outgoing[index].status = "等待电脑保存确认"; refresh()
            remote = try await t.get(RemoteTask.self, "/api/finish", method: "POST", json: ["id": remote.id])
        }
        guard remote.state == "完成" else { throw TransferError(message: "电脑尚未确认保存") }
        disk.index.outgoing[index].status = "已保存到电脑"; disk.index.outgoing[index].progress = 1
        try disk.save(); try? FileManager.default.removeItem(at: disk.url(item.filename)); refresh()
    }
    func cancel(_ id: String) {
        guard let disk, let i = disk.index.outgoing.firstIndex(where: { $0.id == id }) else { return }
        disk.index.outgoing[i].cancelled = true; disk.index.outgoing[i].status = "已取消"
        do { try disk.save(); refresh() } catch { self.error = error.localizedDescription }
    }
    func sendText(_ text: String) async {
        guard let transport, !text.isEmpty else { return }
        do { let _: RemoteTask = try await transport.get(RemoteTask.self, "/api/text", method: "POST", json: ["text": text]); status = "文字已保存到电脑" }
        catch { self.error = error.localizedDescription }
    }
    func settingsChanged() { UserDefaults.standard.set(phoneName, forKey: "phoneName"); UserDefaults.standard.set(autoReceive, forKey: "autoReceive") }
    func renameComputer(_ name: String) { guard var p = peer else { return }; p.name = name; do { try CredentialStore.save(p); peer = p } catch { self.error = error.localizedDescription } }
    func disconnect() {
        loop?.cancel(); pairing?.cancel(); discovery.stop(); transport = nil; connected = false
        do { try CredentialStore.clear(); peer = nil; status = "未连接电脑" } catch { self.error = error.localizedDescription }
    }
    func fileURL(_ receipt: Receipt) -> URL? { receipt.filename.flatMap { disk?.url($0) } }
}
