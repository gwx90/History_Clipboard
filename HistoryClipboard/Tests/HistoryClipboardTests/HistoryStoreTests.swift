import Foundation
import GRDB
import XCTest
@testable import HistoryClipboard

final class HistoryStoreTests: XCTestCase, @unchecked Sendable {
    private var root: URL!
    private var images: URL!
    private var queue: DatabaseQueue!
    private var database: DatabaseManager!
    private var store: HistoryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        images = root.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        queue = try DatabaseQueue()
        database = try DatabaseManager(databaseQueue: queue)
        store = HistoryStore(databaseManager: database, imageDirectory: images)
    }

    override func tearDownWithError() throws {
        store = nil
        database = nil
        queue = nil
        try FileManager.default.removeItem(at: root)
    }

    func testTextDedupUsesCaptureOrderWhenClockMovesBackwards() async throws {
        try await store.captureText("A", timestamp: 1000)
        try await store.captureText("B", timestamp: 900)
        try await store.captureText("A", timestamp: 901)
        XCTAssertEqual(try database.count(), 3)
        XCTAssertEqual(try database.latestItem()?.timestamp, 901)
        // Display order remains timestamp-descending, independent from dedup order.
        XCTAssertEqual(try database.fetchPage().items.first?.timestamp, 1000)
    }

    func testImageDedupUsesCaptureOrderWhenClockMovesBackwards() async throws {
        try await store.capturePNG(Data([1]), timestamp: 1000)
        try await store.capturePNG(Data([2]), timestamp: 900)
        try await store.capturePNG(Data([1]), timestamp: 901)
        XCTAssertEqual(try database.count(), 3)
    }

    func testImageCaptureConvertsTIFFAndDeduplicates() async throws {
        let tiff = try TestImageData.make(type: .tiff)
        try await store.capture(.image(tiff))
        let path = try XCTUnwrap(database.latestItem()?.imagePath)
        let png = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let copied = try await store.pasteContent(id: XCTUnwrap(database.latestItem()?.id))
        XCTAssertEqual(copied, .image(png))
        try await store.capture(.image(tiff))
        XCTAssertEqual(try database.count(), 1)
    }

    func testInvalidAndOversizedImagesAreRejectedBeforeWritingFiles() async throws {
        for data in [Data([1, 2, 3]), Data(count: 50 * 1024 * 1024 + 1)] {
            do {
                try await store.capture(.image(data))
                XCTFail("Expected invalid content")
            } catch is HistoryStore.ContentError {
            }
        }
        XCTAssertEqual(try database.count(), 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: images.path).isEmpty)
    }

    func testPendingDeletionDoesNotRemoveImageReferencedByPinnedRecord() async throws {
        try await store.capturePNG(Data([1]))
        let path = try XCTUnwrap(database.latestItem()?.imagePath)
        try database.insert(ClipboardItem(type: "image", imagePath: path, timestamp: 1000, isPinned: true))
        try await store.clearNonPinned()
        XCTAssertEqual(try database.count(), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(try database.pendingImageDeletions().isEmpty)
    }

    func testCopyingDeletedRecordReturnsMissingItem() async throws {
        try await store.captureText("Removed")
        let id = try XCTUnwrap(database.latestItem()?.id)
        try await store.delete(id: id)
        do {
            _ = try await store.pasteContent(id: id)
            XCTFail("Expected missing record")
        } catch HistoryStore.ContentError.missingItem { }
    }

    func testCopyingMissingImageFileThrows() async throws {
        try await store.capture(.image(TestImageData.make()))
        let item = try XCTUnwrap(database.latestItem())
        try FileManager.default.removeItem(atPath: XCTUnwrap(item.imagePath))
        do {
            _ = try await store.pasteContent(id: XCTUnwrap(item.id))
            XCTFail("Expected missing file")
        } catch { }
    }

    func testCopyingCorruptImageDoesNotReturnInvalidBytes() async throws {
        try await store.capture(.image(TestImageData.make()))
        let item = try XCTUnwrap(database.latestItem())
        try Data([1, 2, 3]).write(to: URL(fileURLWithPath: XCTUnwrap(item.imagePath)))
        do {
            _ = try await store.pasteContent(id: XCTUnwrap(item.id))
            XCTFail("Expected invalid image")
        } catch HistoryStore.ContentError.invalidImage { }
        XCTAssertEqual(try database.count(), 1)
    }

    func testFailedImageInsertRemovesWrittenFile() async throws {
        try await queue.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_insert BEFORE INSERT ON clipboard_items BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        do {
            try await store.capturePNG(Data([1, 2, 3]))
            XCTFail("Expected insert failure")
        } catch { }
        XCTAssertEqual(try database.count(), 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: images.path).isEmpty)
    }

    func testFailedDatabaseDeletionPreservesImageAndRollsBackJob() async throws {
        try await store.capturePNG(Data([1, 2, 3]))
        let item = try XCTUnwrap(database.latestItem())
        let path = try XCTUnwrap(item.imagePath)
        try await queue.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_delete BEFORE DELETE ON clipboard_items BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        do {
            try await store.delete(id: XCTUnwrap(item.id))
            XCTFail("Expected deletion failure")
        } catch { }
        XCTAssertEqual(try database.count(), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(try database.pendingImageDeletions().isEmpty)
    }

    func testFailedFileDeletionIsPersistedAndRetriedAfterReopeningDatabase() async throws {
        let dbURL = root.appendingPathComponent("test.db")
        let diskDatabase = try DatabaseManager(databaseQueue: DatabaseQueue(path: dbURL.path))
        let failingStore = HistoryStore(databaseManager: diskDatabase, imageDirectory: images, removeFile: { _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        try await failingStore.capturePNG(Data([1, 2, 3]))
        let item = try XCTUnwrap(diskDatabase.latestItem())
        let path = try XCTUnwrap(item.imagePath)
        try await failingStore.delete(id: XCTUnwrap(item.id))
        XCTAssertEqual(try diskDatabase.count(), 0)
        XCTAssertEqual(try diskDatabase.pendingImageDeletions(), [path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        let reopened = try DatabaseManager(databaseQueue: DatabaseQueue(path: dbURL.path))
        let retryStore = HistoryStore(databaseManager: reopened, imageDirectory: images)
        try await retryStore.processPendingImageDeletions()
        XCTAssertTrue(try reopened.pendingImageDeletions().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testCleanupPreservesPinnedAndRecentImages() async throws {
        try await store.capturePNG(Data([1]), timestamp: 1000)
        let oldPath = try XCTUnwrap(database.latestItem()?.imagePath)
        try await store.capturePNG(Data([2]), timestamp: 2000)
        let pinned = try XCTUnwrap(database.latestItem())
        try database.pin(id: XCTUnwrap(pinned.id))
        try await store.capturePNG(Data([3]), timestamp: 10000)
        let recentPath = try XCTUnwrap(database.latestItem()?.imagePath)

        try await store.cleanup(olderThan: 5000)

        XCTAssertEqual(try database.count(), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPath))
        XCTAssertTrue(try FileManager.default.fileExists(atPath: XCTUnwrap(pinned.imagePath)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentPath))
    }

    func testClearNonPinnedDeletesImagesButKeepsPinnedRecords() async throws {
        try await store.capturePNG(Data([1]), timestamp: 1000)
        let pinned = try XCTUnwrap(database.latestItem())
        try database.pin(id: XCTUnwrap(pinned.id))
        try await store.capturePNG(Data([2]), timestamp: 2000)
        let removedPath = try XCTUnwrap(database.latestItem()?.imagePath)
        try await store.clearNonPinned()
        XCTAssertEqual(try database.count(), 1)
        XCTAssertTrue(try FileManager.default.fileExists(atPath: XCTUnwrap(pinned.imagePath)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedPath))
    }

    func testMissingDeletedFileStillAcknowledgesJob() async throws {
        try await store.capturePNG(Data([1]))
        let item = try XCTUnwrap(database.latestItem())
        try FileManager.default.removeItem(atPath: XCTUnwrap(item.imagePath))
        try await store.delete(id: XCTUnwrap(item.id))
        XCTAssertTrue(try database.pendingImageDeletions().isEmpty)
    }

    func testDeletionNeverRemovesFilesOutsideImageDirectory() async throws {
        let outside = root.appendingPathComponent(UUID().uuidString + ".png")
        try Data([1]).write(to: outside)
        let item = try database.insert(ClipboardItem(type: "image", imagePath: outside.path, timestamp: 1000, isPinned: false))
        try await store.delete(id: XCTUnwrap(item.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertEqual(try database.pendingImageDeletions(), [outside.path])
    }

    func testOrphanScanRespectsGracePeriodReferencesAndFileNames() async throws {
        let old = images.appendingPathComponent(UUID().uuidString + ".png")
        let fresh = images.appendingPathComponent(UUID().uuidString + ".png")
        let unrelated = images.appendingPathComponent("keep.png")
        for url in [old, fresh, unrelated] { try Data([1]).write(to: url) }
        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-7200)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-7200)], ofItemAtPath: unrelated.path)
        try await store.capturePNG(Data([2]))
        let referenced = try XCTUnwrap(database.latestItem()?.imagePath)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-7200)], ofItemAtPath: referenced)

        // Legacy records can use /var while directory enumeration resolves to /private/var.
        let aliasReference = images.appendingPathComponent(UUID().uuidString + ".png")
        try Data([3]).write(to: aliasReference)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-7200)], ofItemAtPath: aliasReference.path)
        try database.insert(ClipboardItem(type: "image", imagePath: aliasReference.path, timestamp: 0, isPinned: true))
        try await store.reconcileOrphanImages(now: now)
        try await store.processPendingImageDeletions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: aliasReference.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: referenced))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }
}
