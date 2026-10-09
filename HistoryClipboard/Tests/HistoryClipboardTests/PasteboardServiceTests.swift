import AppKit
import XCTest
@testable import HistoryClipboard

final class PasteboardServiceTests: XCTestCase {
    @MainActor
    func testSensitiveMarkersAreIgnoredBeforeReadingText() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let service = PasteboardService(pasteboard: board)
        for marker in PasteboardService.ignoredTypes {
            board.clearContents()
            board.setString("Do not store", forType: .string)
            board.setData(Data(), forType: marker)
            XCTAssertNil(try service.readSnapshot().content)
        }
    }

    @MainActor
    func testTextTakesPriorityWithoutDecodingImage() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let service = PasteboardService(pasteboard: board)
        board.setString("Text wins", forType: .string)
        board.setData(Data([1, 2, 3]), forType: .png)
        XCTAssertEqual(try service.readSnapshot().content, .text("Text wins"))
    }

    @MainActor
    func testRTFIsConvertedToPlainText() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let attributed = NSAttributedString(string: "Rich text")
        let data = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        board.setData(data, forType: .rtf)
        XCTAssertEqual(try PasteboardService(pasteboard: board).readSnapshot().content, .text("Rich text"))
    }

    @MainActor
    func testOwnWritesAreIgnoredButExternalWritesAreRecorded() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let service = PasteboardService(pasteboard: board)
        try service.write(text: "From history")
        XCTAssertNil(try service.readSnapshot().content)
        board.clearContents()
        board.setString("External copy", forType: .string)
        XCTAssertEqual(try service.readSnapshot().content, .text("External copy"))
    }

    @MainActor
    func testImageSnapshotUsesRawData() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let data = Data([1, 2, 3])
        board.setData(data, forType: .tiff)
        XCTAssertEqual(try PasteboardService(pasteboard: board).readSnapshot().content, .image(data))
    }

    @MainActor
    func testFailedWritesThrow() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let service = PasteboardService(pasteboard: board, writeObjects: { _ in false })
        XCTAssertThrowsError(try service.write(text: "Test"))
        XCTAssertThrowsError(try service.write(pngData: Data([1])))
    }

    @MainActor
    func testUnsupportedContentIsDeliberatelyIgnored() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setData(Data([1]), forType: .init("test.unsupported"))
        XCTAssertNil(try PasteboardService(pasteboard: board).readSnapshot().content)
    }
}
