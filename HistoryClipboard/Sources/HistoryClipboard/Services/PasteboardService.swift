import AppKit
import Foundation

final class PasteboardService: @unchecked Sendable {
    static let shared = PasteboardService()

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = 0

    private init() {}

    var currentChangeCount: Int {
        pasteboard.changeCount
    }

    // MARK: - Read

    func readString() -> String? {
        guard let items = pasteboard.readObjects(forClasses: [NSString.self], options: nil),
              let string = items.first as? String else {
            return nil
        }
        return string.isEmpty ? nil : string
    }

    func readImage() -> NSImage? {
        guard let items = pasteboard.readObjects(forClasses: [NSImage.self], options: nil),
              let image = items.first as? NSImage else {
            return nil
        }
        return image
    }

    func readContent() -> (text: String?, image: NSImage?) {
        let text = readString()
        let image = readImage()
        return (text, image)
    }

    // MARK: - Write

    func write(text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func write(image: NSImage) {
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}
