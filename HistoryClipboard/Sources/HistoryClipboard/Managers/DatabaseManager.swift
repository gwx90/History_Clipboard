import GRDB
import Foundation

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue!

    private init() {}

    func setup() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbDir = appSupport.appendingPathComponent("HistoryClipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("clipboard.db").path

        dbQueue = try DatabaseQueue(path: dbPath)
        try createTablesIfNeeded()
    }

    private func createTablesIfNeeded() throws {
        try dbQueue.write { db in
            try db.create(table: "clipboard_items", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type", .text).notNull().check(sql: "type IN ('text', 'image')")
                t.column("content", .text)
                t.column("imagePath", .text)
                t.column("timestamp", .double).notNull()
                t.column("isPinned", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "idx_timestamp", on: "clipboard_items", columns: ["timestamp"], ifNotExists: true)
        }
    }

    // MARK: - Write Operations

    @discardableResult
    func insert(_ item: ClipboardItem) throws -> ClipboardItem {
        var newId: Int64 = 0
        try dbQueue.write { db in
            try item.insert(db)
            newId = db.lastInsertedRowID
        }
        var inserted = item
        inserted.id = newId
        return inserted
    }

    func delete(id: Int64) throws {
        _ = try dbQueue.write { db in
            try ClipboardItem.deleteOne(db, key: id)
        }
    }

    func deleteAllNonPinned() throws -> [ClipboardItem] {
        try dbQueue.write { db in
            let items = try ClipboardItem
                .filter(ClipboardItem.Columns.isPinned == false)
                .fetchAll(db)
            try ClipboardItem
                .filter(ClipboardItem.Columns.isPinned == false)
                .deleteAll(db)
            return items
        }
    }

    func pin(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clipboard_items SET isPinned = 1 WHERE id = ?",
                arguments: [id]
            )
        }
    }

    func unpin(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clipboard_items SET isPinned = 0 WHERE id = ?",
                arguments: [id]
            )
        }
    }

    func deleteExpired(olderThan cutoff: TimeInterval) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM clipboard_items WHERE isPinned = 0 AND timestamp < ?",
                arguments: [cutoff]
            )
        }
    }

    // MARK: - Read Operations

    func fetchAll() throws -> [ClipboardItem] {
        try dbQueue.read { db in
            try ClipboardItem
                .order(ClipboardItem.Columns.isPinned.desc, ClipboardItem.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }

    func search(keyword: String) throws -> [ClipboardItem] {
        try dbQueue.read { db in
            try ClipboardItem
                .filter(ClipboardItem.Columns.content.like("%\(keyword)%"))
                .order(ClipboardItem.Columns.isPinned.desc, ClipboardItem.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }

    func latestItem() throws -> ClipboardItem? {
        try dbQueue.read { db in
            try ClipboardItem
                .order(ClipboardItem.Columns.timestamp.desc)
                .fetchOne(db)
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in
            try ClipboardItem.fetchCount(db)
        }
    }
}
