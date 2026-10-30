---
{
  "title": "使用 Xcode 套件整合嘅生成專案",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "了解如何喺使用 Xcode 套件整合嘅生成 Xcode 專案中使用 Tuist Registry。"
}
---
# 使用 Xcode 套件整合生成專案 {#generated-project-with-xcode-based-integration}

如果你喺 Tuist Projects 中使用套件嘅 <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode 預設整合</.localized_link>，你喺新增套件時需要使用註冊表識別符號而非 URL：
```swift
import ProjectDescription

let project = Project(
    name: "MyProject",
    packages: [
        // Source control resolution
        // .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
        // Registry resolution
        .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "App",
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
> 你唔需要為每個套件都使用其註冊表識別符號。喺專案生成後執行 `tuist registry setup`，亦會設定 Xcode 從註冊表解析以原始碼控制 URL 宣告嘅套件，而 `registryEnabled` 本身並唔會咁做。請參閱 <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">解析原始碼控制套件</.localized_link>。
