---
{
  "title": "Swift パッケージ",
  "titleTemplate": ":title · Swift · パッケージレジストリ · 機能 · ガイド · Tuist",
  "description": "Tuist Registry を Swift パッケージで利用する方法を学びます。"
}
---
# Swift パッケージ {#swift-package}

Swift パッケージを作業している場合、依存関係がレジストリで利用可能であれば、`--replace-scm-with-registry` フラグを使用してレジストリから依存関係を解決できます。

```bash
swift package --replace-scm-with-registry resolve
```

依存関係を解決するたびにレジストリを使用することを確実にしたい場合は、`Package.swift` ファイル内の `dependencies` を更新して、URL ではなくレジストリ識別子を使用する必要があります。レジストリ識別子は常に `{organization}.{repository}` の形式です。例えば、`swift-composable-architecture` パッケージのレジストリを使用するには、次のようにします。
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
