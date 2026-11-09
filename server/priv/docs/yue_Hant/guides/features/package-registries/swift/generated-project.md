---
{
  "title": "使用 Xcode 套件整合的生成專案",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "了解如何在具有 Xcode 套件整合的生成 Xcode 專案中使用 Tuist Registry。"
}
---
# 使用 Xcode 套件整合生成嘅項目 {#generated-project-with-xcode-based-integration}

如果你喺 Tuist Projects 中使用套件嘅 <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode 預設整合</.localized_link>，你喺新增套件時需要使用註冊表識別符，而唔係 URL：
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
> 你唔需要為每個套件都加上其註冊表識別符。喺項目生成後執行 `tuist registry setup`，亦會設定 Xcode 從註冊表解析以原始碼控制 URL 宣告嘅套件，而呢個功能係 `registryEnabled` 本身做唔到嘅。請參閱 <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">解析原始碼控制套件</.localized_link>。
