import AppKit
import SwiftUI

struct ClipboardCardView: View {
    let item: ClipboardItem
    var isPasting = false
    var onTap: () -> Void = {}
    var onPin: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Content preview
            contentPreview
                .frame(maxWidth: .infinity, alignment: .leading)

            // Action buttons
            VStack(spacing: 8) {
                Button { onPin() } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().glassEffect())
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)

                Button { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().glassEffect())
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .scaleEffect(isPasting ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPasting)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: - Content Preview

    @ViewBuilder
    private var contentPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            dragSource
            Text(formatTimestamp(item.timestamp))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var dragSource: some View {
        switch item.type {
        case "text":
            Text(item.content ?? "")
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
                .onDrag { dragProvider }

        case "image":
            HStack(spacing: 8) {
                if let imagePath = item.imagePath,
                   let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.secondary.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                }
                Text("图片")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onDrag { dragProvider }

        default:
            EmptyView()
        }
    }

    private var dragProvider: NSItemProvider {
        switch item.type {
        case "text":
            return NSItemProvider(object: (item.content ?? "") as NSString)
        case "image":
            if let path = item.imagePath {
                return NSItemProvider(object: URL(fileURLWithPath: path) as NSURL)
            }
            return NSItemProvider()
        default:
            return NSItemProvider()
        }
    }

    private func formatTimestamp(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let now = Date()
        let diff = now.timeIntervalSince(date)

        if diff < 60 {
            return "刚刚"
        } else if diff < 3600 {
            return "\(Int(diff / 60)) 分钟前"
        } else if diff < 86400 {
            return "\(Int(diff / 3600)) 小时前"
        } else {
            return "\(Int(diff / 86400)) 天前"
        }
    }
}
