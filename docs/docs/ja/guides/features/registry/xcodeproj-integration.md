---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# XcodeProj ベースのパッケージ統合で生成されたプロジェクト{#generated-project-with-xcodeproj-based-integration}

<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProjベースの統合</LocalizedLink>を使用する場合、``--replace-scm-with-registry``フラグを使用すると、利用可能な場合はレジストリから依存関係を解決できます。`Tuist.swift` ファイルの`installOptions`
に追加してください：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

依存関係を解決するたびにレジストリが使用されるようにするには、`Tuist/Package.swift` ファイル内の`dependencies`
を更新して、URL ではなくレジストリ識別子を使用するようにする必要があります。レジストリ識別子は常に`{organization}.{repository}`
の形式です。たとえば、`swift-composable-architecture` パッケージのレジストリを使用するには、次のようにします：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
