import SwiftUI

struct LiquidSearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isFocused ? .primary : .secondary)
                .accessibilityHidden(true)

            TextField("搜索...", text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFocused)
                .accessibilityLabel("搜索剪贴板历史")
                .onKeyPress(.escape) {
                    isFocused = false
                    return .handled
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
                .help("清空搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassEffect(.regular.interactive(), in: Capsule())
        .contentShape(Capsule())
        .simultaneousGesture(TapGesture().onEnded { isFocused = true })
        .scaleEffect(isFocused && !reduceMotion ? 1.025 : 1)
        .offset(y: isFocused && !reduceMotion ? -2 : 0)
        .shadow(color: .black.opacity(isFocused ? 0.12 : 0.06),
                radius: isFocused ? 6 : 3, y: isFocused ? 3 : 1)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.25, dampingFraction: 0.82), value: isFocused)
        .onReceive(NotificationCenter.default.publisher(for: .panelDidHide)) { _ in
            isFocused = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .resignSearchBar)) { _ in
            isFocused = false
        }
    }
}
