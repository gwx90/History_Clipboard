# CLAUDE.md — History Clipboard 项目工作指引

## 项目简介

History Clipboard 是一款 macOS 菜单栏剪贴板历史管理工具，采用 Liquid Glass 设计风格，SwiftUI + GRDB 技术栈。

## 标准文件索引

项目实施前，务必先阅读以下规范文件：

| 文件 | 路径 | 用途 |
|------|------|------|
| 功能需求 | [docs/requirements.md](docs/requirements.md) | 所有功能需求规格，任何实现必须对齐此文件 |
| 技术方案 | [docs/tech-spec.md](docs/tech-spec.md) | 技术栈、架构、数据库设计、文件路径约定 |
| 设计规范 | [docs/design-spec.md](docs/design-spec.md) | Liquid Glass UI 标准、材质、尺寸、字体规范 |
| 构建步骤 | [docs/build-steps.md](docs/build-steps.md) | 分 5 阶段实施步骤，每步的具体任务和验证标准 |

## 开发日志

每日开发结束时，自动在 [devlog/](devlog/) 创建 `YYYY-MM-DD.md`，格式如下：

```markdown
# YYYY-MM-DD 开发日志

## 已完成
- [具体完成的事项1]
- [具体完成的事项2]

## 待办
- [待完成的事项1]
- [待完成的事项2]

## 备注
（遇到的问题、决策、注意事项等）
```

## 工作原则

1. **严格按阶段推进**：完成一个阶段的所有步骤并验证通过后，才能进入下一阶段
2. **每步验证**：每个步骤完成后必须编译通过（`xcodebuild` 或 Xcode Run），功能验证通过
3. **每日记录**：每次开发会话结束时，更新 devlog
4. **不跳步、不批量**：不跳过构建步骤中的任何子步骤，不做批量的未经验证的改动
5. **参考规范**：任何 UI 实现前查阅 design-spec.md，任何数据操作查阅 tech-spec.md

## 关键约束

- macOS 目标版本：macOS 26（Darwin 25.x）
- UI 必须使用 Liquid Glass 材质（`.glass`, `.regularMaterial`, `.thinMaterial`）
- 数据库路径：`~/Library/Application Support/HistoryClipboard/clipboard.db`
- 图片存储路径：`~/Library/Application Support/HistoryClipboard/Images/`
- 剪贴板轮询间隔：0.5 秒
- 默认保留时长：3 天

## 项目文件位置

- Xcode 项目：`/Users/jackgu/History _Clipboard/HistoryClipboard/`
- 规范文档：`/Users/jackgu/History _Clipboard/docs/`
- 开发日志：`/Users/jackgu/History _Clipboard/devlog/`
