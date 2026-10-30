---
{
  "title": "Swift パッケージ",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "Swift パッケージで Tuist Registry を使用する方法を学びます。"
}
---
# Swift パッケージ {#swift-package}

Swift パッケージを扱っている場合、レジストリから依存関係を解決する際に `--replace-scm-with-registry` フラグを使用できます（利用可能な場合）：

```bash
swift package --replace-scm-with-registry resolve
```

依存関係の解決時に毎回レジストリを使用するようにするには、`Package.swift` ファイル内の `dependencies` を更新し、URL の代わりにレジストリ識別子を使用する必要があります。レジストリ識別子は常に `{organization}.{repository}` の形式です。例えば、`swift-composable-architecture` パッケージでレジストリを使用するには、次のようにします：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
