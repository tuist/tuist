---
{
  "title": "Xcodeパッケージ統合を使用した生成プロジェクト",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "Xcodeパッケージ統合を備えた生成されたXcodeプロジェクトでTuist Registryを使用する方法を学びます。"
}
---
# Xcode パッケージ統合による生成プロジェクト {#generated-project-with-xcode-based-integration}

Tuist プロジェクトでパッケージを <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode のデフォルト統合</.localized_link> で使用している場合、パッケージを追加する際は URL ではなくレジストリ識別子を使用する必要があります。
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
> すべてのパッケージをレジストリ識別子で追加する必要はありません。プロジェクトを生成した後に `tuist registry setup` を実行すると、ソース管理 URL で宣言されたパッケージをレジストリから解決するように Xcode も構成されます。これは `registryEnabled` 単独では行いません。<.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">ソース管理パッケージの解決</.localized_link>をご覧ください。
