<p align="center">
  <img src="HistoryClipboard/Assets/AppIcon.svg" alt="History Clipboard" width="128" />
</p>

# History Clipboard

macOS 菜单栏剪贴板历史管理工具。自动记录文字与图片，支持搜索、置顶和再次复制。采用 **Liquid Glass**、SwiftUI + GRDB，最低系统 macOS 26。

## 功能

- **自动记录** — 0.5 秒轮询，纯文本/富文本转纯文本、PNG/TIFF 图片，连续重复内容去重
- **历史浏览** — 360×500pt 面板，置顶优先、时间倒序，每页 100 条，可继续加载
- **全文搜索** — 后台查询，字面匹配（包括 `%`、`_`），取消过时搜索结果
- **一键回贴** — 点击卡片或聚焦卡片后回车，成功写回剪贴板才关闭面板，再 Cmd+V 粘贴；自身回写不重复记录
- **置顶、删除与清理** — 默认保留 3 天，可选 1/3/5 天，置顶不自动清理；图片删除失败有持久化任务重试
- **隐私控制** — 敏感/临时/自动生成标记过滤、暂停记录、前台应用 Bundle ID 排除
- **后台图片处理** — 原图编码/存储、缩略图下采样和缓存不在视图主线程执行
- **菜单与自启** — 右键提供设置、暂停/继续和退出；开机自启可关闭，显示真实系统状态和待批准提示
- **系统适配** — 跟随浅色/深色外观，原生按钮及无障碍标签

## 构建

1. 安装包含 macOS 26 SDK 的 Xcode。
2. 打开 `HistoryClipboard/HistoryClipboard.xcodeproj`，等待 GRDB 依赖解析。
3. ⌘R 运行；或在仓库根目录执行：

```bash
xcodebuild -project HistoryClipboard/HistoryClipboard.xcodeproj -scheme HistoryClipboard build
```

源码位于 `HistoryClipboard/Sources/HistoryClipboard/`；并发、数据库及存储说明见 [技术方案](docs/tech-spec.md)。

## 测试

在仓库根目录执行：

```bash
swift test --package-path HistoryClipboard
```

测试只使用独立内存/临时目录数据库、合成图片、独立命名剪贴板和隔离 UserDefaults，不访问正式历史或通用剪贴板，不注册真实系统登录项。覆盖初始化失败、存储补偿、删除重试、采集重试与取消、隐私过滤、分页/搜索、缩略图及登录项状态控制。

## 数据与隐私

| 内容 | 路径 |
|------|------|
| 数据库 | `~/Library/Application Support/HistoryClipboard/clipboard.db` |
| 图片 | `~/Library/Application Support/HistoryClipboard/Images/` |
| 设置 | UserDefaults |

数据仅存本地，无网络访问；**数据库和图片未加密**。

- 标记过滤不能识别所有密码：应用未提供敏感标记时，内容仍可能被记录。
- 应用排除按采集时的前台应用判断，不能保证识别后台复制来源。设置中每行填写一个 Bundle ID，例如 `com.apple.Terminal`。
- 暂停会丢弃当前变化并取消尚未提交的采集，恢复后不补录暂停时的内容；已经保存的历史不会因此删除。
- 单张源图片上限 50 MB / 4000 万像素，超限或无效图片不会保存，面板会显示提示。
- 图片存储失败会尝试补偿；异常退出留下的孤立 UUID PNG 经引用检查及 1 小时宽限后回收。置顶和仍有引用的图片不受影响。
- 开机自启首次默认尝试注册，后续保留用户选择；待批准时请使用设置中的系统登录项入口。

## 手动验收

请从 Xcode 构建的完整 App 验证：文字/图片复制回贴、搜索和分页、删除新建测试条目、置顶保留、暂停/恢复、深色模式、点击外部关闭后重开，以及系统登录项批准/关闭。自动化测试不替代真实系统登录或界面验收。

## 许可

MIT
