import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let onBack: () -> Void

    @State private var selectedDays: RetentionDays

    private let appSettings = AppSettings.shared

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        _selectedDays = State(initialValue: AppSettings.shared.retentionDays)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { onBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().glassEffect())
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)

                Text("设置")
                    .font(.headline)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("剪贴板保留时长")
                    .font(.subheadline)

                HStack(spacing: 0) {
                    ForEach(RetentionDays.allCases, id: \.rawValue) { option in
                        Text(option.title)
                            .font(.system(size: 13, weight: selectedDays == option ? .medium : .regular))
                            .foregroundColor(selectedDays == option ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.interpolatingSpring(stiffness: 300, damping: 25)) {
                                    selectedDays = option
                                }
                                appSettings.retentionDays = option
                                CleanupService.shared.performCleanup()
                            }
                    }
                }
                .padding(4)
                .background(
                    GeometryReader { geometry in
                        let count = CGFloat(RetentionDays.allCases.count)
                        let contentW = geometry.size.width - 8
                        let segW = contentW / count
                        let idx = CGFloat(RetentionDays.allCases.firstIndex(of: selectedDays) ?? 0)
                        Capsule()
                            .glassEffect()
                            .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                            .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 0.5))
                            .frame(width: segW, height: geometry.size.height - 8)
                            .offset(x: 4 + idx * segW, y: 4)
                    }
                )

                Text("超过保留时长的非置顶内容将被自动清除")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("开机自启")
                    .font(.subheadline)

                Text("App 会在系统登录时自动启动")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    do { try SMAppService.mainApp.register() }
                    catch { NSLog("HistoryClipboard: register error: \(error)") }
                } label: {
                    Text("注册开机启动")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(height: 28)
                        .padding(.horizontal, 14)
                        .background(Capsule().glassEffect())
                        .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

}
