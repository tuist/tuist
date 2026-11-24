---
{
  "title": "生成的 Xcode 项目",
  "titleTemplate": ":title · 快照 · 功能 · 指南 · Tuist",
  "description": "对 Tuist 生成项目的每个 SwiftUI 预览进行快照，并在 Tuist 中审查变更。"
}
---
# 生成的 Xcode 项目快照 {#generated-xcode-project-snapshots}

> [!IMPORTANT]
> **要求**
>
> - 你的账户已启用快照功能。目前仅限邀请使用：[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中留言以申请访问权限。
> - 一个<.localized_link href="/guides/get-started/generated-xcode-project">已连接到 Tuist</.localized_link>的项目。
> - 需要 iOS 17 或 macOS 14 来渲染预览。

[tuist/snapshots](https://github.com/tuist/snapshots) 库会将应用中的每个 SwiftUI 预览渲染为图像，因此你无需手动编写快照测试。`tuist test` 会在运行结束后上传这些图像，Tuist 会将它们与<.localized_link href="/guides/features/snapshots#how-it-works">基线</.localized_link>进行比较。

## 设置 {#set-up}

将包添加到 `Tuist/Package.swift`：

```swift
let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/tuist/snapshots", .upToNextMinor(from: "0.1.0")),
    ]
)
```

然后添加一个依赖于你的应用和 `TuistSnapshotsTesting` 的单元测试目标，以及一个用于运行该目标的 Scheme。该 Scheme 定义了快照集的名称：

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        // Your app target, named "App".
        .target(
            name: "AppSnapshotTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.app-snapshot-tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Tests/AppSnapshotTests/**"],
            dependencies: [
                .target(name: "App"),
                .external(name: "TuistSnapshotsTesting"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "AppSnapshots",
            buildAction: .buildAction(targets: [.target("App")]),
            testAction: .targets([.testableTarget(target: "AppSnapshotTests")])
        ),
    ]
)
```

向该目标添加一个测试类。每个预览都会成为独立的测试：

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

运行 `tuist install` 以获取包。

## 运行 {#run}

使用 `tuist test` 运行该 Scheme，并始终在同一个模拟器上执行，因为不同设备渲染出的图像尺寸不同：

```bash
tuist test AppSnapshots --device "iPhone 17"
```

在 CI 中，测试渲染的图像会在运行结束后上传；如果图像发生变化且无人批准更改，命令将会失败。本地运行不会上传任何内容，因为这会上传未提交的更改。

> [!TIP]
> 借助<.localized_link href="/guides/features/selective-testing">选择性测试</.localized_link>，只有当快照测试目标的图像通过验证或被批准后，该目标才会被跳过，因此重新运行无法跳过那些更改尚未被审查的目标。当一次运行跳过某些目标时，未渲染的图像计为“已跳过”，而非“已移除”。

<!-- @snippet: ./_previews-library -->
