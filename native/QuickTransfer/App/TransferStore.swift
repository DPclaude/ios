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
    func receipt(_ id: String, pin: String) -> Receipt? { index.receipts.first { $0.id == id && $0.peerPin == pin && $0.needsRecovery != true } }
    func receiptIsValid(_ receipt: Receipt, for task: RemoteTask) -> Bool {
        guard receipt.id == task.id, task.direction == "out" else { return false }
        if task.kind == "text" { return receipt.filename == nil && receipt.text == task.text && receipt.text != nil }
        guard task.kind == "file", let filename = receipt.filename,
              filename == receiptFilename(task, pin: receipt.peerPin), let hash = task.hash else { return false }
        let file = url(filename)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.size] as? NSNumber)?.int64Value == task.size else { return false }
        return (try? FilePolicy.hashFile(file)) == hash
    }
    func markForRecovery(_ receipt: Receipt) throws {
        guard let i = index.receipts.firstIndex(where: { $0.id == receipt.id && $0.peerPin == receipt.peerPin }) else { return }
        let previous = index.receipts[i]
        index.receipts[i].needsRecovery = true; index.receipts[i].acknowledged = false
        do { try save() } catch { index.receipts[i] = previous; throw error }
    }
    func stopReceiptRetry(_ receipt: Receipt, reason: String) throws {
        guard let i = index.receipts.firstIndex(where: { $0.id == receipt.id && $0.peerPin == receipt.peerPin }) else { return }
        let previous = index.receipts[i]
        index.receipts[i].retryStoppedReason = reason
        do { try save() } catch { index.receipts[i] = previous; throw error }
    }
    func finishCancellation(_ id: String) throws {
        guard let i = index.outgoing.firstIndex(where: { $0.id == id }) else { return }
        let previous = index.outgoing[i]
        index.outgoing[i].cancelConfirmed = true; index.outgoing[i].status = "已取消"
        do { try save() } catch { index.outgoing[i] = previous; throw error }
    }
    func outgoingFailed(_ id: String, error: Error) throws {
        guard let i = index.outgoing.firstIndex(where: { $0.id == id }) else { return }
        let previous = index.outgoing[i]
        index.outgoing[i].status = "未完成：\(error.localizedDescription)"
        if QueuePolicy.isTerminal(error) { index.outgoing[i].retryStoppedReason = error.localizedDescription }
        do { try save() } catch { index.outgoing[i] = previous; throw error }
    }
    func receiptFilename(_ task: RemoteTask, pin: String) -> String { "\(String(pin.prefix(12)))-\(FilePolicy.safeName(task.id))-\(FilePolicy.safeName(task.name))" }
    // This method touches only deterministic task-owned file paths; it can run off the main actor.
    func prepareFile(_ task: RemoteTask, pin: String, downloaded: URL?) throws {
        let destination = url(receiptFilename(task, pin: pin))
        let exists = FileManager.default.fileExists(atPath: destination.path)
        if exists, try FilePolicy.hashFile(destination) == task.hash { return }
        guard let downloaded, try FilePolicy.hashFile(downloaded) == task.hash else { throw TransferError(message: "文件校验失败，未发送保存回执") }
        let h = try FileHandle(forWritingTo: downloaded); defer { try? h.close() }; try h.synchronize()
        // POSIX rename atomically replaces only this transfer's private destination after validation.
        guard rename(downloaded.path, destination.path) == 0 else { throw TransferError(message: "无法保存收到的文件（\(errno)）") }
    }
    func commit(_ task: RemoteTask, pin: String, downloaded: URL?, filePrepared: Bool = false) throws {
        if receipt(task.id, pin: pin) != nil { return }
        let name = FilePolicy.safeName(task.name)
        // Stable private task path makes a crash between file move and index write recoverable.
        let filename = task.kind == "file" ? receiptFilename(task, pin: pin) : nil
        if filename != nil && !filePrepared { try prepareFile(task, pin: pin, downloaded: downloaded) }
        let previous = index.receipts
        index.receipts.removeAll { $0.id == task.id && $0.peerPin == pin }
        index.receipts.append(Receipt(id: task.id, peerPin: pin, name: name, filename: filename, text: task.text, date: Date(), acknowledged: false))
        do { try save() } catch { index.receipts = previous; throw error }
    }
}

