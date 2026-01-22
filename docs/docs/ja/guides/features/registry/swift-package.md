---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Swiftパッケージ{#swift-package}

Swiftパッケージを扱う場合、レジストリから依存関係を解決できる場合は、``--replace-scm-with-registry`` フラグを使用できます:

```bash
swift package --replace-scm-with-registry resolve
```

` 依存関係を解決するたびにレジストリを使用するようにするには、`の Package.swift ファイル内の`dependencies` を更新し、URL
の代わりにレジストリ識別子を使用する必要があります。レジストリ識別子は常に`{organization}.{repository}` の形式です。たとえば、`の
swift-composable-architecture` パッケージのレジストリを使用するには、次の操作を行います：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
