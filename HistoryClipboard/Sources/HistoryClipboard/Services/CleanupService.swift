import Foundation

@MainActor
final class CleanupService {
    static let shared = CleanupService()
    private var timer: Timer?
    private var cleanupTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard timer == nil else { return }
        performCleanup()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.performCleanup() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cleanupTask?.cancel()
        cleanupTask = nil
    }

    func performCleanup() {
        cleanupTask?.cancel()
        let cutoff = AppSettings.shared.retentionDays.cutoffTimestamp
        cleanupTask = Task {
            do {
                try Task.checkCancellation()
                try await HistoryStore.shared.cleanup(olderThan: cutoff)
            } catch is CancellationError {
            } catch { NSLog("HistoryClipboard: cleanup error: \(error)") }
        }
    }
}
