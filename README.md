# Finder Session Restore

Finder Session Restore 是一个原生 macOS 菜单栏工具，用来保存当前 Finder 窗口状态，并在需要时恢复最近一次保存的 Finder 会话。

它是本地工具，不依赖云服务，不上传数据。所有会话文件都保存在当前 Mac 的 Application Support 目录中。

## 功能

- 保存当前 Finder 窗口的位置、大小、目标路径和桌面信息。
- 恢复最近一次保存的 Finder 会话。
- 按窗口原本所在的 macOS Desktop/Space 分组恢复。
- 恢复时不会主动关闭用户当前已有的 Finder 窗口。
- 支持本地路径、已挂载卷和网络位置的恢复前检查。
- 支持手动保存、手动恢复、设置窗口和本地历史快照。
- 自动保存默认关闭，可在设置中打开。
- 保存和恢复完成音效默认开启，可在设置中关闭。

## 项目结构

```text
FinderSessionRestore.xcodeproj/
  xcshareddata/xcschemes/FinderSessionRestore.xcscheme

Sources/
  FinderSessionRestoreApp/
    main.swift
    AppEntry.swift
    MenuBarController.swift
    SettingsWindowController.swift

  FinderSessionRestoreCore/
    FinderSessionRecorder.swift
    FinderSessionRestorer.swift
    FinderAutomationService.swift
    SpaceService.swift
    SessionStore.swift
    SettingsStore.swift
    ...

Tests/
  FinderSessionRestoreCoreTests/

Resources/
  Info.plist

Scripts/
  package_app.sh
```

## 构建

推荐使用 Xcode 打开：

```bash
open FinderSessionRestore.xcodeproj
```

命令行构建：

```bash
xcodebuild \
  -project FinderSessionRestore.xcodeproj \
  -scheme FinderSessionRestore \
  -configuration Debug \
  -derivedDataPath .xcode-derived-data \
  build
```

生成本地 `.app`：

```bash
Scripts/package_app.sh
```

生成的 app 路径：

```text
.xcode-derived-data/Build/Products/Debug/FinderSessionRestore.app
```

启动：

```bash
open .xcode-derived-data/Build/Products/Debug/FinderSessionRestore.app
```

## 测试

运行 Xcode scheme 测试：

```bash
xcodebuild test \
  -project FinderSessionRestore.xcodeproj \
  -scheme FinderSessionRestore \
  -configuration Debug \
  -derivedDataPath .xcode-derived-data \
  -destination 'platform=macOS'
```

也可以运行 SwiftPM 测试：

```bash
swift test
```

## 菜单

菜单栏图标为 `FSR`，菜单项包括：

- `Save Current Finder State`
- `Restore Last Finder State`
- `Settings`
- `Quit`

## 设置

设置窗口分为四类：

- `General`: 自动保存、完成音效、登录启动。
- `Restore`: 网络超时、历史快照数量。
- `Permissions`: macOS 权限状态和权限请求入口。
- `Data`: 最近保存时间、数据目录、重置保存会话。

默认设置：

- 自动保存：关闭。
- 自动保存间隔：300 秒。
- 完成音效：开启。
- 网络恢复超时：20 秒。
- 历史快照数量：10。
- 登录启动：关闭。

## 权限

应用可能需要以下 macOS 权限：

- Automation: 控制 Finder 保存和恢复窗口。
- Accessibility: 读取和调整 Finder 窗口位置。
- Screen Recording: 读取窗口元数据，用于区分不同 Desktop/Space 上的 Finder 窗口。

权限状态可在 `Settings > Permissions` 中查看。

如果 macOS 弹出系统权限确认，请由用户手动确认。不要通过自动化脚本点击系统安全授权弹窗。

## 数据位置

本地数据目录：

```text
~/Library/Application Support/FinderSessionRestore/
```

主要文件：

```text
latest-session.json
last-restore-report.json
last-error.txt
settings.json
History/
```

说明：

- `latest-session.json`: 最近一次保存的 Finder 会话。
- `last-restore-report.json`: 最近一次恢复结果，包括恢复数量和警告。
- `last-error.txt`: 最近一次保存或恢复错误。
- `settings.json`: 用户设置。
- `History/`: 历史会话快照。

## 恢复策略

恢复流程会按保存时记录的 Desktop/Space 分组：

1. 记录当前所在 Desktop/Space。
2. 切换到需要恢复的 Desktop/Space。
3. 在该 Desktop/Space 中恢复对应 Finder 窗口。
4. 继续下一个 Desktop/Space。
5. 恢复完成后返回最初所在的 Desktop/Space。

恢复是增量行为：应用不会为了恢复会话而关闭现有 Finder 窗口。

## 已知限制

- macOS 没有公开稳定 API 可以把任意 Finder 窗口直接分配到指定 Desktop/Space。
- 应用依赖保存时记录到的真实窗口 Space 信息；缺少真实 Desktop 身份的窗口会被跳过，避免错误恢复到当前 Desktop。
- Finder 标签页目标在部分 macOS 版本中无法通过公开 AppleScript 稳定读取，因此标签页恢复是尽力而为。
- 网络位置恢复依赖当前网络和卷挂载状态；失败时会写入恢复报告，不会阻塞其他窗口恢复。

## 手动验证清单

- 保存并恢复单个本地 Finder 窗口。
- 保存并恢复多个 Finder 窗口。
- 保存并恢复跨两个以上 Desktop/Space 的 Finder 窗口。
- 恢复后确认窗口回到原 Desktop/Space，而不是全部落到当前 Desktop。
- 保存时确认不会切换 Desktop，也不会移动 Finder 窗口。
- 恢复时确认不会关闭现有 Finder 窗口。
- 测试 Finder 窗口目标不存在或网络位置不可达时的 warning。
- 测试 `Settings` 中自动保存、音效、权限状态和数据目录按钮。
- 检查 `latest-session.json` 和 `last-restore-report.json`。
- 使用打包后的 `.app` 运行，而不是只验证源码或单元测试。

## 开发约定

- 主项目格式是 `FinderSessionRestore.xcodeproj`。
- `Scripts/package_app.sh` 必须通过 Xcode project 生成 app。
- 本地构建产物在 `.xcode-derived-data/`，不提交到 git。
- 修改 app 行为后需要重新打包、重启新 app，并通过真实 UI 验证。
