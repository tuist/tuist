---
{
  "title": "使用 Xcode 包集成的生成项目",
  "titleTemplate": ":title · Swift · 包注册表 · 功能 · 指南 · Tuist",
  "description": "了解如何在带有 Xcode 包集成的生成 Xcode 项目中使用 Tuist Registry。"
}
---
# 使用 Xcode 包集成生成的项目 {#generated-project-with-xcode-based-integration}

如果你在使用 Tuist 项目的 <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode 默认集成</.localized_link>，在添加包时需要使用注册表标识符而非 URL：
```swift
import ProjectDescription

let project = Project(
    name: "MyProject",
    packages: [
        // Source control resolution
        // .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
        // Registry resolution
        .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            dependencies: [
                .package(product: "ComposableArchitecture"),
            ]
        )
    ]
)
```

> [!TIP]
> 你不必为每个包都使用注册表标识符。在项目生成后运行 `tuist registry setup`，还会配置 Xcode 从注册表中解析以源代码管理 URL 声明的包，而 `registryEnabled` 本身不会执行此操作。请参阅 <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">解析源代码管理包</.localized_link>。
