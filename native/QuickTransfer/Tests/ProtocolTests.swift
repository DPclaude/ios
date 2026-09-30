import XCTest
@testable import QuickTransfer

final class ProtocolTests: XCTestCase {
    func testPairRequiresExactFingerprint() throws {
        XCTAssertThrowsError(try Peer.parse("https://example.com/pair"))
        XCTAssertThrowsError(try Peer.parse("quicktransfer://pair?host=127.0.0.1&pin=bad&secret=a"))
        let p = try Peer.parse("quicktransfer://pair?host=192.168.1.4&port=39278&pin=" + String(repeating: "a", count: 64) + "&secret=123&name=PC&hostname=pc.local")
        XCTAssertEqual(p.port, 39278); XCTAssertEqual(p.hostname, "pc.local")
    }
    func testSafeNamesCannotTraverseDirectory() {
        for name in ["../../secret", "..", ".", "a/b", "a\\b", "", "中文.txt"] {
            let safe = FilePolicy.safeName(name)
            XCTAssertFalse(safe.contains("/")); XCTAssertFalse(safe.contains("\\")); XCTAssertFalse(safe == "..")
        }
        XCTAssertEqual(FilePolicy.safeName("中文.txt"), "中文.txt")
    }
    func testStreamingHashEmptyAndChunkBoundaries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for size in [0, 1, 1048576, 1048579] {
            let data = Data(repeating: 51, count: size); try data.write(to: root)
            XCTAssertEqual(try FilePolicy.hashFile(root), FilePolicy.digest(data))
        }
    }
    func testDurableReceiptSurvivesRestartAndIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DiskStore(root: root)
        let task = RemoteTask(id: "one", direction: "out", kind: "text", name: "文字", text: "你好", size: 6, offset: 0, hash: nil, state: "等待")
        try store.commit(task, pin: "pin", downloaded: nil)
        try store.commit(task, pin: "pin", downloaded: nil)
        let reopened = try DiskStore(root: root)
        XCTAssertEqual(reopened.index.receipts.count, 1)
        XCTAssertEqual(reopened.index.receipts[0].text, "你好")
        XCTAssertFalse(reopened.index.receipts[0].acknowledged)
    }
    func testCorruptFileNeverCreatesReceipt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DiskStore(root: root), file = root.appendingPathComponent("temp")
        try Data("wrong".utf8).write(to: file)
        let task = RemoteTask(id: "two", direction: "out", kind: "file", name: "report.txt", text: nil, size: 5, offset: 0, hash: FilePolicy.digest(Data("right".utf8)), state: "等待")
        XCTAssertThrowsError(try store.commit(task, pin: "pin", downloaded: file))
        XCTAssertTrue(store.index.receipts.isEmpty)
    }
    func testCorruptOrphanIsReplacedOnlyWithVerifiedNewDownload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DiskStore(root: root)
        let task = RemoteTask(id: "orphan", direction: "out", kind: "file", name: "report.txt", text: nil, size: 5, offset: 0, hash: FilePolicy.digest(Data("right".utf8)), state: "等待")
        let destination = store.url(store.receiptFilename(task, pin: "pin"))
        try Data("wrong".utf8).write(to: destination)
        let downloaded = root.appendingPathComponent("new")
        try Data("right".utf8).write(to: downloaded)
        try store.commit(task, pin: "pin", downloaded: downloaded)
        XCTAssertEqual(try Data(contentsOf: destination), Data("right".utf8))
        XCTAssertEqual(try DiskStore(root: root).index.receipts.count, 1)
    }
    func testPendingAckRejectsDeletedOrEditedFileAndRecoversAfterRestart() throws {
        for deleted in [true, false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try DiskStore(root: root)
            let bytes = Data("right".utf8)
            let task = RemoteTask(id: "pending", direction: "out", kind: "file", name: "report.txt", text: nil, size: 5, offset: 0, hash: FilePolicy.digest(bytes), state: "等待手机下载")
            let downloaded = root.appendingPathComponent("download")
            try bytes.write(to: downloaded)
            try store.commit(task, pin: "pin", downloaded: downloaded)
            let receipt = try XCTUnwrap(store.receipt(task.id, pin: "pin"))
            XCTAssertTrue(store.receiptIsValid(receipt, for: task))
            let finalFile = store.url(try XCTUnwrap(receipt.filename))
            if deleted { try FileManager.default.removeItem(at: finalFile) }
            else { try Data("wrong".utf8).write(to: finalFile) }
            XCTAssertFalse(store.receiptIsValid(receipt, for: task), "Missing or same-size edited file must never authorize ACK")
            try store.markForRecovery(receipt)
            let reopened = try DiskStore(root: root)
            XCTAssertNil(reopened.receipt(task.id, pin: "pin"), "Invalid index entry must not block a fresh download")
            XCTAssertEqual(reopened.index.receipts.first?.needsRecovery, true)
            try bytes.write(to: downloaded)
            try reopened.commit(task, pin: "pin", downloaded: downloaded)
            let restored = try XCTUnwrap(reopened.receipt(task.id, pin: "pin"))
            XCTAssertTrue(reopened.receiptIsValid(restored, for: task))
            XCTAssertEqual(reopened.index.receipts.count, 1)
            XCTAssertFalse(restored.acknowledged)
        }
    }
    func testHTTPFailurePreservesStatusForRevokedCredentialRecovery() {
        XCTAssertThrowsError(try Transport.check(401)) { error in
            XCTAssertEqual((error as? TransferError)?.statusCode, 401)
        }
        XCTAssertThrowsError(try Transport.check(503)) { error in
            XCTAssertEqual((error as? TransferError)?.statusCode, 503)
            XCTAssertNotEqual((error as? TransferError)?.statusCode, 401)
        }
        XCTAssertNoThrow(try Transport.check(200))
    }
    @MainActor func testMissingTaskDoesNotStarveLaterQueueItems() async throws {
        var visited: [Int] = [], failed: [Int] = []
        try await QueuePolicy.run([1, 2, 3], operation: { item in
            visited.append(item)
            if item == 1 { throw TransferError(message: "任务不存在", statusCode: 400) }
            if item == 2 { throw TransferError(message: "磁盘空间不足", statusCode: 400) }
        }, failed: { item, error in
            failed.append(item)
            XCTAssertEqual(QueuePolicy.isTerminal(error), item == 1)
        })
        XCTAssertEqual(visited, [1, 2, 3]); XCTAssertEqual(failed, [1, 2])
    }
    @MainActor func testNetworkAndAuthorizationFailuresRemainGlobal() async {
        let failures: [Error] = [URLError(.notConnectedToInternet), TransferError(message: "授权失效", statusCode: 401), TransferError(message: "服务不可用", statusCode: 503)]
        for failure in failures {
            var visited: [Int] = [], localFailures = 0
            do {
                try await QueuePolicy.run([1, 2], operation: { item in visited.append(item); throw failure }, failed: { _, _ in localFailures += 1 })
                XCTFail("Global error must reach connection recovery")
            } catch { XCTAssertTrue(QueuePolicy.isGlobal(error)) }
            XCTAssertEqual(visited, [1]); XCTAssertEqual(localFailures, 0)
        }
    }
    func testTerminalRetryAndConfirmedCancelPersistWithoutDeletingHistoryOrFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DiskStore(root: root)
        let file = store.url("staged")
        try Data("retained".utf8).write(to: file)
        var expired = Outgoing(peerPin: "pin", name: "old.txt", filename: "staged", size: 8, hash: "hash")
        expired.remoteID = "expired"
        var cancelled = Outgoing(peerPin: "pin", name: "cancel.txt", filename: "cancelled", size: 0, hash: "hash")
        cancelled.cancelled = true
        store.index.outgoing = [expired, cancelled]
        let receipt = Receipt(id: "old-receipt", peerPin: "pin", name: "old.txt", filename: "staged", text: nil, date: Date(), acknowledged: false)
        store.index.receipts = [receipt]
        try store.outgoingFailed(expired.id, error: TransferError(message: "任务不存在", statusCode: 400))
        try store.finishCancellation(cancelled.id)
        try store.stopReceiptRetry(receipt, reason: "电脑任务已过期")
        let reopened = try DiskStore(root: root)
        XCTAssertEqual(reopened.index.outgoing.count, 2)
        XCTAssertNotNil(reopened.index.outgoing[0].retryStoppedReason)
        XCTAssertEqual(reopened.index.outgoing[1].cancelConfirmed, true)
        XCTAssertNotNil(reopened.index.receipts[0].retryStoppedReason)
        XCTAssertFalse(reopened.index.receipts[0].acknowledged)
        XCTAssertEqual(try Data(contentsOf: file), Data("retained".utf8))
    }
}
