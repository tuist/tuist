---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# スウィフトパッケージ{#swift-package}

Swift パッケージで作業している場合、`--replace-scm-with-registry`
フラグを使用すると、利用可能な場合はレジストリから依存関係を解決できます：

```bash
swift package --replace-scm-with-registry resolve
```

依存関係を解決するたびにレジストリが使用されるようにするには、`Package.swift` ファイルの`dependencies` を更新して、URL
の代わりにレジストリ識別子を使用する必要があります。レジストリ識別子は常に`{organization}.{repository}`
の形式です。たとえば、`swift-composable-architecture` パッケージのレジストリを使用するには、次のようにします：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
