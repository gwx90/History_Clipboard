import AppKit
import Foundation

final class ClipboardMonitor: @unchecked Sendable {
    static let shared = ClipboardMonitor()

    private let pasteboardService = PasteboardService.shared
    private let databaseManager = DatabaseManager.shared

    private var timer: Timer?
    private var lastChangeCount: Int

    private init() {
        lastChangeCount = pasteboardService.currentChangeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        // Fire immediately on start
        checkPasteboard()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func checkPasteboard() {
        let currentChangeCount = pasteboardService.currentChangeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        let (text, image) = pasteboardService.readContent()

        if let text, !text.isEmpty {
            handleText(text)
        } else if let image {
            handleImage(image)
        }
    }

    private func handleText(_ text: String) {
        // Dedup: skip if same as latest stored item
        if let latest = try? databaseManager.latestItem(),
           latest.type == "text",
           latest.content == text {
            return
        }

        let item = ClipboardItem(
            type: "text",
            content: text,
            timestamp: Date().timeIntervalSince1970,
            isPinned: false
        )
        _ = try? databaseManager.insert(item)
    }

    private func handleImage(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        // Dedup: compare file size with latest image
        if let latest = try? databaseManager.latestItem(),
           latest.type == "image",
           let existingPath = latest.imagePath {
            let existingData = try? Data(contentsOf: URL(fileURLWithPath: existingPath))
            if existingData == pngData { return }
        }

        // Save image to disk
        let imageDir = imageStorageDirectory()
        let filename = UUID().uuidString + ".png"
        let fileURL = imageDir.appendingPathComponent(filename)

        do {
            try pngData.write(to: fileURL)
        } catch {
            return
        }

        let item = ClipboardItem(
            type: "image",
            imagePath: fileURL.path,
            timestamp: Date().timeIntervalSince1970,
            isPinned: false
        )
        _ = try? databaseManager.insert(item)
    }

    private func imageStorageDirectory() -> URL {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let imagesDir = appSupport.appendingPathComponent("HistoryClipboard/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        return imagesDir
    }
}
