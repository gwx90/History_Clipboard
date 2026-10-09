import Foundation
import GRDB
import SwiftUI
import XCTest
@testable import HistoryClipboard

final class HistoryViewModelTests: XCTestCase {
    @MainActor
    private func fixture() throws -> (HistoryViewModel, DatabaseManager) {
        let database = try DatabaseManager(databaseQueue: DatabaseQueue())
        let store = HistoryStore(databaseManager: database,
            imageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        return (HistoryViewModel(store: store), database)
    }

    @MainActor
    func testLoadsAdditionalPagesAndRefreshesAfterMutation() async throws {
        let (model, database) = try fixture()
        for index in 0..<230 {
            try database.insert(ClipboardItem(type: "text", content: "Item \(index)", timestamp: Double(index), isPinned: false))
        }
        await model.setVisible(true)?.value
        XCTAssertEqual(model.items.count, 100)
        XCTAssertEqual(model.totalCount, 230)
        await model.loadMore()?.value
        XCTAssertEqual(model.items.count, 200)
        await model.loadMore()?.value
        XCTAssertEqual(model.items.count, 230)
        XCTAssertFalse(model.canLoadMore)
        try database.delete(id: XCTUnwrap(model.items.first?.id))
        await model.reload()?.value
        XCTAssertEqual(model.totalCount, 229)
        XCTAssertEqual(model.items.count, 100)
    }

    @MainActor
    func testAnimatedPinAndUnpinKeepIdentityAndCorrectOrder() async throws {
        let (model, database) = try fixture()
        try database.insert(ClipboardItem(type: "text", content: "Older", timestamp: 1, isPinned: false))
        try database.insert(ClipboardItem(type: "text", content: "Newer", timestamp: 2, isPinned: false))
        await model.setVisible(true)?.value
        let olderID = try XCTUnwrap(model.items.last?.id)

        try database.pin(id: olderID)
        await model.reload(animation: .spring(response: 0.32, dampingFraction: 0.82))?.value
        XCTAssertEqual(model.items.map(\.content), ["Older", "Newer"])
        XCTAssertEqual(model.items.first?.id, olderID)
        XCTAssertEqual(model.items.first?.isPinned, true)

        try database.unpin(id: olderID)
        await model.reload(animation: .spring(response: 0.32, dampingFraction: 0.82))?.value
        XCTAssertEqual(model.items.map(\.content), ["Newer", "Older"])
        XCTAssertEqual(model.items.last?.id, olderID)
        XCTAssertEqual(model.items.last?.isPinned, false)
        XCTAssertEqual(model.totalCount, 2)
    }

    @MainActor
    func testAnimatedDeletionRefreshesRemainingRowsAndLastRow() async throws {
        let (model, database) = try fixture()
        for timestamp in 1...2 {
            try database.insert(ClipboardItem(type: "text", content: "Item \(timestamp)", timestamp: Double(timestamp), isPinned: false))
        }
        await model.setVisible(true)?.value
        let remainingID = try XCTUnwrap(model.items.last?.id)
        try database.delete(id: XCTUnwrap(model.items.first?.id))
        await model.reload(animation: .easeInOut(duration: 0.22))?.value
        XCTAssertEqual(model.items.map(\.id), [remainingID])
        XCTAssertEqual(model.totalCount, 1)

        try database.delete(id: remainingID)
        await model.reload(animation: .easeInOut(duration: 0.22))?.value
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.totalCount, 0)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.canLoadMore)
    }

    @MainActor
    func testNewSearchCancelsPendingAnimatedRefresh() async throws {
        let (model, database) = try fixture()
        for text in ["Apple", "Banana"] {
            try database.insert(ClipboardItem(type: "text", content: text, timestamp: 1, isPinned: false))
        }
        await model.setVisible(true)?.value
        let animated = model.reload(debounce: true, animation: .easeInOut(duration: 0.28))
        model.searchText = "Banana"
        await model.reload()?.value
        await animated?.value
        XCTAssertEqual(model.items.map(\.content), ["Banana"])
        XCTAssertEqual(model.totalCount, 1)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.loadError)
    }

    @MainActor
    func testMutationWaitFollowsReplacementRefreshBeforeUnlocking() async throws {
        let (model, database) = try fixture()
        try database.insert(ClipboardItem(type: "text", content: "Pin", timestamp: 1, isPinned: false))
        await model.setVisible(true)?.value
        let id = try XCTUnwrap(model.items.first?.id)
        let waiting = Task {
            await model.reloadAndWait(debounce: true, animation: .easeInOut(duration: 0.22))
        }
        for _ in 0..<100 where !model.isLoading { await Task.yield() }
        XCTAssertTrue(model.isLoading)

        // Simulate a commit notification replacing the task the mutation awaits.
        try database.pin(id: id)
        let replacement = model.reload(debounce: true, animation: .easeInOut(duration: 0.22))
        await waiting.value
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.items.first?.isPinned, true)
        await replacement?.value
    }

    @MainActor
    func testMutationWaitFollowsNewSearchAndStopsOnHide() async throws {
        let (model, database) = try fixture()
        for text in ["Apple", "Banana"] {
            try database.insert(ClipboardItem(type: "text", content: text, timestamp: 1, isPinned: false))
        }
        await model.setVisible(true)?.value
        let waiting = Task { await model.reloadAndWait(debounce: true) }
        for _ in 0..<100 where !model.isLoading { await Task.yield() }
        XCTAssertTrue(model.isLoading)
        model.searchText = "Banana"
        let search = model.reload(debounce: true)
        await waiting.value
        XCTAssertEqual(model.items.map(\.content), ["Banana"])
        XCTAssertFalse(model.isLoading)
        await search?.value

        let hiding = Task { await model.reloadAndWait(debounce: true) }
        for _ in 0..<100 where !model.isLoading { await Task.yield() }
        XCTAssertTrue(model.isLoading)
        model.setVisible(false)
        await hiding.value
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.items.map(\.content), ["Banana"])
    }

    @MainActor
    func testFirstClearRefreshesVisibleHistoryAndPreservesPinnedRecords() async throws {
        let database = try DatabaseManager(databaseQueue: DatabaseQueue())
        let store = HistoryStore(databaseManager: database,
            imageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let model = HistoryViewModel(store: store)
        try database.insert(ClipboardItem(type: "text", content: "Keep", timestamp: 1, isPinned: true))
        for index in 0..<120 {
            try database.insert(ClipboardItem(type: "text", content: "Remove \(index)", timestamp: Double(index), isPinned: false))
        }
        await model.setVisible(true)?.value
        XCTAssertEqual(model.totalCount, 121)
        XCTAssertTrue(model.canLoadMore)

        try await store.clearNonPinned()
        await model.reload(animation: .easeInOut(duration: 0.28))?.value
        XCTAssertEqual(model.items.map(\.content), ["Keep"])
        XCTAssertEqual(model.totalCount, 1)
        XCTAssertFalse(model.canLoadMore)
        XCTAssertNil(model.loadError)
    }

    @MainActor
    func testClearRefreshesToEmptyStateWithoutASecondRequest() async throws {
        let database = try DatabaseManager(databaseQueue: DatabaseQueue())
        let store = HistoryStore(databaseManager: database,
            imageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let model = HistoryViewModel(store: store)
        try database.insert(ClipboardItem(type: "text", content: "Remove", timestamp: 1, isPinned: false))
        await model.setVisible(true)?.value
        try await store.clearNonPinned()
        await model.reload(animation: .easeInOut(duration: 0.28))?.value
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.totalCount, 0)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.loadError)
    }

    @MainActor
    func testStaleSearchCannotReplaceNewResults() async throws {
        let (model, database) = try fixture()
        for text in ["Apple", "Banana"] {
            try database.insert(ClipboardItem(type: "text", content: text, timestamp: 1000, isPinned: false))
        }
        await model.setVisible(true)?.value
        model.searchText = "Apple"
        let old = model.reload(debounce: true)
        model.searchText = "Banana"
        await model.reload()?.value
        await old?.value
        XCTAssertEqual(model.items.map(\.content), ["Banana"])
        XCTAssertEqual(model.totalCount, 1)
    }

    @MainActor
    func testHiddenPanelDoesNotReloadAndCancelsPendingSearch() async throws {
        let (model, database) = try fixture()
        try database.insert(ClipboardItem(type: "text", content: "Original", timestamp: 1000, isPinned: false))
        await model.setVisible(true)?.value
        model.searchText = "Nothing"
        let pending = model.reload(debounce: true)
        model.setVisible(false)
        await pending?.value
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.reload())
        XCTAssertEqual(model.items.count, 1)
    }

    @MainActor
    func testFailedNewSearchCannotAppendPagesToOldQuery() async throws {
        let queue = try DatabaseQueue()
        let database = try DatabaseManager(databaseQueue: queue)
        for prefix in ["Apple", "Banana"] {
            for index in 0..<230 {
                try database.insert(ClipboardItem(type: "text", content: "\(prefix) \(index)", timestamp: Double(index), isPinned: false))
            }
        }
        let store = HistoryStore(databaseManager: database, imageDirectory: FileManager.default.temporaryDirectory)
        let model = HistoryViewModel(store: store)
        model.searchText = "Apple"
        await model.setVisible(true)?.value
        XCTAssertTrue(model.canLoadMore)
        model.searchText = "Banana"
        XCTAssertNil(model.loadMore())
        try await queue.write { db in
            db.add(function: DatabaseFunction("localized_contains", argumentCount: 2) { _ -> Bool in
                throw CocoaError(.fileReadUnknown)
            })
        }
        await model.reload()?.value
        XCTAssertNotNil(model.loadError)
        XCTAssertFalse(model.canLoadMore)
        XCTAssertNil(model.loadMore())
        try await queue.write { db in
            db.add(function: DatabaseFunction("localized_contains", argumentCount: 2) { values in
                guard let text = String.fromDatabaseValue(values[0]), let keyword = String.fromDatabaseValue(values[1]) else { return false }
                return text.localizedCaseInsensitiveContains(keyword)
            })
        }
        await model.reload()?.value
        await model.loadMore()?.value
        XCTAssertEqual(model.items.count, 200)
        XCTAssertTrue(model.items.allSatisfy { $0.content?.hasPrefix("Banana") == true })
        XCTAssertNil(model.loadError)
    }

    @MainActor
    func testReadFailureIsNotPresentedAsEmptyHistory() async throws {
        let store = HistoryStore(databaseManager: DatabaseManager(), imageDirectory: FileManager.default.temporaryDirectory)
        let model = HistoryViewModel(store: store)
        await model.setVisible(true)?.value
        XCTAssertNotNil(model.loadError)
        XCTAssertFalse(model.isLoading)
    }
}
