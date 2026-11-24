---
{
  "title": "Xcode パッケージ統合を用いた生成プロジェクト",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "Xcode パッケージ統合を備えた生成済み Xcode プロジェクトで Tuist Registry を使用する方法を学びます。"
}
---
# Xcodeのパッケージ統合を使用した生成プロジェクト {#generated-project-with-xcode-based-integration}

Tuist Projectsでパッケージの<.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcodeデフォルト統合</.localized_link>を使用している場合、パッケージを追加する際はURLではなくレジストリ識別子を使用する必要があります。
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
> すべてのパッケージをレジストリ識別子で追加する必要はありません。プロジェクト生成後に`tuist registry setup`を実行すると、ソース管理URLで宣言されたパッケージをレジストリから解決するようにXcodeも構成されますが、これは`registryEnabled`だけでは行われません。<.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">ソース管理パッケージの解決</.localized_link>をご覧ください。
