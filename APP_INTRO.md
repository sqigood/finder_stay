# Finder Session Restore 简介

Finder Session Restore 是一个原生 macOS 菜单栏工具，用来保存和恢复 Finder 窗口会话。

当你同时打开多个 Finder 窗口、分布在不同 Desktop/Space、不同目录或网络位置时，macOS 本身并不总能完整恢复这些窗口状态。Finder Session Restore 的目标是把当前 Finder 工作现场保存下来，并在需要时尽量恢复到原来的窗口位置、大小、目录和桌面。

## 适合谁使用

- 经常同时打开多个 Finder 窗口的人。
- 会在多个 macOS Desktop/Space 之间整理文件的人。
- 需要反复切换项目目录、素材目录、网络盘或外接卷的人。
- 不希望重启、误关窗口或切换任务后手动重新摆放 Finder 窗口的人。

## 核心能力

- 一键保存当前 Finder 窗口状态。
- 一键恢复最近保存的 Finder 会话。
- 记录 Finder 窗口的位置、大小、目标路径和 Desktop/Space 信息。
- 恢复时按原 Desktop/Space 分组处理，避免所有窗口都挤到当前桌面。
- 恢复时不主动关闭现有 Finder 窗口。
- 支持本地目录、已挂载卷和网络位置的恢复前检查。
- 自动保存默认关闭，避免后台频繁改写状态。
- 保存和恢复完成后默认播放提示音。

## 使用方式

启动 app 后，菜单栏会出现 `FSR`。

常用菜单：

- `Save Current Finder State`: 保存当前 Finder 状态。
- `Restore Last Finder State`: 恢复最近一次保存的 Finder 状态。
- `Settings`: 打开设置。
- `Quit`: 退出 app。

## 设置说明

设置窗口分为四类：

- `General`: 自动保存、完成音效、登录启动。
- `Restore`: 网络恢复超时、历史快照数量。
- `Permissions`: macOS 权限状态。
- `Data`: 最近保存时间、本地数据目录和重置入口。

默认情况下，自动保存是关闭的。你可以在需要时手动保存，也可以在设置中打开自动保存。

## 权限说明

为了保存和恢复 Finder 窗口，app 可能需要 macOS 授权：

- Automation: 允许 app 控制 Finder。
- Accessibility: 允许 app 读取和调整窗口位置。
- Screen Recording: 允许 app 读取窗口元数据，用来区分不同 Desktop/Space。

这些权限只用于本机 Finder 会话保存和恢复。app 不会上传你的路径、窗口信息或文件内容。

## 本地数据

会话数据保存在：

```text
~/Library/Application Support/FinderSessionRestore/
```

主要数据包括最近一次保存的会话、恢复报告、错误日志、设置文件和历史快照。

## 设计原则

Finder Session Restore 的设计重点不是强行接管 Finder，而是尽量忠实恢复你保存时的 Finder 工作现场。

因此它遵循几个原则：

- 不关闭用户现有 Finder 窗口。
- 不修改 macOS 的 Desktop 分配设置。
- 不把无法确认 Desktop 身份的窗口错误恢复到当前桌面。
- 有问题时写入恢复报告，而不是静默失败。
- 所有数据只保存在本机。

## 当前限制

macOS 没有公开稳定的 API 可以直接把任意 Finder 窗口分配到指定 Desktop/Space。因此 app 会先切换到保存时记录的 Desktop/Space，再恢复该桌面的 Finder 窗口。

如果某个窗口缺少可靠的 Desktop/Space 信息，app 会跳过它，避免把窗口恢复到错误桌面。
