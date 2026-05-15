# 分阶段构建步骤

> **核心原则**：每步实施 → 验证通过 → 记录日志 → 再推进下一步。不跳步、不批量推进。

---

## 阶段 1：项目骨架 + 数据层

**目标**：Xcode 项目可编译运行，数据库能正常读写。

### 步骤 1.1：创建 Xcode 项目
- Xcode → New Project → macOS → SwiftUI App
- Product Name: `HistoryClipboard`
- 保存到 `/Users/jackgu/History _Clipboard/HistoryClipboard/`
- 最低部署目标：macOS 26

### 步骤 1.2：引入 GRDB 依赖
- File → Add Package Dependencies
- 搜索 `https://github.com/groue/GRDB.swift`
- 选择最新稳定版

### 步骤 1.3：创建项目文件结构
在 Xcode 中创建以下 Group 和文件：
- Models/ClipboardItem.swift
- Managers/DatabaseManager.swift
- HistoryClipboardApp.swift（项目自带，修改入口）

### 步骤 1.4：实现 ClipboardItem 模型
- 定义符合 GRDB `FetchableRecord` + `PersistableRecord` 的结构体
- 字段：id, type, content, imagePath, timestamp, isPinned

### 步骤 1.5：实现 DatabaseManager
- 单例模式，持有 DatabaseQueue
- 建表方法（`createTableIfNeeded`）
- CRUD 方法：insert, fetchAll, search, delete, pin, unpin

### 步骤 1.6：编写单元测试
- 测试插入文字记录
- 测试插入图片记录
- 测试 fetchAll 排序（时间倒序 + 置顶优先）
- 测试搜索
- 测试删除
- 测试置顶/取消置顶

### 验证标准
- 所有单元测试通过
- 数据库文件在 Application Support 目录中正确创建

---

## 阶段 2：剪贴板监听 + 存储

**目标**：复制内容后自动存入数据库。

### 步骤 2.1：实现 PasteboardService
- `readFromPasteboard()` → String? / NSImage?
- `writeToPasteboard(text:)` → Void
- `writeToPasteboard(image:)` → Void

### 步骤 2.2：实现 ClipboardMonitor
- 持有 Timer，每 0.5s 触发
- 检测 `NSPasteboard.general.changeCount`
- 变化时调用 PasteboardService 读取内容
- 去重：与最新 DB 记录比较
- 文字：直接写入 ClipboardItem(type: "text")
- 图片：保存 PNG 文件到 Images 目录，写入 ClipboardItem(type: "image", imagePath:...)

### 步骤 2.3：App 启动时启动监听
- 在 App 的 `init()` 或 `applicationDidFinishLaunching` 中启动 ClipboardMonitor

### 验证标准
- 运行 App → Cmd+C 复制文字 → 数据库中出现新记录
- 复制图片（如截屏后 Cmd+C）→ 数据库中出现新记录，Images 目录有对应文件

---

## 阶段 3：菜单栏 + 主面板 UI

**目标**：点击菜单栏图标可弹出历史面板，Liquid Glass 风格。

### 步骤 3.1：实现 MenuBarManager
- 创建 NSStatusBar 图标（SF Symbol: `clipboard`）
- 点击图标时 toggle NSPopover
- Popover 包含 ContentView

### 步骤 3.2：实现 ContentView
- `@State` 持有 clipboardItems 列表
- `.onAppear` 从 DatabaseManager 加载数据
- List 视图，按 isPinned DESC，timestamp DESC 排列
- 面板 `.glass` 背景

### 步骤 3.3：实现 ClipboardCardView
- 根据 ClipboardItem.type 显示文字或图片预览
- 玻璃态材质背景（`.thinMaterial` / `.regularMaterial`）
- 右侧操作按钮占位（阶段 4 连接实际功能）

### 步骤 3.4：实现 SearchBarView
- HStack: 搜索图标 + TextField
- 玻璃态材质输入框

### 验证标准
- App 运行后菜单栏出现图标
- 点击图标弹出面板，看到已有的历史记录卡片
- UI 呈现 Liquid Glass 玻璃质感

---

## 阶段 4：搜索 + 置顶 + 删除 + 粘贴

**目标**：所有核心交互功能可用。

### 步骤 4.1：搜索功能
- SearchBarView 绑定 `@State searchText`
- 输入变化时调用 DatabaseManager.search(keyword:)
- 列表实时更新

### 步骤 4.2：粘贴功能
- 点击文字卡片 → PasteboardService.writeToPasteboard(text:)
- 点击图片卡片 → PasteboardService.writeToPasteboard(image:)
- 写入后关闭 Popover

### 步骤 4.3：置顶功能
- 点击置顶按钮 → DatabaseManager.pin(id:) / unpin(id:)
- 列表自动重排

### 步骤 4.4：删除功能
- 点击删除按钮 → 确认弹窗（或直接删除）
- DatabaseManager.delete(id:)
- 图片类型同时删除文件
- 列表实时更新

### 验证标准
- 搜索：输入关键词，列表正确过滤
- 粘贴：点击卡片，Cmd+V 成功粘贴
- 置顶：卡片移至顶部，再次点击取消置顶
- 删除：卡片消失，数据库和文件系统同步清除

---

## 阶段 5：保留时长设置 + 自动清理 + 开机自启

**目标**：完整产品闭环。

### 步骤 5.1：实现 AppSettings
- 使用 `@AppStorage` 存储保留天数
- 枚举：1 天、3 天（默认）、5 天

### 步骤 5.2：实现 SettingsView
- 保留时长选择器（Picker 或 SegmentedControl）
- 当前条目计数显示

### 步骤 5.3：实现 CleanupService
- 计算截止时间 = 当前时间 - 保留天数 × 86400
- 查询 timestamp < 截止时间 AND isPinned = 0 的记录
- 批量删除（图片类型同时删文件）
- 触发时机：App 启动时 + 每 1 小时定时器

### 步骤 5.4：实现开机自启
- 在 App 启动时调用 `SMAppService.mainApp.register()`
- 第一次启动时请求用户授权

### 验证标准
- 切换保留时长 → 设置正确保存
- 模拟过期数据 → 重启 App → 非置顶过期条目被清除
- 重启电脑 → App 自动启动，菜单栏出现图标

---

## 最终整体验证

1. 编译运行 → 菜单栏出现图标
2. Cmd+C 复制文字 → 面板中看到文字卡片
3. 复制图片 → 面板中看到图片预览卡片
4. 搜索框输入关键词 → 列表正确过滤
5. 点击卡片 → Cmd+V 粘贴成功
6. 置顶某条 → 保持在列表顶部
7. 删除某条 → 从列表消失
8. 设置保留 1 天 → 过期条目被清除，置顶条目保留
9. 重启电脑 → App 自动启动
