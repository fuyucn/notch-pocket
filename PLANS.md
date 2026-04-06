# Notch Pocket — Plan 清单

> 每个 plan 对应一个可独立交付的功能模块，按依赖顺序排列。

## Plan 状态说明

| 状态 | 含义 |
|------|------|
| `in-progress` | 当前正在开发 |
| `planned` | 已规划，等待前置 plan 完成 |
| `done` | 已完成并合并至 main |

---

## Plan 列表

### Plan 1: 项目初始化 — `plan-1-project-setup`
**状态**: `in-progress`
**分支**: `plan-1-project-setup`
**目标**: 搭建项目骨架，包括 SPM 项目结构、基础 App 生命周期（AppDelegate）、菜单栏图标（StatusBarController）、基础测试框架、DESIGN.md 设计文档、CLAUDE.md 开发规范。
**交付物**:
- Xcode/SPM 项目结构（DropZoneLib + DropZone targets）
- AppDelegate + StatusBarController
- 基础单元测试（7 tests passing）
- DESIGN.md、CLAUDE.md

---

### Plan 2: Notch 检测与浮动面板 — `plan-2-notch-detection`
**状态**: `planned`
**依赖**: Plan 1
**目标**: 实现 notch/刘海屏区域检测与浮动面板窗口。
**功能范围**:
- ScreenDetector：检测屏幕是否有 notch，计算 notch 几何位置
- NotchGeometry：notch 区域矩形 + activation zone（下方 40pt、左右 20pt 扩展）
- DropZonePanel（NSPanel）：无边框浮动面板，定位在 notch 区域
- 非 notch 屏幕的 fallback 浮动 pill 定位
- 面板的展开/收起基础动画（expand/collapse）
- 多显示器场景下的屏幕切换检测（`NSApplication.didChangeScreenParametersNotification`）

---

### Plan 3: 全局 Drag 监听 — `plan-3-drag-monitor`
**状态**: `planned`
**依赖**: Plan 2
**目标**: 实现系统级拖拽会话检测，当用户在任何应用拖拽文件时激活 Notch Pocket。
**功能范围**:
- DragMonitor：通过 `NSEvent.addGlobalMonitorForEvents` 监听全局拖拽事件
- 检测 `NSPasteboard(name: .drag)` 中的文件内容
- DragState 状态机：HIDDEN → LISTENING → EXPANDED → COLLAPSE
- 光标进入/离开 activation zone 时触发面板显示/隐藏
- CGEventTap fallback 方案（需 Accessibility 权限）

---

### Plan 4: 拖放接收与文件暂存 — `plan-4-drag-drop-shelf`
**状态**: `planned`
**依赖**: Plan 3
**目标**: 实现文件拖入 drop zone 后的接收、暂存和数据管理。
**功能范围**:
- DragDestinationView：实现 `NSDraggingDestination` 协议，接收文件拖放
- FileShelfService：文件暂存到 `~/Library/Caches/com.dropzone.app/shelf/`
- 同卷 hard-link 优先，跨卷自动 copy fallback
- ShelfItem model：文件元数据（URL、缩略图、时间戳）
- ShelfStore（`@Observable`）：shelf 状态管理（添加/删除/清空）
- 支持多文件批量拖入
- 支持文本选区（生成 .txt）、URL（生成 .webloc）、网页图片等非文件类型

---

### Plan 5: Shelf UI 与缩略图 — `plan-5-shelf-ui`
**状态**: `planned`
**依赖**: Plan 4
**目标**: 实现 shelf 展开视图，展示已暂存文件的缩略图网格。
**功能范围**:
- ShelfView（SwiftUI）：4 列网格布局，80×80pt cells，最大 480×320pt
- ShelfItemView：64×64pt 缩略图 + 文件名（截断 2 行）
- ThumbnailService：异步缩略图生成（`QLThumbnailGenerator`）
  - 图片/PDF：QuickLook 缩略图
  - 视频：`AVAssetImageGenerator` 首帧
  - 其他：系统文件类型图标
- BadgeView：notch 区域的文件计数小圆标
- Hover 展开 shelf 交互

---

### Plan 6: 文件拖出与检索 — `plan-6-drag-out`
**状态**: `planned`
**依赖**: Plan 5
**目标**: 实现从 shelf 拖出文件到目标位置的完整检索流程。
**功能范围**:
- ShelfItemView 实现 `NSDraggingSource`
- 拖出时提供文件 URL（从暂存目录）
- 拖出成功后可选择从 shelf 移除
- 支持多选拖出
- 单个文件的删除按钮
- "清空全部"功能

---

### Plan 7: 文件过期与存储管理 — `plan-7-file-expiry`
**状态**: `planned`
**依赖**: Plan 6
**目标**: 实现文件自动过期、存储容量管理和清理机制。
**功能范围**:
- Timer-based 自动过期（默认 1 小时）
- 最大 shelf 容量限制（默认 50 项、2GB）
- 容量超限时自动移除最旧文件
- 大文件（>500MB）警告 toast
- App 退出时清理暂存文件
- 崩溃恢复：下次启动时清理残留暂存文件

