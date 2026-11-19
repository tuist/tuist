---
{
  "title": "透過 Xcode 套件整合產生專案",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "了解如何在透過 Xcode 套件整合產生的 Xcode 專案中使用 Tuist Registry。"
}
---
# 使用 Xcode 套件整合生成專案 {#generated-project-with-xcode-based-integration}

如果你喺 Tuist Projects 入面用緊 <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode 嘅預設套件整合</.localized_link>，新增套件時需要用註冊表識別符代替 URL：
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
> 你唔使將每個套件都加上註冊表識別符。喺專案生成之後執行 `tuist registry setup`，亦會設定 Xcode 從註冊表解析以原始碼控制 URL 宣告嘅套件，而 `registryEnabled` 本身並唔會處理呢部分。詳情請參閱 <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">解析原始碼控制套件</.localized_link>。
