---
{
  "title": "Xcodeパッケージ統合を使用した生成済みプロジェクト",
  "titleTemplate": ":title · Swift · パッケージレジストリ · 機能 · ガイド · Tuist",
  "description": "Xcodeパッケージ統合を使用した生成済みXcodeプロジェクトでTuist Registryを使用する方法を学びます。"
}
---
# Xcode パッケージ統合を使用したプロジェクトの生成 {#generated-project-with-xcode-based-integration}

Tuist プロジェクトでパッケージを扱う際に <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode のデフォルト統合</.localized_link> を使用している場合は、パッケージを追加する際、URL ではなくレジストリ識別子を使用する必要があります。
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
> すべてのパッケージをレジストリ識別子で追加する必要はありません。プロジェクト生成後に `tuist registry setup` を実行すると、ソース管理 URL で宣言されたパッケージをレジストリから解決するように Xcode も構成されます。これは `registryEnabled` だけでは行われません。<.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">ソース管理パッケージの解決</.localized_link> を参照してください。
