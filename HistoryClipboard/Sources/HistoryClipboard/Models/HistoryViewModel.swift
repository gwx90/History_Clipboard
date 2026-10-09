import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class HistoryViewModel {
    private let store: HistoryStore
    private let pageSize = 100
    private var loadTask: Task<Void, Never>?
    private var generation = 0
    private var isVisible = false
    private var loadedKeyword: String?

    private(set) var items: [ClipboardItem] = []
    private(set) var totalCount = 0
    private(set) var isLoading = false
    private(set) var canLoadMore = false
    private(set) var loadError: String?
    var searchText = ""

    init(store: HistoryStore = .shared) { self.store = store }

    @discardableResult
    func setVisible(_ visible: Bool) -> Task<Void, Never>? {
        guard visible != isVisible else { return nil }
        isVisible = visible
        if visible { return reload() }
        generation += 1
        loadTask?.cancel()
        isLoading = false
        return nil
    }

    @discardableResult
    func reload(debounce: Bool = false, animation: Animation? = nil) -> Task<Void, Never>? {
        guard isVisible else { return nil }
        generation += 1
        loadTask?.cancel()
        canLoadMore = false
        return requestPage(offset: 0, reset: true, debounce: debounce, animation: animation)
    }

    func reloadAndWait(debounce: Bool = false, animation: Animation? = nil) async {
        guard reload(debounce: debounce, animation: animation) != nil else { return }
        // A commit notification or search may replace the task being awaited.
        // Keep the operation locked until the latest refresh has settled.
        while let pending = loadTask {
            let pendingGeneration = generation
            await pending.value
            if generation == pendingGeneration { return }
        }
    }

    @discardableResult
    func loadMore() -> Task<Void, Never>? {
        guard isVisible, canLoadMore, !isLoading, loadedKeyword == searchText else { return nil }
        return requestPage(offset: items.count, reset: false, debounce: false)
    }

    private func requestPage(offset: Int, reset: Bool, debounce: Bool, animation: Animation? = nil) -> Task<Void, Never> {
        let requestGeneration = generation
        let keyword = reset ? searchText : (loadedKeyword ?? searchText)
        // A mutation refresh must never animate a pending search's new results.
        let pageAnimation = keyword == loadedKeyword ? animation : nil
        isLoading = true
        let task = Task {
            defer { if generation == requestGeneration { isLoading = false } }
            do {
                if debounce { try await Task.sleep(for: .milliseconds(150)) }
                try Task.checkCancellation()
                let page = try await store.fetchPage(keyword: keyword, limit: pageSize, offset: offset)
                try Task.checkCancellation()
                guard generation == requestGeneration else { return }
                // The animation belongs to applying the successful async result,
                // not to launching the task or performing the database operation.
                withAnimation(pageAnimation) {
                    if reset {
                        items = page.items
                        loadedKeyword = keyword
                    }
                    else { items.append(contentsOf: page.items) }
                    totalCount = page.totalCount
                    canLoadMore = items.count < totalCount
                    loadError = nil
                    isLoading = false
                }
            } catch is CancellationError {
            } catch {
                guard generation == requestGeneration else { return }
                loadError = error.localizedDescription
            }
        }
        loadTask = task
        return task
    }
}
