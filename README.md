# DropZone

一款 macOS 应用，将 MacBook 的 notch（刘海）区域变为临时文件中转架，通过拖放操作实现跨窗口、跨空间的无摩擦文件传输。

## 功能简介

- 拖拽文件到 notch 区域即可暂存，释放鼠标后自由切换工作上下文
- 从 notch 中转架拖出文件到目标位置，完成传输
- 支持多文件批量拖放、缩略图预览
- 文件自动过期清理，默认 1 小时
- 支持有 notch 和无 notch 的 Mac 屏幕
- 支持多显示器

## 技术栈

| 项目 | 说明 |
|------|------|
| 语言 | Swift 6.0 |
| 框架 | SwiftUI + AppKit |
| 最低系统 | macOS 14 Sonoma |
| 构建系统 | Swift Package Manager (SPM) |
| 测试框架 | Swift Testing |

## 开发环境搭建

### 前置要求

- macOS 14 Sonoma 或更高版本
- Xcode 16+ （需要完整安装，非仅 Command Line Tools）

### DEVELOPER_DIR 设置

运行测试时需要确保 `DEVELOPER_DIR` 指向 Xcode 安装路径。如果你的默认开发工具指向 Command Line Tools，请先执行：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

或通过 `xcode-select` 永久设置：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### 构建与测试

```bash
# 构建项目
cd DropZone
swift build

# 运行测试
swift test

# Release 构建
swift build -c release
```

## 项目结构

```
dropzone/
├── CLAUDE.md                 # 开发规范与工作流
├── DESIGN.md                 # 产品设计文档
├── README.md                 # 本文件
├── DropZone/                 # Swift Package 根目录
│   ├── Package.swift         # SPM 配置（macOS 14+）
│   ├── Info.plist            # 应用信息配置
│   ├── DropZone.entitlements # 应用权限声明
│   ├── Sources/
│   │   ├── DropZone/         # 可执行目标（入口）
│   │   │   └── main.swift
│   │   └── DropZoneLib/      # 核心库目标
│   │       ├── AppDelegate.swift        # 应用生命周期管理
│   │       ├── StatusBarController.swift # 菜单栏图标控制
│   │       ├── DropZonePanel.swift       # 浮动面板窗口
│   │       ├── NotchGeometry.swift       # Notch 区域几何计算
│   │       └── ScreenDetector.swift      # 屏幕检测（notch/非 notch）
│   └── Tests/
│       └── DropZoneTests/    # 单元测试
│           ├── AppDelegateTests.swift
│           ├── DropZonePanelTests.swift
│           ├── NotchGeometryTests.swift
│           └── ScreenDetectorTests.swift
└── research/                 # 技术调研文档
```

### SPM Target 说明

| Target | 类型 | 说明 |
|--------|------|------|
| `DropZoneLib` | Library | 核心库，包含所有业务逻辑，供测试导入 |
| `DropZone` | Executable | 应用入口，依赖 `DropZoneLib` |
| `DropZoneTests` | Test | 单元测试，依赖 `DropZoneLib` |

## 许可证

待定
