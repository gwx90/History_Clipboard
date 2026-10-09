import AppKit
import GRDB
import XCTest
@testable import HistoryClipboard

final class ClipboardMonitorTests: XCTestCase, @unchecked Sendable {
    @MainActor
    private func runWithMonitor(_ body: @MainActor (ClipboardMonitor, NSPasteboard, AppSettings, DatabaseManager, DatabaseQueue) async throws -> Void) async throws {
        let board = NSPasteboard.withUniqueName()
        let suite = "HistoryClipboardTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            board.releaseGlobally()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let settings = AppSettings(defaults: defaults)
        let queue = try DatabaseQueue()
        let database = try DatabaseManager(databaseQueue: queue)
        let store = HistoryStore(databaseManager: database, imageDirectory: root)
        let monitor = ClipboardMonitor(pasteboardService: PasteboardService(pasteboard: board), settings: settings,
                                       store: store, frontmostApplicationID: { "test.app" })
        try await body(monitor, board, settings, database, queue)
    }

    @MainActor
    func testPauseCancelsCaptureWaitingForBusyStore() async throws {
        let board = NSPasteboard.withUniqueName()
        let suite = "HistoryClipboardPauseTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let release = DispatchSemaphore(value: 0)
        defer {
            release.signal()
            board.releaseGlobally()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent(UUID().uuidString + ".png").path
        try Data([1]).write(to: URL(fileURLWithPath: path))
        let database = try DatabaseManager(databaseQueue: DatabaseQueue())
        try database.enqueueImageDeletion(path: path)
        let entered = expectation(description: "Store is busy with image I/O")
        let busyStore = HistoryStore(databaseManager: database, imageDirectory: root, removeFile: { _ in
            entered.fulfill()
            release.wait()
            throw CocoaError(.fileWriteNoPermission)
        })
        let blocker = Task.detached { try await busyStore.processPendingImageDeletions() }
        await fulfillment(of: [entered], timeout: 2)
        let settings = AppSettings(defaults: defaults)
        let monitor = ClipboardMonitor(pasteboardService: PasteboardService(pasteboard: board), settings: settings,
            store: busyStore, frontmostApplicationID: { nil })
        board.clearContents()
        board.setString("Queued before pause", forType: .string)
        let poll = Task { await monitor.poll() }
        for _ in 0..<100 {
            if monitor.isProcessing { break }
            await Task.yield()
        }
        XCTAssertTrue(monitor.isProcessing)
        settings.isMonitoringPaused = true
        monitor.discardCurrentChange()
        release.signal()
        try await blocker.value
        await poll.value
        XCTAssertEqual(try database.count(), 0)
        XCTAssertNil(monitor.lastError)
    }

    @MainActor
    func testFailedCaptureRetriesSameChange() async throws {
        try await runWithMonitor { monitor, board, _, database, queue in
            try await queue.write { db in
                try db.execute(sql: "CREATE TRIGGER fail_insert BEFORE INSERT ON clipboard_items BEGIN SELECT RAISE(ABORT, 'test failure'); END")
            }
            board.clearContents()
            board.setString("Retry me", forType: .string)
            await monitor.poll()
            XCTAssertEqual(try database.count(), 0)
            XCTAssertNotNil(monitor.lastError)
            try await queue.write { db in try db.execute(sql: "DROP TRIGGER fail_insert") }
            await monitor.poll()
            XCTAssertEqual(try database.fetchAll().first?.content, "Retry me")
            XCTAssertNil(monitor.lastError)
        }
    }

    @MainActor
    func testRetriesAreBoundedAndNextCopyRecovers() async throws {
        try await runWithMonitor { monitor, board, _, database, queue in
            try await queue.write { db in
                try db.execute(sql: "CREATE TRIGGER fail_insert BEFORE INSERT ON clipboard_items BEGIN SELECT RAISE(ABORT, 'test failure'); END")
            }
            board.clearContents()
            board.setString("Fails", forType: .string)
            for _ in 0..<3 { await monitor.poll() }
            try await queue.write { db in try db.execute(sql: "DROP TRIGGER fail_insert") }
            await monitor.poll()
            XCTAssertEqual(try database.count(), 0)
            board.clearContents()
            board.setString("Next copy", forType: .string)
            await monitor.poll()
            XCTAssertEqual(try database.fetchAll().first?.content, "Next copy")
        }
    }

    @MainActor
    func testPausedAndExcludedCopiesAreNotCollectedOnResume() async throws {
        try await runWithMonitor { monitor, board, settings, database, _ in
            settings.isMonitoringPaused = true
            board.clearContents()
            board.setString("While paused", forType: .string)
            await monitor.poll()
            settings.isMonitoringPaused = false
            await monitor.poll()
            XCTAssertEqual(try database.count(), 0)
            settings.excludedApplicationIDs = "  test.app  \nother.app"
            board.clearContents()
            board.setString("Excluded", forType: .string)
            await monitor.poll()
            settings.excludedApplicationIDs = ""
            await monitor.poll()
            XCTAssertEqual(try database.count(), 0)
            board.clearContents()
            board.setString("Allowed", forType: .string)
            await monitor.poll()
            XCTAssertEqual(try database.count(), 1)
        }
    }

    @MainActor
    func testConsecutiveDuplicateIsNotStoredTwice() async throws {
        try await runWithMonitor { monitor, board, _, database, _ in
            board.clearContents()
            board.setString("Same", forType: .string)
            await monitor.poll()
            board.clearContents()
            board.setString("Same", forType: .string)
            await monitor.poll()
            XCTAssertEqual(try database.count(), 1)
        }
    }

    @MainActor
    func testSensitiveCopyDoesNotReachDatabase() async throws {
        try await runWithMonitor { monitor, board, _, database, _ in
            board.clearContents()
            board.setString("Secret", forType: .string)
            board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
            await monitor.poll()
            XCTAssertEqual(try database.count(), 0)
        }
    }

    @MainActor
    func testDiscardCurrentChangeSkipsCopiesBeforeResume() async throws {
        try await runWithMonitor { monitor, board, _, database, _ in
            board.clearContents()
            board.setString("Do not capture after resume", forType: .string)
            monitor.discardCurrentChange()
            await monitor.poll()
            XCTAssertEqual(try database.count(), 0)
        }
    }
}
