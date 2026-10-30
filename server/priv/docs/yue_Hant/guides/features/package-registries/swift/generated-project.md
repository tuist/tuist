---
{
  "title": "使用 Xcode package 整合嘅生成專案",
  "titleTemplate": ":title · Swift · Package Registries · 功能 · 指南 · Tuist",
  "description": "學習喺具有 Xcode package 整合嘅生成 Xcode 專案中點樣使用 Tuist Registry。"
}
---
# 使用 Xcode 套件整合生成專案 {#generated-project-with-xcode-based-integration}

如果你喺 Tuist Projects 入面用緊 <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode 嘅預設整合方式</.localized_link> 來管理套件，咁你喺新增套件嗰陣需要用註冊表識別碼代替 URL：
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
> 你唔需要為每個套件都指定註冊表識別碼。喺專案生成之後執行一次 `tuist registry setup`，亦會設定 Xcode 從註冊表解析以原始碼控制 URL 宣告嘅套件，而呢個係 `registryEnabled` 單獨做唔到嘅。詳情請參閱 <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">解析原始碼控制套件</.localized_link>。
