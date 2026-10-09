import GRDB
import Foundation

extension Notification.Name {
    static let clipboardHistoryDidChange = Notification.Name("HistoryClipboardHistoryDidChange")
}

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    enum InitializationError: LocalizedError {
        case notInitialized

        var errorDescription: String? {
            "剪贴板数据库尚未初始化。"
        }
    }

    private var dbQueue: DatabaseQueue?

    private var readyQueue: DatabaseQueue {
        get throws {
            guard let dbQueue else { throw InitializationError.notInitialized }
            return dbQueue
        }
    }

    init() {}

    init(databaseQueue: DatabaseQueue) throws {
        try setup(databaseQueue: databaseQueue)
    }

    func setup() throws {
        guard dbQueue == nil else { return }

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbDir = appSupport.appendingPathComponent("HistoryClipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("clipboard.db").path

        try setup(databaseQueue: DatabaseQueue(path: dbPath))
    }

    func setup(databaseQueue: DatabaseQueue) throws {
        guard dbQueue == nil else { return }
        try Self.createTablesIfNeeded(in: databaseQueue)
        dbQueue = databaseQueue
    }

    private static func createTablesIfNeeded(in dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            db.add(function: DatabaseFunction("localized_contains", argumentCount: 2, pure: true) { values in
                guard let text = String.fromDatabaseValue(values[0]), let keyword = String.fromDatabaseValue(values[1]) else { return false }
                return text.localizedCaseInsensitiveContains(keyword)
            })
            try db.create(table: "clipboard_items", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type", .text).notNull().check(sql: "type IN ('text', 'image')")
                t.column("content", .text)
                t.column("imagePath", .text)
                t.column("timestamp", .double).notNull()
                t.column("isPinned", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "idx_timestamp", on: "clipboard_items", columns: ["timestamp"], ifNotExists: true)
            try db.create(index: "idx_history_order", on: "clipboard_items", columns: ["isPinned", "timestamp", "id"], ifNotExists: true)
            try db.create(table: "pending_image_deletions", ifNotExists: true) { t in
                t.column("path", .text).notNull().primaryKey()
            }
        }
    }

    // MARK: - Write Operations

    @discardableResult
    func insert(_ item: ClipboardItem) throws -> ClipboardItem {
        var newId: Int64 = 0
        try readyQueue.write { db in
            try item.insert(db)
            newId = db.lastInsertedRowID
        }
        var inserted = item
        inserted.id = newId
        notifyChange()
        return inserted
    }

    func delete(id: Int64) throws {
        _ = try deleteItems(where: "id = ?", arguments: [id])
    }

    @discardableResult
    func deleteAllNonPinned() throws -> Int {
        try deleteItems(where: "isPinned = 0", arguments: [])
    }

    private func deleteItems(where predicate: String, arguments: StatementArguments) throws -> Int {
        let count = try readyQueue.write { db in
            let paths = try String.fetchAll(db,
                sql: "SELECT imagePath FROM clipboard_items WHERE (\(predicate)) AND type = 'image' AND imagePath IS NOT NULL",
                arguments: arguments)
            for path in paths {
                try db.execute(sql: "INSERT OR IGNORE INTO pending_image_deletions (path) VALUES (?)", arguments: [path])
            }
            try db.execute(sql: "DELETE FROM clipboard_items WHERE \(predicate)", arguments: arguments)
            return db.changesCount
        }
        if count > 0 { notifyChange() }
        return count
    }

    func pin(id: Int64) throws {
        try readyQueue.write { db in
            try db.execute(sql: "UPDATE clipboard_items SET isPinned = 1 WHERE id = ?", arguments: [id])
        }
        notifyChange()
    }

    func unpin(id: Int64) throws {
        try readyQueue.write { db in
            try db.execute(sql: "UPDATE clipboard_items SET isPinned = 0 WHERE id = ?", arguments: [id])
        }
        notifyChange()
    }

    @discardableResult
    func deleteExpired(olderThan cutoff: TimeInterval) throws -> Int {
        try deleteItems(where: "isPinned = 0 AND timestamp < ?", arguments: [cutoff])
    }

    func pendingImageDeletions() throws -> [String] {
        try readyQueue.read { db in
            try String.fetchAll(db, sql: "SELECT path FROM pending_image_deletions ORDER BY path")
        }
    }

    func enqueueImageDeletion(path: String) throws {
        try readyQueue.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO pending_image_deletions (path) VALUES (?)", arguments: [path])
        }
    }

    func acknowledgeImageDeletion(path: String) throws {
        try readyQueue.write { db in
            try db.execute(sql: "DELETE FROM pending_image_deletions WHERE path = ?", arguments: [path])
        }
    }

    func imagePaths() throws -> Set<String> {
        try readyQueue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT imagePath FROM clipboard_items WHERE type = 'image' AND imagePath IS NOT NULL"))
        }
    }

    // MARK: - Read Operations

    func fetchAll() throws -> [ClipboardItem] {
        try readyQueue.read { db in
            try ClipboardItem
                .order(ClipboardItem.Columns.isPinned.desc, ClipboardItem.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }

    func search(keyword: String) throws -> [ClipboardItem] {
        try readyQueue.read { db in
            try ClipboardItem
                .filter(sql: "localized_contains(content, ?)", arguments: [keyword])
                .order(ClipboardItem.Columns.isPinned.desc, ClipboardItem.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }

    func fetchPage(keyword: String = "", limit: Int = 100, offset: Int = 0) throws -> HistoryPage {
        try readyQueue.read { db in
            var request = ClipboardItem.all()
            if !keyword.isEmpty { request = request.filter(sql: "localized_contains(content, ?)", arguments: [keyword]) }
            let total = try request.fetchCount(db)
            let items = try request
                .order(ClipboardItem.Columns.isPinned.desc, ClipboardItem.Columns.timestamp.desc, ClipboardItem.Columns.id.desc)
                .limit(max(1, min(limit, 500)), offset: max(0, offset))
                .fetchAll(db)
            return HistoryPage(items: items, totalCount: total)
        }
    }

    func fetchItem(id: Int64) throws -> ClipboardItem? {
        try readyQueue.read { db in try ClipboardItem.fetchOne(db, key: id) }
    }

    func latestItem() throws -> ClipboardItem? {
        try readyQueue.read { db in
            try ClipboardItem
                .order(ClipboardItem.Columns.id.desc)
                .fetchOne(db)
        }
    }

    func count() throws -> Int {
        try readyQueue.read { db in
            try ClipboardItem.fetchCount(db)
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
    }
}
