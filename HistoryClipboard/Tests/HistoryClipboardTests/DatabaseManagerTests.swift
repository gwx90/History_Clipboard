import XCTest
@testable import HistoryClipboard

final class DatabaseManagerTests: XCTestCase {
    var dbManager: DatabaseManager!

    override func setUp() async throws {
        // For testing, we use the shared instance which will create a test DB
        dbManager = DatabaseManager.shared
        try dbManager.setup()
        // Clean up any existing data
        let items = try dbManager.fetchAll()
        for item in items {
            if let id = item.id {
                try dbManager.delete(id: id)
            }
        }
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
