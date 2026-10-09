import AppKit
import Observation

@MainActor
@Observable
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private let pasteboardService: PasteboardService
    private let settings: AppSettings
    private let store: HistoryStore
    private let frontmostApplicationID: () -> String?
    private var timer: Timer?
    private var pollTask: Task<Void, Never>?
    private(set) var isProcessing = false
    private var captureTask: Task<Void, Error>?
    private var lastProcessedCount: Int
    private var failedChangeCount: Int?
    private var attempts = 0
    private var preferencesGeneration = 0
    private(set) var lastError: String?

    init(pasteboardService: PasteboardService = .shared, settings: AppSettings = .shared,
         store: HistoryStore = .shared,
         frontmostApplicationID: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }) {
        self.pasteboardService = pasteboardService
        self.settings = settings
        self.store = store
        self.frontmostApplicationID = frontmostApplicationID
        lastProcessedCount = pasteboardService.currentChangeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.schedulePoll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        schedulePoll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pollTask?.cancel()
        captureTask?.cancel()
        pollTask = nil
    }

    func discardCurrentChange() {
        preferencesGeneration += 1
        captureTask?.cancel()
        lastProcessedCount = pasteboardService.currentChangeCount
        failedChangeCount = nil
        attempts = 0
        lastError = nil
    }

    private func schedulePoll() {
        guard pollTask == nil else { return }
        pollTask = Task {
            await poll()
            pollTask = nil
        }
    }

    /// Public internally so tests can drive deterministic polls without a timer or the general pasteboard.
    func poll() async {
        guard !isProcessing else { return }
        let count = pasteboardService.currentChangeCount
        if settings.isMonitoringPaused || settings.excludesApplication(frontmostApplicationID()) {
            lastProcessedCount = count
            failedChangeCount = nil
            attempts = 0
            lastError = nil
            return
        }
        guard count != lastProcessedCount else { return }
        if failedChangeCount != count {
            failedChangeCount = count
            attempts = 0
        }
        guard attempts < 3 else { return }
        let generation = preferencesGeneration
        isProcessing = true
        defer { isProcessing = false }
        attempts += 1
        do {
            let snapshot = try pasteboardService.readSnapshot()
            if let content = snapshot.content {
                let task = Task { try await store.capture(content) }
                captureTask = task
                defer { captureTask = nil }
                try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: { task.cancel() }
            }
            guard generation == preferencesGeneration else { return }
            lastProcessedCount = snapshot.changeCount
            failedChangeCount = nil
            attempts = 0
            lastError = nil
        } catch is CancellationError {
        } catch let error as HistoryStore.ContentError {
            // Invalid/oversized data cannot be fixed by rereading the same change.
            guard generation == preferencesGeneration else { return }
            lastProcessedCount = count
            lastError = error.localizedDescription
        } catch {
            guard generation == preferencesGeneration else { return }
            lastError = attempts >= 3 ? "采集失败，已停止重试本次内容。下一次复制后会继续记录。" : "采集失败，正在重试。"
            NSLog("HistoryClipboard: capture attempt \(attempts) failed: \(error)")
        }
    }
}
