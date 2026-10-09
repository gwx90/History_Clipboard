import AppKit
import SwiftUI

extension Notification.Name {
    static let requestClosePopover = Notification.Name("HistoryClipboardRequestClosePopover")
    static let requestShowSettings = Notification.Name("HistoryClipboardRequestShowSettings")
    static let resignSearchBar = Notification.Name("HistoryClipboardResignSearchBar")
}

struct ContentView: View {
    private enum HistoryMutation { case pin, delete, clear }

    @State private var model = HistoryViewModel()
    @State private var showSettings = false
    @State private var isPanelVisible = false
    @State private var pastedItemId: Int64?
    @State private var isMutating = false
    @State private var mutationStyle = HistoryMutation.delete
    @State private var errorMessage: String?
    @State private var showClearConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if showSettings {
                SettingsView(onBack: { showSettings = false })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                mainContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(4)
        .frame(width: 360, height: 500)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { resignSearch() }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSettings)
        .disabled(showClearConfirmation)
        .accessibilityHidden(showClearConfirmation)
        .overlay {
            if showClearConfirmation {
                ZStack {
                    Color.black.opacity(0.12)
                        .contentShape(Rectangle())
                        .onTapGesture { dismissClearConfirmation() }
                        .accessibilityHidden(true)
                    ClearHistoryConfirmationView(
                        onCancel: dismissClearConfirmation,
                        onConfirm: {
                            guard showClearConfirmation, !isMutating, pastedItemId == nil else { return }
                            dismissClearConfirmation()
                            mutate(.clear) { try await HistoryStore.shared.clearNonPinned() }
                        }
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.25, dampingFraction: 0.85), value: showClearConfirmation)
        .onReceive(NotificationCenter.default.publisher(for: .requestShowSettings)) { _ in showSettings = true }
        .onChange(of: showSettings) { _, value in
            if value { resignSearch() }
            model.setVisible(isPanelVisible && !value)
        }
        .onChange(of: model.searchText) { _, _ in model.reload(debounce: true) }
        .onReceive(NotificationCenter.default.publisher(for: .panelWillShow)) { _ in
            isPanelVisible = true
            model.setVisible(!showSettings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidHide)) { _ in
            isPanelVisible = false
            showClearConfirmation = false
            model.setVisible(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardHistoryDidChange).receive(on: RunLoop.main)) { _ in
            // Commit notifications can arrive before the local operation returns.
            model.reload(animation: isMutating ? mutationAnimation : nil)
        }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            LiquidSearchBar(text: $model.searchText)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            historyContent
                .contentShape(Rectangle())
                // Simultaneous recognition preserves copying and all button actions.
                .simultaneousGesture(TapGesture().onEnded { resignSearch() })
        }
    }

    private var historyContent: some View {
        VStack(spacing: 0) {
            if AppSettings.shared.isMonitoringPaused {
                statusLine("剪贴板记录已暂停", symbol: "pause.circle")
            } else if let error = ClipboardMonitor.shared.lastError {
                statusLine(error, symbol: "exclamationmark.triangle")
            }
            if LoginItemManager.shared.errorMessage != nil {
                statusLine("开机自启设置失败，请到设置中重试。", symbol: "exclamationmark.triangle")
            }
            if let error = model.loadError {
                HStack {
                    Text("读取失败：\(error)").font(.caption)
                    Button("重试") { model.reload() }.buttonStyle(.glass)
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
            }

            // Keep the list mounted even when the last item is removed, so its
            // removal transition can finish before the empty state settles in.
            ZStack {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.items, id: \.id) { item in
                            ClipboardCardView(item: item, isPasting: pastedItemId == item.id,
                                onTap: { pasteItem(item) }, onPin: { togglePin(item) }, onDelete: { deleteItem(item) })
                                .disabled(isMutating || pastedItemId != nil)
                                .transition(rowTransition)
                                .onAppear { if item.id == model.items.last?.id { model.loadMore() } }
                        }
                        if model.canLoadMore {
                            Button("加载更多") { model.loadMore() }
                                .buttonStyle(.glass).disabled(model.isLoading)
                        }
                        if model.isLoading && !model.items.isEmpty { ProgressView().controlSize(.small) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .allowsHitTesting(!model.items.isEmpty)
                .accessibilityHidden(model.items.isEmpty)

                if model.items.isEmpty {
                    Group {
                        if model.isLoading { ProgressView() }
                        else { emptyState }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
            Divider().opacity(0.3)
            HStack {
                Text("共 \(model.totalCount) 条").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("清除", role: .destructive) { confirmClearAll() }
                    .foregroundStyle(.red)
                    .buttonStyle(.glass).disabled(isMutating || pastedItemId != nil)
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.glass).accessibilityLabel("设置").help("设置")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private var mutationAnimation: Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        switch mutationStyle {
        case .pin: return .spring(response: 0.32, dampingFraction: 0.82)
        case .delete: return .easeInOut(duration: 0.22)
        case .clear: return .easeInOut(duration: 0.28)
        }
    }

    private var rowTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let removal: AnyTransition = mutationStyle == .clear
            ? .opacity.combined(with: .scale(scale: 0.96))
            : .opacity.combined(with: .move(edge: .trailing))
        return .asymmetric(insertion: .opacity, removal: removal)
    }

    private func statusLine(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: model.loadError == nil ? "clipboard" : "exclamationmark.triangle")
                .font(.system(size: 36)).foregroundStyle(.secondary)
            Text(model.loadError != nil ? "无法读取历史记录" : (model.searchText.isEmpty ? "暂无剪贴板历史" : "未找到匹配内容"))
                .font(.body).foregroundStyle(.secondary)
        }
    }

    private func pasteItem(_ item: ClipboardItem) {
        guard let id = item.id, pastedItemId == nil else { return }
        pastedItemId = id
        Task {
            defer { pastedItemId = nil }
            do {
                let content = try await HistoryStore.shared.pasteContent(id: id)
                switch content {
                case .text(let text): try PasteboardService.shared.write(text: text)
                case .image(let data): try PasteboardService.shared.write(pngData: data)
                }
                NotificationCenter.default.post(name: .requestClosePopover, object: nil)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func togglePin(_ item: ClipboardItem) {
        guard let id = item.id else { return }
        mutate(.pin) { try await HistoryStore.shared.setPinned(id: id, isPinned: !item.isPinned) }
    }

    private func deleteItem(_ item: ClipboardItem) {
        guard let id = item.id else { return }
        mutate(.delete) { try await HistoryStore.shared.delete(id: id) }
    }

    private func confirmClearAll() {
        guard !isMutating, pastedItemId == nil else { return }
        resignSearch()
        showClearConfirmation = true
    }

    private func resignSearch() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        NotificationCenter.default.post(name: .resignSearchBar, object: nil)
    }

    private func dismissClearConfirmation() {
        showClearConfirmation = false
    }

    private func mutate(_ style: HistoryMutation, _ operation: @escaping @MainActor () async throws -> Void) {
        guard !isMutating else { return }
        mutationStyle = style
        isMutating = true
        Task {
            defer { isMutating = false }
            do {
                try await operation()
                await model.reloadAndWait(animation: mutationAnimation)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
