import Foundation

final class CleanupService: @unchecked Sendable {
    static let shared = CleanupService()

    private let databaseManager = DatabaseManager.shared
    private let appSettings = AppSettings.shared
    private var timer: Timer?

    private init() {}

    func start() {
        // Run cleanup on start
        performCleanup()

        // Then every hour
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.performCleanup()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func performCleanup() {
        let cutoff = appSettings.retentionDays.cutoffTimestamp
        do {
            let allItems = try databaseManager.fetchAll()
            for item in allItems {
                guard !item.isPinned,
                      let id = item.id,
                      item.timestamp < cutoff else {
                    continue
                }
                // Delete image file if present
                if item.type == "image", let path = item.imagePath {
                    try? FileManager.default.removeItem(atPath: path)
                }
                try databaseManager.delete(id: id)
            }
        } catch {
            NSLog("HistoryClipboard: cleanup error: \(error)")
        }
    }
}
