---
{
  "title": "XcodeProjベースのパッケージ統合を用いた生成済みプロジェクト",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "生成済みプロジェクトで、XcodeProjベースのパッケージ統合とともにTuist Registryを使用します。"
}
---
# XcodeProjベースのパッケージ統合による生成プロジェクト {#generated-project-with-xcodeproj-based-integration}

<.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProjベースの統合</.localized_link>を使用する場合、レジストリで利用可能な依存関係を解決するために ``--replace-scm-with-registry`` フラグを使用できます。これを `Tuist.swift` ファイルの `installOptions` に追加してください:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

依存関係を解決するたびにレジストリが使用されるようにするには、`Tuist/Package.swift` ファイルの `dependencies` を更新して、URLではなくレジストリ識別子を使用する必要があります。レジストリ識別子は常に `{organization}.{repository}` の形式です。たとえば、`swift-composable-architecture` パッケージにレジストリを使用するには、次のようにします:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
