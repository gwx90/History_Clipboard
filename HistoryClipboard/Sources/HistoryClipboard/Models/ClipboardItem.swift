import GRDB
import Foundation

struct ClipboardItem: Codable {
    var id: Int64?
    var type: String
    var content: String?
    var imagePath: String?
    var timestamp: TimeInterval
    var isPinned: Bool
}

// MARK: - GRDB Record Protocols
extension ClipboardItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "clipboard_items"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let type = Column(CodingKeys.type)
        static let content = Column(CodingKeys.content)
        static let imagePath = Column(CodingKeys.imagePath)
        static let timestamp = Column(CodingKeys.timestamp)
        static let isPinned = Column(CodingKeys.isPinned)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
