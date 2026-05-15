# 技术方案与架构说明

## 技术栈

| 层面 | 技术选型 | 版本要求 |
|------|----------|----------|
| 开发语言 | Swift 6 | - |
| UI 框架 | SwiftUI | macOS 26+ |
| 数据库 | GRDB (SQLite) | 7.x |
| 包管理 | Swift Package Manager | - |
| 最低部署 | macOS 26 | Darwin 25.x |
| 目标平台 | macOS (Designed for Mac) | - |

## 项目结构

```
HistoryClipboard/
├── HistoryClipboardApp.swift          - @main App 入口
├── Managers/
│   ├── MenuBarManager.swift           - NSStatusBar 管理 + NSPopover
│   ├── ClipboardMonitor.swift         - 0.5s Timer 轮询粘贴板变化
│   └── DatabaseManager.swift          - GRDB 数据库队列、建表、CRUD
├── Models/
│   └── ClipboardItem.swift            - Codable + FetchableRecord + PersistableRecord
├── Views/
│   ├── ContentView.swift              - 主面板根视图
│   ├── ClipboardCardView.swift        - 单条历史卡片组件
│   ├── SearchBarView.swift            - 搜索输入组件
│   └── SettingsView.swift             - 设置面板
├── Services/
│   ├── PasteboardService.swift        - NSPasteboard 读写封装
│   └── CleanupService.swift           - 过期清理逻辑
└── AppSettings.swift                  - @AppStorage 用户设置封装
```

## 架构模式

采用 **MVVM 简化模式**（适合小型 SwiftUI App）：

- **Model**：ClipboardItem（GRDB Record）
- **ViewModel**：DatabaseManager 提供 `@Observable` 数据观察，ContentView 通过 `@Query` 或手动订阅刷新
- **View**：SwiftUI 视图层，通过 `@State` / `@Environment` 消费数据

数据流向：
```
NSPasteboard → ClipboardMonitor → DatabaseManager.write(item)
                                        ↓
ContentView ← @Query/Observable ← DatabaseManager.read()
```

## 数据库设计

表名：`clipboard_items`

```sql
CREATE TABLE clipboard_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL CHECK(type IN ('text', 'image')),
    content TEXT,
    imagePath TEXT,
    timestamp REAL NOT NULL,
    isPinned INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_timestamp ON clipboard_items(timestamp);
CREATE INDEX idx_type ON clipboard_items(type);
```

## 文件存储路径

- 数据库文件：`~/Library/Application Support/HistoryClipboard/clipboard.db`
- 图片存储：`~/Library/Application Support/HistoryClipboard/Images/{uuid}.png`
- 设置存储：`UserDefaults.standard`（通过 `@AppStorage`）

## 剪贴板轮询机制

```
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    let newCount = NSPasteboard.general.changeCount
    guard newCount != lastChangeCount else { return }
    lastChangeCount = newCount
    // 读取内容 → 去重检查 → 写入 DB
}
```

去重：比较最新一条记录的内容，与当前粘贴板内容相同则跳过。

## 依赖

通过 Swift Package Manager 引入：
- `https://github.com/groue/GRDB.swift` — SQLite 数据库框架

## 安全与隐私

- 所有数据存储于本地，无网络访问
- 不需要网络权限
- 不需要辅助功能权限（仅读取通用粘贴板，不访问其他 App 的内容）
- 开机自启通过 SMAppService 原生 API，不需要特殊权限