---

### Plan 8: 动画与视觉效果 — `plan-8-animations`
**状态**: `planned`
**依赖**: Plan 5
**目标**: 完善所有交互动画，达到设计文档中的视觉规格。
**功能范围**:
- Notch → Expanded：300ms spring 动画（damping 0.75）
- Expanded → Collapsed：250ms ease-in
- Drop 确认：200ms scale pulse
- Shelf 展开/收起：spring + 缩略图 50ms stagger fade-in
- 文件计数变化：150ms spring
- 文件移除：250ms shrink + fade-out + 剩余文件 reflow
- `NSVisualEffectView` hudWindow material 背景
- Drop highlight：动态虚线边框 + 内发光

---

### Plan 9: 设置与偏好 — `plan-9-settings`
**状态**: `planned`
**依赖**: Plan 7
**目标**: 实现用户偏好设置界面与持久化。
**功能范围**:
- SettingsView（SwiftUI）：偏好设置窗口
- 可配置项：
  - 自动过期时间（15 分钟 – 24 小时）
  - 最大 shelf 项数（10 – 200）
  - 最大存储容量（500MB – 10GB）
  - 开机自启动（Launch at Login）
  - 多显示器模式（Show on all displays）
  - 全局快捷键（默认 `⌘ + Shift + D`）
  - 音效开关
- UserDefaults 持久化

---

### Plan 10: Accessibility 无障碍 — `plan-10-accessibility`
**状态**: `planned`
**依赖**: Plan 6
**目标**: 实现完整的无障碍支持，满足 macOS accessibility 标准。
**功能范围**:
- VoiceOver 支持：所有交互元素的 accessibility label 和 role
- 键盘替代方案：
  - `⌘ + Shift + D`：打开 shelf
  - `⌘ + V`：粘贴文件到 shelf
  - `⌘ + C`：复制 shelf 文件到剪贴板
  - 方向键导航、Delete 删除、Escape 关闭
- Reduce Motion：尊重系统动画减弱设置，使用 fade 替代 spring
- Increase Contrast：加粗边框、提高背景不透明度
- Reduce Transparency：用纯色背景替代毛玻璃效果
- Dynamic Type：shelf 标签尊重系统文字大小

---

### Plan 11: 多显示器支持 — `plan-11-multi-monitor`
**状态**: `planned`
**依赖**: Plan 2, Plan 6
**目标**: 完善多显示器场景下的 Notch Pocket 体验。
**功能范围**:
- 多屏 Notch Pocket 实例管理（每屏一个面板）
- Notch 屏 + 非 notch 外接屏混合场景
- 屏幕热插拔（connect/disconnect）时面板重新定位（< 500ms）
- 跨屏拖拽时的 activation zone 检测
- 所有屏幕共享单一 shelf 数据
- Spaces / Mission Control 支持（`.canJoinAllSpaces`）
- 全屏应用上方显示（`fullScreenAuxiliary`）

---

### Plan 12: Edge Cases 与健壮性 — `plan-12-edge-cases`
**状态**: `planned`
**依赖**: Plan 7, Plan 11
**目标**: 处理各类边界情况，提升应用健壮性。
**功能范围**:
- 大文件跨卷拷贝进度指示
- Alias / Symlink 解析处理
- Sandboxed app 拖拽的 security-scoped bookmark 处理
- 菜单栏应用与 notch 区域重叠时的优先级处理
- 屏幕锁定/屏保时面板隐藏与恢复
- App 崩溃后暂存文件清理
- 跨文件系统（APFS → HFS+）fallback

---

### Plan 13: 性能优化与打磨 — `plan-13-performance`
**状态**: `planned`
**依赖**: Plan 12
**目标**: 达到设计文档中的性能指标，整体打磨。
**功能范围**:
- Idle CPU < 0.5%
- Active CPU（拖拽中）< 2%
- 内存基线 < 30MB（空 shelf）/ < 80MB（50 项）
- 面板显示延迟 < 100ms
- 缩略图生成 < 500ms/文件
- Performance 测试用例（XCTest measure blocks）
- 内存泄漏检测与修复
- Release 构建优化

---

## 依赖关系图

```
Plan 1 (项目初始化)
  └── Plan 2 (Notch 检测)
        ├── Plan 3 (全局 Drag 监听)
        │     └── Plan 4 (拖放接收)
        │           └── Plan 5 (Shelf UI)
        │                 ├── Plan 6 (文件拖出)
        │                 │     ├── Plan 10 (Accessibility)
        │                 │     └── Plan 11 (多显示器) ← 也依赖 Plan 2
        │                 └── Plan 8 (动画)
        │           └── Plan 7 (文件过期) ← 也依赖 Plan 6
        │                 └── Plan 9 (设置)
        └── Plan 11 (多显示器)
  Plan 7 + Plan 11 → Plan 12 (Edge Cases)
  Plan 12 → Plan 13 (性能优化)
```
