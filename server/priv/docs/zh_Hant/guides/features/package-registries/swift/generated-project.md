---
{
  "title": "使用 Xcode 套件整合的產生專案",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "了解如何在具備 Xcode 套件整合的產生專案中使用 Tuist Registry。"
}
---
# 使用 Xcode 套件整合產生的專案 {#generated-project-with-xcode-based-integration}

若在 Tuist 專案中使用套件的 <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode 預設整合方式</.localized_link>，新增套件時需使用註冊表識別碼而非 URL：
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
> 你不必為每個套件都指定註冊表識別碼。產生專案後執行 `tuist registry setup`，也會設定 Xcode 從註冊表解析以原始碼控制 URL 宣告的套件，而 `registryEnabled` 本身不會處理此行為。請參閱 <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">解析原始碼控制套件</.localized_link>。
