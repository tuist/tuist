---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# XcodeProjベースのパッケージ統合で生成されたプロジェクト{#generated-project-with-xcodeproj-based-integration}

<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProjベースの統合</LocalizedLink>を使用する場合、レジストリから依存関係を解決できる場合は、```--replace-scm-with-registry```
フラグを使用できます。これを、`Tuist.swift` ファイル内の`installOptions` に追加してください：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

依存関係を解決するたびにレジストリを使用するようにするには、`Tuist/Package.swift` ファイル内の`dependencies`
を更新し、URL の代わりにレジストリ識別子を使用する必要があります。レジストリ識別子は常に`{organization}.{repository}`
の形式です。例えば、`swift-composable-architecture` パッケージのレジストリを使用するには、次の操作を行います：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
