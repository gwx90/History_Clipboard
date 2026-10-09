import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Serializes database mutations and image I/O away from the main actor.
actor HistoryStore {
    static let shared = HistoryStore(
        databaseManager: .shared,
        imageDirectory: URL.applicationSupportDirectory.appendingPathComponent("HistoryClipboard/Images", isDirectory: true)
    )

    enum ContentError: LocalizedError {
        case invalidImage
        case imageTooLarge
        case missingItem

        var errorDescription: String? {
            switch self {
            case .invalidImage: return "无法读取这张图片。"
            case .imageTooLarge: return "图片超过采集上限（50 MB 或 4000 万像素），本次未保存。"
            case .missingItem: return "该历史记录或图片已不存在，请刷新后重试。"
            }
        }
    }

    private let databaseManager: DatabaseManager
    private let imageDirectory: URL
    private let removeFile: @Sendable (URL) throws -> Void

    init(databaseManager: DatabaseManager, imageDirectory: URL,
         removeFile: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.databaseManager = databaseManager
        self.imageDirectory = imageDirectory.standardizedFileURL.resolvingSymlinksInPath()
        self.removeFile = removeFile
    }

    func capture(_ content: ClipboardContent, timestamp: TimeInterval = Date().timeIntervalSince1970) throws {
        try Task.checkCancellation()
        switch content {
        case .text(let text): try captureText(text, timestamp: timestamp)
        case .image(let data):
            let png = try encodePNG(data)
            try Task.checkCancellation()
            try capturePNG(png, timestamp: timestamp)
        }
    }

    private func encodePNG(_ data: Data) throws -> Data {
        guard data.count <= 50 * 1024 * 1024 else { throw ContentError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ContentError.invalidImage }
        guard Double(width) * Double(height) <= 40_000_000 else { throw ContentError.imageTooLarge }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ContentError.invalidImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw ContentError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ContentError.invalidImage }
        return output as Data
    }

    func captureText(_ text: String, timestamp: TimeInterval = Date().timeIntervalSince1970) throws {
        if let latest = try databaseManager.latestItem(), latest.type == "text", latest.content == text { return }
        try Task.checkCancellation()
        try databaseManager.insert(ClipboardItem(type: "text", content: text, timestamp: timestamp, isPinned: false))
    }

    func capturePNG(_ data: Data, timestamp: TimeInterval = Date().timeIntervalSince1970) throws {
        if let latest = try databaseManager.latestItem(), latest.type == "image", let path = latest.imagePath,
           let existing = try? Data(contentsOf: URL(fileURLWithPath: path)), existing == data { return }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        let url = imageDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try data.write(to: url, options: .atomic)
        do {
            try Task.checkCancellation()
            try databaseManager.insert(ClipboardItem(type: "image", imagePath: url.path, timestamp: timestamp, isPinned: false))
        } catch {
            // A crash or failed compensation is recovered by the orphan scan after a grace period.
            do { try removeFile(url) }
            catch { NSLog("HistoryClipboard: image compensation failed: \(error)") }
            throw error
        }
    }

    func fetchPage(keyword: String, limit: Int = 100, offset: Int = 0) throws -> HistoryPage {
        try Task.checkCancellation()
        return try databaseManager.fetchPage(keyword: keyword, limit: limit, offset: offset)
    }

    func pasteContent(id: Int64) throws -> ClipboardContent {
        guard let item = try databaseManager.fetchItem(id: id) else { throw ContentError.missingItem }
        switch item.type {
        case "text":
            guard let content = item.content else { throw ContentError.missingItem }
            return .text(content)
        case "image":
            guard let path = item.imagePath, isManagedImage(URL(fileURLWithPath: path)) else { throw ContentError.missingItem }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetStatus(source) == .statusComplete else { throw ContentError.invalidImage }
            return .image(data)
        default: throw ContentError.missingItem
        }
    }

    func delete(id: Int64) throws {
        try databaseManager.delete(id: id)
        try processPendingImageDeletions()
    }

    func clearNonPinned() throws {
        try databaseManager.deleteAllNonPinned()
        try processPendingImageDeletions()
    }

    func setPinned(id: Int64, isPinned: Bool) throws {
        if isPinned { try databaseManager.pin(id: id) }
        else { try databaseManager.unpin(id: id) }
    }

    func cleanup(olderThan cutoff: TimeInterval) throws {
        try Task.checkCancellation()
        try databaseManager.deleteExpired(olderThan: cutoff)
        try reconcileOrphanImages()
        try processPendingImageDeletions()
    }

    func processPendingImageDeletions() throws {
        let referenced = Set(try databaseManager.imagePaths().map {
            URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path
        })
        for path in try databaseManager.pendingImageDeletions() {
            let url = URL(fileURLWithPath: path)
            if referenced.contains(url.standardizedFileURL.resolvingSymlinksInPath().path) {
                try databaseManager.acknowledgeImageDeletion(path: path)
                continue
            }
            guard isManagedImage(url) else {
                NSLog("HistoryClipboard: refused image deletion outside managed UUID image files")
                continue
            }
            do {
                try removeFile(url)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                // A previous run may have removed the file before acknowledging the job.
            } catch {
                NSLog("HistoryClipboard: image deletion deferred: \(error)")
                continue
            }
            try databaseManager.acknowledgeImageDeletion(path: path)
        }
    }

    func reconcileOrphanImages(now: Date = Date()) throws {
        guard FileManager.default.fileExists(atPath: imageDirectory.path) else { return }
        let referenced = Set(try databaseManager.imagePaths().map {
            URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path
        })
        let files = try FileManager.default.contentsOfDirectory(
            at: imageDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]
        )
        for url in files where isManagedImage(url) && !referenced.contains(url.standardizedFileURL.resolvingSymlinksInPath().path) {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true, let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) >= 3600 else { continue }
            try databaseManager.enqueueImageDeletion(path: url.path)
        }
    }

    private func isManagedImage(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "png"
            && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
            && url.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
                == imageDirectory.standardizedFileURL.resolvingSymlinksInPath()
    }
}