@MainActor final class TransferStore: ObservableObject {
    @Published var peer: Peer?
    @Published var status = "未连接电脑"
    @Published var error: String?
    @Published var receipts: [Receipt] = []
    @Published var outgoing: [Outgoing] = []
    @Published var receiving: String?
    @Published var receiveProgress: Double = 0
    private var receiveID: String?
    @Published var remoteTasks: [RemoteTask] = []
    @Published var connected = false
    @Published var autoReceive = UserDefaults.standard.object(forKey: "autoReceive") as? Bool ?? true
    @Published var phoneName = UserDefaults.standard.string(forKey: "phoneName") ?? "我的 iPhone"
    private var disk: DiskStore?
    private var transport: Transport?
    private var loop: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var pairing: Task<Void, Never>?
    private let discovery = Discovery()
    init() {
        do { disk = try DiskStore(); peer = try CredentialStore.load(); refresh() }
        catch { self.error = "本地记录读取失败，原文件已保留：\(error.localizedDescription)" }
    }
    func refresh() { receipts = Array((disk?.index.receipts ?? []).filter { $0.needsRecovery != true }.reversed()); outgoing = disk?.index.outgoing ?? [] }
    func foreground(_ active: Bool) {
        loop?.cancel(); loop = nil; heartbeat?.cancel(); heartbeat = nil
        if !active { connected = false; status = "已暂停 · 回到 App 后继续"; return }
        guard let peer, disk != nil else { return }
        discovery.start(hostname: peer.hostname) { [weak self] host in
            guard let self, var p = self.peer, p.host != host else { return }
            p.host = host
            // Address is only a hint; the pinned certificate is checked on every connection.
            self.peer = p; try? CredentialStore.save(p); self.transport = Transport(p)
        }
        transport = Transport(peer)
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                guard let self, let t = self.transport else { return }
                do {
                    _ = try await t.raw("/api/touch", method: "POST", json: [:])
                    try Task.checkCancellation()
                } catch {
                    if Task.isCancelled { return }
                    self.connected = false; self.status = "暂时无法连接"; self.error = error.localizedDescription
                }
            }
        }
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
                var replacingRevokedCredential = false
                if let old = peer, old.pin == p.pin {
                    var candidate = p; candidate.token = old.token
                    do {
                        let _: RemoteState = try await Transport(candidate).get(RemoteState.self, "/api/state")
                        candidate.secret = ""; try CredentialStore.save(candidate); peer = candidate; foreground(true); return
                    } catch let failure as TransferError where failure.statusCode == 401 {
                        // Only an authenticated server's explicit revocation permits a new identity.
                        // Network/TLS errors preserve the old credential and do not create duplicates.
                        replacingRevokedCredential = true
                        loop?.cancel(); heartbeat?.cancel(); discovery.stop(); connected = false
                    }
                }
                guard peer == nil || replacingRevokedCredential else { throw TransferError(message: "请先在设置中断开当前电脑，再连接另一台电脑") }
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
        let pendingReceipts = disk.index.receipts.filter { $0.peerPin == t.peer.pin && !$0.acknowledged && $0.retryStoppedReason == nil }
        try await QueuePolicy.run(pendingReceipts, operation: { item in
            guard let task = state.tasks.first(where: { $0.id == item.id }), task.state != "已取消" else {
                try disk.stopReceiptRetry(item, reason: "电脑任务已过期或已取消；本地文件保留"); return
            }
            let valid = await Task.detached { disk.receiptIsValid(item, for: task) }.value
            try Task.checkCancellation()
            guard valid else { try disk.markForRecovery(item); self.refresh(); return }
            _ = try await t.raw("/api/ack", method: "POST", json: ["id": item.id])
            if let i = disk.index.receipts.firstIndex(where: { $0.id == item.id && $0.peerPin == item.peerPin }) { disk.index.receipts[i].acknowledged = true; disk.index.receipts[i].needsRecovery = nil; try disk.save() }
        }, failed: { item, error in
            if QueuePolicy.isTerminal(error) { try disk.stopReceiptRetry(item, reason: error.localizedDescription) }
            self.error = "\(item.name)：\(error.localizedDescription)"
        })
        if autoReceive {
            let recoveryIDs = Set(disk.index.receipts.filter { $0.peerPin == t.peer.pin && $0.needsRecovery == true && $0.retryStoppedReason == nil }.map(\.id))
            for item in state.tasks where item.direction == "out" && item.state != "已取消" && item.state != "正在准备" && (recoveryIDs.contains(item.id) || (item.state != "手机已收到" && item.state != "已保存到手机" && item.state != "完成")) {
                do {
                try Task.checkCancellation()
                if disk.index.receipts.contains(where: { $0.id == item.id && $0.peerPin == t.peer.pin && $0.retryStoppedReason != nil }) { continue }
                if disk.receipt(item.id, pin: t.peer.pin) != nil { continue }
                receiving = item.name; receiveID = item.id; receiveProgress = 0
                defer { receiving = nil; receiveID = nil; t.delegate.progress = nil }
                if item.kind == "text" { try disk.commit(item, pin: t.peer.pin, downloaded: nil) }
                else {
                    guard let hash = item.hash, hash.count == 64 else { continue }
                    let capacity = try disk.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                    guard capacity > item.size + (32 << 20) else { throw TransferError(message: "iPhone 存储空间不足，需额外保留 32 MB") }
                    t.delegate.progress = { [weak self] value in Task { @MainActor in self?.receiveProgress = value } }
                    let (temp, response) = try await t.session.download(for: t.request("/api/download/\(item.id)"))
                    defer { try? FileManager.default.removeItem(at: temp) }
                    try Transport.check((response as? HTTPURLResponse)?.statusCode ?? 0)
                    try Task.checkCancellation()
                    let attrs = try FileManager.default.attributesOfItem(atPath: temp.path)
                    guard (attrs[.size] as? NSNumber)?.int64Value == item.size else { throw TransferError(message: "文件大小不符，请重试") }
                    try await Task.detached { try disk.prepareFile(item, pin: t.peer.pin, downloaded: temp) }.value
                    try Task.checkCancellation()
                    try disk.commit(item, pin: t.peer.pin, downloaded: nil, filePrepared: true)
                }
                refresh()
                guard let saved = disk.receipt(item.id, pin: t.peer.pin) else { continue }
                let valid = await Task.detached { disk.receiptIsValid(saved, for: item) }.value
                try Task.checkCancellation()
                guard valid else { try disk.markForRecovery(saved); refresh(); continue }
                _ = try await t.raw("/api/ack", method: "POST", json: ["id": item.id])
                if let i = disk.index.receipts.firstIndex(where: { $0.id == item.id && $0.peerPin == t.peer.pin }) { disk.index.receipts[i].acknowledged = true; disk.index.receipts[i].needsRecovery = nil; try disk.save() }
                } catch {
                    if QueuePolicy.isGlobal(error) { throw error }
                    if QueuePolicy.isTerminal(error), let receipt = disk.receipt(item.id, pin: t.peer.pin) { try disk.stopReceiptRetry(receipt, reason: error.localizedDescription) }
                    self.error = "\(item.name)：\(error.localizedDescription)"
                }
            }
        }
        let pendingSends = disk.index.outgoing.filter { $0.peerPin == t.peer.pin && $0.status != "已保存到电脑" && $0.cancelConfirmed != true && $0.retryStoppedReason == nil }
        try await QueuePolicy.run(pendingSends, operation: { item in
            if item.cancelled {
                if let id = item.remoteID { _ = try await t.raw("/api/cancel", method: "POST", json: ["id": id]) }
                try disk.finishCancellation(item.id); return
            }
            try await self.upload(item.id, transport: t)
        }, failed: { item, error in
            try disk.outgoingFailed(item.id, error: error)
            self.error = "\(item.name)：\(error.localizedDescription)"
        })
        refresh()
    }
    func importFile(_ url: URL) async {
        guard let disk, let peer else { error = "请先连接电脑"; return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let filename = ".send-\(UUID().uuidString)"
        let dest = disk.url(filename)
        do {
            let hash = try await Task.detached {
                try FileManager.default.copyItem(at: url, to: dest)
                return try FilePolicy.hashFile(dest)
            }.value
            let size = (try FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? 0
            disk.index.outgoing.append(Outgoing(peerPin: peer.pin, name: FilePolicy.safeName(url.lastPathComponent), filename: filename, size: size, hash: hash))
            do { try disk.save() } catch { disk.index.outgoing.removeLast(); throw error }
            refresh()
        } catch { try? FileManager.default.removeItem(at: dest); self.error = error.localizedDescription }
    }
    func upload(_ id: String, transport t: Transport) async throws {
        guard let disk, let index = disk.index.outgoing.firstIndex(where: { $0.id == id }) else { return }
        var item = disk.index.outgoing[index]
        var remote: RemoteTask
        if let remoteID = item.remoteID { remote = try await t.get(RemoteTask.self, "/api/task", query: ["id": remoteID]) }
        else {
            remote = try await t.get(RemoteTask.self, "/api/upload", method: "POST", json: ["name": item.name, "size": item.size, "hash": item.hash])
            item.remoteID = remote.id; disk.index.outgoing[index].remoteID = remote.id; try disk.save()
        }
        if disk.index.outgoing[index].cancelled { return }
        if remote.state != "完成" {
            guard remote.state == "上传中", remote.offset >= 0, remote.offset <= item.size else { throw TransferError(message: "电脑任务已取消或不可继续，请取消后重发", terminalTask: true) }
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
            try Task.checkCancellation()
            if disk.index.outgoing[index].cancelled { return }
            remote = try await t.get(RemoteTask.self, "/api/finish", method: "POST", json: ["id": remote.id])
        }
        guard remote.state == "完成" else { throw TransferError(message: "电脑尚未确认保存") }
        disk.index.outgoing[index].status = "已保存到电脑"; disk.index.outgoing[index].progress = 1
        try disk.save(); try? FileManager.default.removeItem(at: disk.url(item.filename)); refresh()
    }
    func cancel(_ id: String) {
        guard let disk, let i = disk.index.outgoing.firstIndex(where: { $0.id == id }) else { return }
        disk.index.outgoing[i].cancelled = true; disk.index.outgoing[i].status = "已取消"
        do { try disk.save(); try? FileManager.default.removeItem(at: disk.url(disk.index.outgoing[i].filename)); refresh() } catch { self.error = error.localizedDescription }
    }
    func cancelReceiving() {
        guard let id = receiveID, let t = transport else { return }
        loop?.cancel()
        Task {
            do { _ = try await t.raw("/api/cancel", method: "POST", json: ["id": id]) }
            catch { self.error = "取消尚未送达电脑：\(error.localizedDescription)" }
            foreground(true)
        }
    }
    func sendText(_ text: String) async {
        guard let transport, !text.isEmpty else { return }
        do { let _: RemoteTask = try await transport.get(RemoteTask.self, "/api/text", method: "POST", json: ["text": text]); status = "文字已保存到电脑" }
        catch { self.error = error.localizedDescription }
    }
    func settingsChanged() { UserDefaults.standard.set(phoneName, forKey: "phoneName"); UserDefaults.standard.set(autoReceive, forKey: "autoReceive") }
    func renameComputer(_ name: String) { guard var p = peer else { return }; p.name = name; do { try CredentialStore.save(p); peer = p } catch { self.error = error.localizedDescription } }
    func disconnect() {
        loop?.cancel(); heartbeat?.cancel(); pairing?.cancel(); discovery.stop(); transport = nil; connected = false
        do { try CredentialStore.clear(); peer = nil; status = "未连接电脑" } catch { self.error = error.localizedDescription }
    }
    func fileURL(_ receipt: Receipt) -> URL? { receipt.filename.flatMap { disk?.url($0) } }
}
