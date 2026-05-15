import SwiftUI
import AppKit
import ServiceManagement

extension Notification.Name {
    static let panelDidShow = Notification.Name("HistoryClipboardPanelDidShow")
    static let panelDidHide = Notification.Name("HistoryClipboardPanelDidHide")
}

@main
struct HistoryClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try DatabaseManager.shared.setup()
        } catch {
            NSLog("HistoryClipboard: DB error: \(error)")
        }
        ClipboardMonitor.shared.start()
        CleanupService.shared.start()
        setupStatusItem()
        setupPopover()

        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("HistoryClipboard: SMAppService error: \(error)")
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRequestClose),
            name: .requestClosePopover,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResizePopover(_:)),
            name: .popoverResize,
            object: nil
        )
    }

    private let statusMenu: NSMenu = {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "退出 History Clipboard",
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))
        return menu
    }()

    @MainActor private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "clipboard.fill",
                accessibilityDescription: "History Clipboard"
            )
            button.action = #selector(statusButtonClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @MainActor private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 360, height: 500)
        popover?.behavior = .transient
        popover?.appearance = NSAppearance(named: .aqua)

        let hostingController = NSHostingController(rootView: ContentView())
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover?.contentViewController = hostingController

        // Pre-load to establish ViewBridge connection
        _ = hostingController.view
        hostingController.view.needsLayout = true
        hostingController.view.layoutSubtreeIfNeeded()
    }

    @MainActor @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            statusMenu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.height + 4),
                in: sender
            )
        } else {
            togglePopover()
        }
    }

    @MainActor @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.close()
            NotificationCenter.default.post(name: .panelDidHide, object: nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NotificationCenter.default.post(name: .panelDidShow, object: nil)
        }
    }

    @MainActor @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @MainActor @objc private func handleRequestClose() {
        popover?.close()
        NotificationCenter.default.post(name: .panelDidHide, object: nil)
    }

    @MainActor @objc private func handleResizePopover(_ notification: Notification) {
        if let size = notification.userInfo?["size"] as? NSSize {
            popover?.contentSize = size
        }
    }
}
