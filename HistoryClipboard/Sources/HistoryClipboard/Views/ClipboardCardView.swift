import AppKit
import SwiftUI

struct ClipboardCardView: View {
    let item: ClipboardItem
    var isPasting = false
    var onTap: () -> Void = {}
    var onPin: () -> Void = {}
    var onDelete: () -> Void = {}
    @State private var thumbnail: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    contentPreview
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(formatTimestamp(now: context.date)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onKeyPress(.return) { onTap(); return .handled }
            .help("复制到剪贴板")
            .accessibilityLabel(item.type == "image" ? "复制图片" : "复制：\(String((item.content ?? "").prefix(100)))")

            VStack(spacing: 8) {
                Button(action: onPin) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .foregroundStyle(item.isPinned ? Color.accentColor : Color.primary)
                        .frame(width: 28, height: 28)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isPinned ? "取消置顶" : "置顶")
                .help(item.isPinned ? "取消置顶" : "置顶")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("删除记录").help("删除记录")
            }
        }
        .padding(12)
        .scaleEffect(isPasting ? 0.95 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPasting)
        .task(id: item.imagePath) {
            thumbnail = nil
            guard item.type == "image", let path = item.imagePath else { return }
            do {
                let data = try await ThumbnailCache.shared.thumbnail(path: path)
                guard !Task.isCancelled else { return }
                thumbnail = NSImage(data: data)
            } catch { /* Missing/corrupt images retain a placeholder; copying reports a concrete error. */ }
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case "text":
            Text(item.content ?? "").font(.body).foregroundStyle(.primary)
                .lineLimit(2).multilineTextAlignment(.leading)
                .onDrag { dragProvider }
        case "image":
            HStack(spacing: 8) {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                        .frame(width: 40, height: 40).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
                Text("图片").font(.body).foregroundStyle(.secondary)
            }
            .onDrag { dragProvider }
        default: Text("不支持的内容").foregroundStyle(.secondary)
        }
    }

    private var dragProvider: NSItemProvider {
        if item.type == "text" { return NSItemProvider(object: (item.content ?? "") as NSString) }
        if let path = item.imagePath { return NSItemProvider(object: URL(fileURLWithPath: path) as NSURL) }
        return NSItemProvider()
    }

    private func formatTimestamp(now: Date) -> String {
        let diff = max(0, now.timeIntervalSince1970 - item.timestamp)
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(Int(diff / 60)) 分钟前" }
        if diff < 86400 { return "\(Int(diff / 3600)) 小时前" }
        return "\(Int(diff / 86400)) 天前"
    }
}
