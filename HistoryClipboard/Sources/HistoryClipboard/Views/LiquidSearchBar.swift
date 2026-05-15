import SwiftUI

struct LiquidSearchBar: View {
    @Binding var text: String
    @State private var isExpanded = false

    private let popSpring = Animation.interpolatingSpring(stiffness: 200, damping: 10)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isExpanded ? .primary : .secondary)
                .onTapGesture { isExpanded = true }

            SearchTextField(text: $text, isEditing: $isExpanded)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().glassEffect())
        .overlay(
            Capsule()
                .stroke(isExpanded ? Color.white.opacity(0.5) : Color.white.opacity(0.2),
                        lineWidth: isExpanded ? 0.8 : 0.3)
        )
        .scaleEffect(isExpanded ? 1.05 : 1.0)
        .offset(y: isExpanded ? -4 : 0)
        .shadow(color: isExpanded ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                radius: isExpanded ? 8 : 4, x: 0, y: 2)
        .animation(popSpring, value: isExpanded)
        .onReceive(NotificationCenter.default.publisher(for: .panelDidHide)) { _ in
            isExpanded = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .resignSearchBar)) { _ in
            withAnimation(popSpring) { isExpanded = false }
        }
    }
}

// MARK: - AppKit bridge

private final class SearchField: NSTextField {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

private struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool

    func makeNSView(context: Context) -> SearchField {
        let tf = SearchField()
        tf.isBordered = false
        tf.backgroundColor = .clear
        tf.focusRingType = .none
        tf.delegate = context.coordinator
        tf.placeholderString = "搜索..."
        tf.refusesFirstResponder = false
        tf.onMouseDown = { DispatchQueue.main.async { context.coordinator.onClick() } }
        return tf
    }

    func updateNSView(_ nsView: SearchField, context: Context) {
        let isFR = nsView.window?.firstResponder === nsView
        if !isFR, nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: SearchTextField
        init(_ parent: SearchTextField) { self.parent = parent }

        func onClick() {
            parent.isEditing = true
        }

        func controlTextDidChange(_ obj: Notification) {
            if let tf = obj.object as? NSTextField {
                let v = tf.stringValue
                DispatchQueue.main.async { self.parent.text = v }
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            DispatchQueue.main.async { self.parent.isEditing = true }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            DispatchQueue.main.async { self.parent.isEditing = false }
        }
    }
}
