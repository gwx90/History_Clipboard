import AppKit
import XCTest
@testable import HistoryClipboard

final class AppLifecycleTests: XCTestCase {
    @MainActor
    func testPopoverDelegateReportsNativeClose() {
        let closed = expectation(description: "Native/transient popover close resets view state")
        let observer = NotificationCenter.default.addObserver(forName: .panelDidHide, object: nil, queue: .main) { _ in closed.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }
        // Do not launch the App or initialize its production services.
        AppDelegate().popoverDidClose(Notification(name: NSPopover.didCloseNotification))
        wait(for: [closed], timeout: 1)
    }

    @MainActor
    func testPopoverDelegateReportsBeforeNativeShow() {
        let preparing = expectation(description: "History refresh starts before the popover is shown")
        let prematureShow = expectation(description: "Will-show must not report presentation completed")
        prematureShow.isInverted = true
        let observers = [
            NotificationCenter.default.addObserver(forName: .panelWillShow, object: nil, queue: .main) { _ in preparing.fulfill() },
            NotificationCenter.default.addObserver(forName: .panelDidShow, object: nil, queue: .main) { _ in prematureShow.fulfill() }
        ]
        defer { observers.forEach { NotificationCenter.default.removeObserver($0) } }
        AppDelegate().popoverWillShow(Notification(name: NSPopover.willShowNotification))
        wait(for: [preparing, prematureShow], timeout: 0.1)
    }

    @MainActor
    func testPopoverDelegateReportsNativeShow() {
        let shown = expectation(description: "Native popover show loads current history")
        let observer = NotificationCenter.default.addObserver(forName: .panelDidShow, object: nil, queue: .main) { _ in shown.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }
        AppDelegate().popoverDidShow(Notification(name: NSPopover.didShowNotification))
        wait(for: [shown], timeout: 1)
    }
}
