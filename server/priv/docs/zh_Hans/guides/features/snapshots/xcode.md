---
{
  "title": "Xcode",
  "titleTemplate": ":title · 快照 · 功能 · 指南 · Tuist",
  "description": "为 Xcode 项目的每个 SwiftUI 预览创建快照，并在 Tuist 中查看变更。"
}
---
# Xcode 快照 {#xcode-snapshots}

> [!IMPORTANT]
> **要求**
>
> - 你的账户已启用快照功能。目前仅限邀请使用：[联系我们](mailto:contact@tuist.dev)或在 [社区 Slack](https://slack.tuist.dev) 中联系我们以申请访问权限。
> - 一个<.localized_link href="/guides/get-started/existing-xcode-project">已连接到 Tuist</.localized_link>的项目。
> - 需要 iOS 17 或 macOS 14 来渲染预览。

[tuist/snapshots](https://github.com/tuist/snapshots) 库将应用中的每个 SwiftUI 预览渲染为图像，因此你无需手动编写快照测试。`tuist xcodebuild test` 会在运行后上传这些图像，Tuist 会将它们与<.localized_link href="/guides/features/snapshots#how-it-works">基准</.localized_link>进行比较。

## 设置 {#set-up}

1. 在 Xcode 中，添加 `https://github.com/tuist/snapshots` 包，版本从 `0.1.0` 开始。
2. 创建一个由你的应用托管的单元测试目标，例如 `AppSnapshotTests`，并将该包的 `TuistSnapshotsTesting` 产品链接到它。
3. 向该目标添加一个测试类。每个预览都会成为其自己的测试：

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

4. 添加一个运行该目标的 Scheme，例如 `AppSnapshots`。该 Scheme 用于命名快照集。

## 运行 {#run}

通过 `tuist xcodebuild test` 运行测试，始终在同一个模拟器上运行，因为不同的设备会渲染出不同尺寸的图像：

```bash
tuist xcodebuild test -scheme AppSnapshots -destination 'platform=iOS Simulator,name=iPhone 17'
```

在 CI 中，测试渲染的图像会在运行后上传，如果图像发生变化且无人批准更改，命令将会失败。本地运行不会上传任何内容，因为它们会上传未提交的更改。

<!-- @snippet: ./_previews-library -->
