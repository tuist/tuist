---
{
  "title": "Swift パッケージ",
  "titleTemplate": ":title · Swift · パッケージレジストリ · 機能 · ガイド · Tuist",
  "description": "Tuist Registry を Swift パッケージで利用する方法を学びます。"
}
---
# Swift パッケージ {#swift-package}

Swift パッケージを作業している場合、レジストリで依存関係が利用可能であれば、`--replace-scm-with-registry` フラグを使用してレジストリから依存関係を解決できます：

```bash
swift package --replace-scm-with-registry resolve
```

依存関係を解決するたびに必ずレジストリを使用したい場合は、`Package.swift` ファイル内の `dependencies` を更新して、URL ではなくレジストリ識別子を使用する必要があります。

<!-- @snippet: ./_registry-identifier -->
