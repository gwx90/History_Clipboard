import Foundation

enum ClipboardContent: Sendable, Equatable {
    case text(String)
    case image(Data)
}

struct PasteboardSnapshot: Sendable {
    let changeCount: Int
    /// Nil means deliberately ignored (sensitive, unsupported, empty, or our own write).
    let content: ClipboardContent?
}
