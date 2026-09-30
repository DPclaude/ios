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
}
