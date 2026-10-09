import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let onBack: () -> Void
    private let appSettings = AppSettings.shared
    private let loginItems = LoginItemManager.shared

    var body: some View {
        @Bindable var settings = appSettings
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回历史记录")
                .help("返回历史记录")
                Text("设置").font(.headline)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("剪贴板保留时长").font(.subheadline)
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 10) {
                            ForEach(RetentionDays.allCases, id: \.rawValue) { days in
                                let isSelected = settings.retentionDays == days
                                Button { settings.retentionDays = days } label: {
                                    Text(days.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 38)
                                        .glassEffect(
                                            isSelected ? .regular.tint(Color.accentColor.opacity(0.12)).interactive() : .regular.interactive(),
                                            in: RoundedRectangle(cornerRadius: 12)
                                        )
                                        .contentShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("保留 \(days.title)")
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("剪贴板保留时长")
                    .onChange(of: settings.retentionDays) { _, _ in CleanupService.shared.performCleanup() }
                    Text("超过保留时长的非置顶内容将被自动清除")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Toggle("暂停记录剪贴板", isOn: $settings.isMonitoringPaused)
                        .onChange(of: settings.isMonitoringPaused) { _, _ in
                            ClipboardMonitor.shared.discardCurrentChange()
                        }
                    Text("带敏感、临时或自动生成标记的内容不会保存。未标记的密码仍可能被记录。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("不记录这些应用（每行一个 Bundle ID）").font(.subheadline)
                    TextEditor(text: $settings.excludedApplicationIDs)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .scrollContentBackground(.hidden)
                        .frame(height: 72)
                        .padding(8)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                                .allowsHitTesting(false)
                        }
                        .accessibilityLabel("排除的应用 Bundle ID")
                        .onChange(of: settings.excludedApplicationIDs) { _, _ in ClipboardMonitor.shared.discardCurrentChange() }
                    Text("例如 com.apple.Terminal；按采集时的前台应用判断，不保证识别后台复制来源。")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Toggle("开机自启", isOn: Binding(get: { loginItems.isEnabled }, set: { loginItems.setEnabled($0) }))
                        .disabled(loginItems.status == .notFound)
                    Text(loginItems.statusDescription).font(.caption).foregroundStyle(.secondary)
                    if loginItems.status == .requiresApproval {
                        Button("打开系统登录项设置") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(.glass)
                    }
                }
            }
            // Keep the content width while moving the indicator into the outer gutter.
            .contentMargins(.trailing, 12, for: .scrollContent)
            .padding(.trailing, -12)
        }
        .padding(16)
        .onAppear { loginItems.refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItems.refreshStatus() }
        .alert("开机自启设置失败", isPresented: Binding(get: { loginItems.errorMessage != nil }, set: { if !$0 { loginItems.clearError() } })) {
            Button("好", role: .cancel) { loginItems.clearError() }
        } message: { Text(loginItems.errorMessage ?? "") }
    }
}
