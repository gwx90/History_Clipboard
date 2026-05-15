# UI 设计规范

## 设计语言

采用 macOS 26 **Liquid Glass** 设计语言，核心特征：
- 半透明玻璃材质，有深度感和层次感
- 光影在表面流动的微动效
- 跟随系统浅色/深色模式自动适配
- 不使用自定义主题色，依靠系统材质本身呈现

## 面板规格

| 属性 | 值 |
|------|-----|
| 宽度 | 360pt |
| 高度 | 500pt（最大） |
| 背景 | `.glass` 材质 |
| 圆角 | 16pt（面板外围） |
| 阴影 | 系统默认 depth 阴影 |

## 搜索栏

| 属性 | 值 |
|------|-----|
| 高度 | 36pt |
| 背景 | `.regularMaterial` 叠加于 glass 之上 |
| 圆角 | 10pt |
| 左右边距 | 12pt |
| 顶部边距 | 12pt |
| Placeholder | "搜索..." |
| 图标 | 左侧放大镜 SF Symbol |

## 历史卡片

| 属性 | 值 |
|------|-----|
| 背景 | `.thinMaterial` 或 `.regularMaterial` |
| 圆角 | 12pt |
| 边距 | 水平 12pt，垂直 6pt（卡片间距） |
| 内边距 | 12pt |
| 最小高度 | 52pt |

### 文字卡片
- 左侧：文字预览，最多 2 行，SF Pro 正文，lineLimit(2)
- 右侧：相对时间标签 + 置顶图标按钮 + 删除图标按钮
- 文字颜色：primary（系统标签色）

### 图片卡片
- 左侧：图片缩略图，40×40pt，clipped，圆角 6pt
- 缩略图右侧：文字标签"图片"或图片尺寸信息
- 右侧：与文字卡片相同的操作按钮布局

### 置顶卡片
- 额外顶部边缘微光效果（Liquid Glass highlight）
- 背景略亮于普通卡片（`.regularMaterial` vs `.thinMaterial`）

## 操作图标

| 功能 | SF Symbol |
|------|-----------|
| 置顶/取消置顶 | `pin.fill` / `pin` |
| 删除 | `trash` |
| 搜索 | `magnifyingglass` |
| 设置 | `gearshape` |
| 状态栏图标 | `clipboard` 或自定义 |

## 底部状态栏

- 半透明分隔线（`.separator` 材质）
- 左侧：条目计数文字（如"共 23 条"），SF Pro 脚注，secondary 颜色
- 右侧：设置按钮（齿轮图标），点击切换到设置视图

## 颜色

- 不指定固定颜色值
- 所有元素使用系统语义色（primary, secondary, .separator 等）
- Liquid Glass 材质自动适配系统外观
- 唯一可定义的是强调色：系统默认蓝色（用于操作按钮的 active 态）

## 动效

- 面板弹出/收起：spring 动效（系统默认）
- 卡片出现/移除：`.transition(.opacity)` 或 `.transition(.move(edge: .top))`
- 搜索过滤：无动画（直切结果，保持性能）
- 置顶状态切换：卡片平滑移动到新位置

## 字体

全部使用系统 SF Pro，不自定义：
- 正文：`.body`
- 时间标签：`.caption`
- 搜索框：`.body`
- 计数：`.caption`
