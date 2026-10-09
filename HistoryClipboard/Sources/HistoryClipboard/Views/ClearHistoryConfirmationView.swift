import SwiftUI

struct ClearHistoryConfirmationView: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @FocusState private var cancelIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认清除")
                .font(.headline)
            Text("将删除所有非置顶的剪贴板记录，此操作不可撤销。置顶记录会保留。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Spacer()
                Button(action: onCancel) {
                    Text("取消")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 64, height: 28)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .focused($cancelIsFocused)

                Button(role: .destructive, action: onConfirm) {
                    Text("清除")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(width: 64, height: 28)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除所有非置顶记录")
            }
        }
        .padding(20)
        .frame(width: 300)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .accessibilityAddTraits(.isModal)
        // Destructive clearing is never the default keyboard action.
        .onAppear { cancelIsFocused = true }
    }
}
