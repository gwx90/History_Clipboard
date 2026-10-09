import GRDB
import XCTest
@testable import HistoryClipboard

final class DatabaseManagerTests: XCTestCase {
    var dbManager: DatabaseManager!

    override func setUpWithError() throws {
        // Every test owns a fresh in-memory database, never the production singleton.
        dbManager = try DatabaseManager(databaseQueue: DatabaseQueue())
    }

    override func tearDownWithError() throws {
        dbManager = nil
    }

    func testDatabaseInstancesAreIsolated() throws {
        let pinned = try dbManager.insert(ClipboardItem(
            type: "text", content: "Keep this", timestamp: 1000, isPinned: true
        ))
        let pinnedId = try XCTUnwrap(pinned.id)
        let otherManager = try DatabaseManager(databaseQueue: DatabaseQueue())

        XCTAssertEqual(try otherManager.count(), 0)
        let other = try otherManager.insert(ClipboardItem(
            type: "text", content: "Other database", timestamp: 2000, isPinned: false
        ))
        try otherManager.delete(id: XCTUnwrap(other.id))

        let remaining = try dbManager.fetchAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, pinnedId)
        XCTAssertEqual(remaining.first?.content, "Keep this")
        XCTAssertEqual(remaining.first?.isPinned, true)
    }

    func testOperationsBeforeSetupThrowInsteadOfCrashing() throws {
        let manager = DatabaseManager()
        let item = ClipboardItem(
            type: "text", content: "Not stored", timestamp: 1000, isPinned: false
        )
        let operations: [() throws -> Void] = [
            { _ = try manager.insert(item) },
            { try manager.delete(id: 1) },
            { _ = try manager.deleteAllNonPinned() },
            { try manager.pin(id: 1) },
            { try manager.unpin(id: 1) },
            { try manager.deleteExpired(olderThan: 5000) },
            { _ = try manager.fetchAll() },
            { _ = try manager.search(keyword: "test") },
            { _ = try manager.latestItem() },
            { _ = try manager.count() }
        ]

        for operation in operations {
            XCTAssertThrowsError(try operation()) { error in
                XCTAssertEqual(error as? DatabaseManager.InitializationError, .notInitialized)
            }
        }
    }

    func testFailedSetupCanBeRetried() throws {
        let manager = DatabaseManager()
        let incompatibleQueue = try DatabaseQueue()
        try incompatibleQueue.write { db in
            try db.execute(sql: "CREATE TABLE clipboard_items (id INTEGER PRIMARY KEY)")
        }

        XCTAssertThrowsError(try manager.setup(databaseQueue: incompatibleQueue))
        XCTAssertThrowsError(try manager.count()) { error in
            XCTAssertEqual(error as? DatabaseManager.InitializationError, .notInitialized)
        }

        try manager.setup(databaseQueue: DatabaseQueue())
        try manager.insert(ClipboardItem(
            type: "text", content: "Recovered", timestamp: 1000, isPinned: false
        ))
        XCTAssertEqual(try manager.fetchAll().first?.content, "Recovered")
    }

    func testRepeatedSetupPreservesExistingDatabase() throws {
        try dbManager.insert(ClipboardItem(
            type: "text", content: "Keep this", timestamp: 1000, isPinned: true
        ))
        let otherQueue = try DatabaseQueue()

        try dbManager.setup(databaseQueue: otherQueue)

        let remaining = try dbManager.fetchAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.content, "Keep this")
        XCTAssertEqual(remaining.first?.isPinned, true)
        let hasClipboardTable = try otherQueue.read { db in
            try db.tableExists("clipboard_items")
        }
        XCTAssertFalse(hasClipboardTable)
    }

    func testSearchTreatsWildcardCharactersLiterallyAndSupportsUnicode() throws {
        for text in ["100% ready", "file_name", "plain", "CAFÉ 中文"] {
            try dbManager.insert(ClipboardItem(type: "text", content: text, timestamp: 1000, isPinned: false))
        }
        XCTAssertEqual(try dbManager.search(keyword: "%").map(\.content), ["100% ready"])
        XCTAssertEqual(try dbManager.search(keyword: "_").map(\.content), ["file_name"])
        XCTAssertEqual(try dbManager.search(keyword: "café").map(\.content), ["CAFÉ 中文"])
        XCTAssertEqual(try dbManager.search(keyword: "中文").count, 1)
    }

    func testPagesHaveStableOrderingAndCount() throws {
        for index in 0..<230 {
            try dbManager.insert(ClipboardItem(type: "text", content: "Item \(index)", timestamp: 1000, isPinned: index == 0))
        }
        let first = try dbManager.fetchPage(limit: 100)
        let second = try dbManager.fetchPage(limit: 100, offset: 100)
        let third = try dbManager.fetchPage(limit: 100, offset: 200)
        XCTAssertEqual(first.items.count, 100)
        XCTAssertEqual(second.items.count, 100)
        XCTAssertEqual(third.items.count, 30)
        XCTAssertEqual(first.totalCount, 230)
        XCTAssertEqual(first.items.first?.content, "Item 0")
        let ids = (first.items + second.items + third.items).compactMap(\.id)
        XCTAssertEqual(Set(ids).count, 230)
        XCTAssertEqual(try dbManager.fetchPage(keyword: "Item 229").totalCount, 1)
    }

    func testInsertTextItem() throws {
        let item = ClipboardItem(
            type: "text",
            content: "Hello, World!",
            timestamp: Date().timeIntervalSince1970,
            isPinned: false
        )
        let inserted = try dbManager.insert(item)
        XCTAssertNotNil(inserted.id)

        let all = try dbManager.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.content, "Hello, World!")
    }

    func testInsertImageItem() throws {
        let item = ClipboardItem(
            type: "image",
            imagePath: "/tmp/test-image.png",
            timestamp: Date().timeIntervalSince1970,
            isPinned: false
        )
        let inserted = try dbManager.insert(item)
        XCTAssertNotNil(inserted.id)
        XCTAssertEqual(inserted.type, "image")
    }

    func testFetchAllOrdering() throws {
        // Insert older item first
        let old = ClipboardItem(type: "text", content: "Old", timestamp: 1000, isPinned: false)
        let newer = ClipboardItem(type: "text", content: "Newer", timestamp: 2000, isPinned: false)
        try dbManager.insert(old)
        try dbManager.insert(newer)

        let all = try dbManager.fetchAll()
        // newest first
        XCTAssertEqual(all.first?.content, "Newer")
        XCTAssertEqual(all.last?.content, "Old")
    }

    func testPinnedItemsFirst() throws {
        let normal = ClipboardItem(type: "text", content: "Normal", timestamp: 3000, isPinned: false)
        let pinned = ClipboardItem(type: "text", content: "Pinned", timestamp: 1000, isPinned: false)
        try dbManager.insert(normal)
        try dbManager.insert(pinned)

        // Pin the older one
        let items = try dbManager.fetchAll()
        if let pinnedId = items.first(where: { $0.content == "Pinned" })?.id {
            try dbManager.pin(id: pinnedId)
        }

        let all = try dbManager.fetchAll()
        // Pinned should be first regardless of timestamp
        XCTAssertEqual(all.first?.content, "Pinned")
        XCTAssertEqual(all.first?.isPinned, true)
    }

    func testSearch() throws {
        try dbManager.insert(ClipboardItem(type: "text", content: "Apple pie recipe", timestamp: 1000, isPinned: false))
        try dbManager.insert(ClipboardItem(type: "text", content: "Banana bread", timestamp: 2000, isPinned: false))
        try dbManager.insert(ClipboardItem(type: "text", content: "Cherry tart", timestamp: 3000, isPinned: false))

        let results = try dbManager.search(keyword: "pie")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.content, "Apple pie recipe")
    }

    func testDelete() throws {
        let item = ClipboardItem(type: "text", content: "Delete me", timestamp: 1000, isPinned: false)
        let inserted = try dbManager.insert(item)
        let insertedId = try XCTUnwrap(inserted.id)

        try dbManager.delete(id: insertedId)
        let all = try dbManager.fetchAll()
        XCTAssertEqual(all.count, 0)
    }

    func testUnpin() throws {
        let item = ClipboardItem(type: "text", content: "Toggle", timestamp: 1000, isPinned: false)
        let inserted = try dbManager.insert(item)
        let insertedId = try XCTUnwrap(inserted.id)
        try dbManager.pin(id: insertedId)

        var fetched = try dbManager.fetchAll()
        XCTAssertEqual(fetched.first?.isPinned, true)

        try dbManager.unpin(id: insertedId)
        fetched = try dbManager.fetchAll()
        XCTAssertEqual(fetched.first?.isPinned, false)
    }

    func testExpiredDeletion() throws {
        // Current item - should NOT be deleted
        let recent = ClipboardItem(type: "text", content: "Recent", timestamp: Date().timeIntervalSince1970, isPinned: false)
        // Old item - should be deleted
        let old = ClipboardItem(type: "text", content: "Old", timestamp: 1000, isPinned: false)
        // Pinned old item - should NOT be deleted
        let pinnedOld = ClipboardItem(type: "text", content: "PinnedOld", timestamp: 1000, isPinned: false)

        try dbManager.insert(recent)
        try dbManager.insert(old)
        let pinnedInserted = try dbManager.insert(pinnedOld)
        let pinnedInsertedId = try XCTUnwrap(pinnedInserted.id)
        try dbManager.pin(id: pinnedInsertedId)

        // Delete items older than 5000 (which is after 1970)
        try dbManager.deleteExpired(olderThan: 5000)

        let remaining = try dbManager.fetchAll()
        XCTAssertEqual(remaining.count, 2) // recent + pinned old (old was deleted, pinnedOld kept)
    }
}
