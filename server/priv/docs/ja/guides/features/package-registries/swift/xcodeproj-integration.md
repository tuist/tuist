---
{
  "title": "XcodeProjベースのパッケージ統合を使用した生成プロジェクト",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "生成プロジェクトで、XcodeProjベースのパッケージ統合を使用してTuist Registryを利用します。"
}
---
# XcodeProj ベースのパッケージ統合による生成プロジェクト {#generated-project-with-xcodeproj-based-integration}

<.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj ベースの統合</.localized_link>を使用する場合、レジストリで利用可能な依存関係があれば、``--replace-scm-with-registry``フラグを使ってレジストリから解決できます。これを`Tuist.swift`ファイルの`installOptions`に追加してください：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

依存関係の解決時に毎回レジストリが使用されるようにするには、`Tuist/Package.swift`ファイル内の`dependencies`を更新し、URL ではなくレジストリ識別子を使用する必要があります。レジストリ識別子は常に`{organization}.{repository}`の形式です。たとえば、`swift-composable-architecture`パッケージに対してレジストリを使用するには、次のようにします：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
