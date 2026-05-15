import AppKit
import SwiftUI

extension Notification.Name {
    static let requestClosePopover = Notification.Name("HistoryClipboardRequestClosePopover")
    static let popoverResize = Notification.Name("HistoryClipboardPopoverResize")
    static let resignSearchBar = Notification.Name("HistoryClipboardResignSearchBar")
}

struct ContentView: View {
    @State private var items: [ClipboardItem] = []
    @State private var searchText = ""
    @State private var showSettings = false
    @State private var animateIn = false
    @State private var pastedItemId: Int64?

    private let databaseManager = DatabaseManager.shared

    var body: some View {
        ZStack {
            if showSettings {
                SettingsView(onBack: {
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 25)) {
                        showSettings = false
                    }
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
                .frame(width: 300)
            } else {
                mainContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .frame(width: 360, height: 500)
            }

        }
        .padding(4)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    NotificationCenter.default.post(name: .resignSearchBar, object: nil)
                }
        )
        .animation(.interpolatingSpring(stiffness: 300, damping: 25), value: showSettings)
        .onChange(of: showSettings) { _, isSettings in
            let size = isSettings ? NSSize(width: 310, height: 240) : NSSize(width: 360, height: 500)
            NotificationCenter.default.post(name: .popoverResize, object: nil, userInfo: ["size": size])
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            LiquidSearchBar(text: $searchText)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if filteredItems.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems, id: \.id) { item in
                            ClipboardCardView(
                                item: item,
                                isPasting: pastedItemId == item.id,
                                onTap: { pasteItem(item) },
                                onPin: { togglePin(item) },
                                onDelete: { deleteItem(item) }
                            )
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Divider()
                .opacity(0.3)

            HStack {
                Text("共 \(filteredItems.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button { confirmClearAll() } label: {
                    Text("清除")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(height: 28)
                        .padding(.horizontal, 14)
                        .background(Capsule().glassEffect())
                        .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 25)) { showSettings.toggle() }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().glassEffect())
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .scaleEffect(animateIn ? 1 : 0.92, anchor: .top)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : -20)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: animateIn)
        .onAppear { loadItems() }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in
            loadItems()
            animateIn = true
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidHide)) { _ in
            animateIn = false
        }
    }

    // MARK: - Data

    private var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { item in
            item.content?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clipboard")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.4))
            Text(searchText.isEmpty ? "暂无剪贴板历史" : "未找到匹配内容")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func loadItems() {
        items = (try? databaseManager.fetchAll()) ?? []
    }

    // MARK: - Actions

    private func pasteItem(_ item: ClipboardItem) {
        pastedItemId = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch item.type {
            case "text":
                if let content = item.content {
                    PasteboardService.shared.write(text: content)
                }
            case "image":
                if let path = item.imagePath, let image = NSImage(contentsOfFile: path) {
                    PasteboardService.shared.write(image: image)
                }
            default:
                break
            }
            pastedItemId = nil
            NotificationCenter.default.post(name: .requestClosePopover, object: nil)
        }
    }

    private func togglePin(_ item: ClipboardItem) {
        guard let id = item.id else { return }
        do {
            if item.isPinned {
                try databaseManager.unpin(id: id)
            } else {
                try databaseManager.pin(id: id)
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { loadItems() }
        } catch {
            NSLog("HistoryClipboard: pin error: \(error)")
        }
    }

    private func deleteItem(_ item: ClipboardItem) {
        guard let id = item.id else { return }
        do {
            if item.type == "image", let path = item.imagePath {
                try? FileManager.default.removeItem(atPath: path)
            }
            try databaseManager.delete(id: id)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { loadItems() }
        } catch {
            NSLog("HistoryClipboard: delete error: \(error)")
        }
    }

    private func confirmClearAll() {
        let alert = NSAlert()
        alert.messageText = "确认清除"
        alert.informativeText = "将删除所有非置顶的剪贴板记录，此操作不可撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "清除")
        if alert.runModal() == .alertSecondButtonReturn {
            clearAll()
        }
    }

    private func clearAll() {
        do {
            let removed = try databaseManager.deleteAllNonPinned()
            for item in removed where item.type == "image" {
                if let path = item.imagePath {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { loadItems() }
        } catch {
            NSLog("HistoryClipboard: clear error: \(error)")
        }
    }
}
