import SwiftUI
import AppKit
import ServiceManagement

extension Notification.Name {
    static let panelWillShow = Notification.Name("HistoryClipboardPanelWillShow")
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try DatabaseManager.shared.setup()
        } catch {
            NSLog("HistoryClipboard: DB error: \(error)")
            let alert = NSAlert()
            alert.messageText = "无法打开剪贴板数据库"
            alert.informativeText = "应用未启动剪贴板采集或自动清理，也不会重置历史数据。\n请检查磁盘空间和数据目录权限后重试。\n\n\(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "退出")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        ClipboardMonitor.shared.start()
        CleanupService.shared.start()
        setupStatusItem()
        setupPopover()

        LoginItemManager.shared.prepareDefaultRegistration()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRequestClose),
            name: .requestClosePopover,
            object: nil
        )

    }

    private lazy var statusMenu: NSMenu = {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let pause = NSMenuItem(title: "暂停记录", action: #selector(toggleMonitoringPause), keyEquivalent: "")
        pause.target = self
        pause.tag = 1
        menu.addItem(pause)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 History Clipboard", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
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
        // Animate both presentation and native transient dismissal without a
        // second SwiftUI entrance animation that delays the content.
        popover?.animates = true
        popover?.delegate = self

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
            statusMenu.item(withTag: 1)?.title = AppSettings.shared.isMonitoringPaused ? "继续记录" : "暂停记录"
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
        } else {
            // A key window alone does not activate a menu-bar-only app. Without
            // activation, the first click inside can be consumed by activation.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @MainActor @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func handleRequestClose() { popover?.close() }

    @objc private func openSettings() {
        guard let popover, let button = statusItem?.button else { return }
        NSApp.activate()
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        popover.contentViewController?.view.window?.makeKey()
        NotificationCenter.default.post(name: .requestShowSettings, object: nil)
    }

    @objc private func toggleMonitoringPause() {
        AppSettings.shared.isMonitoringPaused.toggle()
        ClipboardMonitor.shared.discardCurrentChange()
    }

    func popoverWillShow(_ notification: Notification) {
        // Start the asynchronous history refresh before presentation, not after it.
        NotificationCenter.default.post(name: .panelWillShow, object: nil)
    }

    func popoverDidShow(_ notification: Notification) {
        NotificationCenter.default.post(name: .panelDidShow, object: nil)
    }

    func popoverDidClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .panelDidHide, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stop()
        CleanupService.shared.stop()
        NotificationCenter.default.removeObserver(self)
    }
}
