import Foundation
import ImageIO
import XCTest
@testable import HistoryClipboard

final class ThumbnailCacheTests: XCTestCase {
    private func dimensions(_ data: Data) throws -> (Int, Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
                try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int))
    }

    func testLargeImageIsDownsampledAndCached() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestImageData.make(width: 800, height: 400).write(to: url)
        let cache = ThumbnailCache()
        let first = try await cache.thumbnail(path: url.path)
        let second = try await cache.thumbnail(path: url.path)
        XCTAssertEqual(first, second)
        let (width, height) = try dimensions(first)
        XCTAssertEqual(width, 80)
        XCTAssertEqual(height, 40)
    }

    func testDeletedFileDoesNotReturnStaleCachedPreview() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestImageData.make().write(to: url)
        let cache = ThumbnailCache()
        _ = try await cache.thumbnail(path: url.path)
        try FileManager.default.removeItem(at: url)
        do {
            _ = try await cache.thumbnail(path: url.path)
            XCTFail("Expected missing file")
        } catch { }
    }

    func testReplacementFileInvalidatesCachedPreview() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = ThumbnailCache()
        try TestImageData.make(width: 800, height: 400).write(to: url)
        _ = try await cache.thumbnail(path: url.path)
        try TestImageData.make(width: 400, height: 800).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(1)], ofItemAtPath: url.path)
        let next = try await cache.thumbnail(path: url.path)
        let (width, height) = try dimensions(next)
        XCTAssertEqual(width, 40)
        XCTAssertEqual(height, 80)
    }
}
