---
{
  "title": "Xcodeパッケージ統合による生成プロジェクト",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "Xcodeパッケージ統合を使用した生成済みXcodeプロジェクトでTuist Registryを利用する方法を学びます。"
}
---
# Xcodeパッケージ統合で生成されたプロジェクト{#generated-project-with-xcode-based-integration}

Tuist Projectsでパッケージを<.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcodeのデフォルト統合</.localized_link>で使用している場合、パッケージを追加する際はURLではなくレジストリ識別子を使用する必要があります。
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
> すべてのパッケージをレジストリ識別子で追加する必要はありません。プロジェクトが生成された後に`tuist registry setup`を実行すると、ソース管理URLで宣言されたパッケージをレジストリから解決するようにXcodeも構成されます。これは`registryEnabled`単独では行いません。<.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">ソース管理パッケージの解決</.localized_link>をご覧ください。
