---
{
  "title": "Swift パッケージ",
  "titleTemplate": ":title · Swift · パッケージレジストリ · 機能 · ガイド · Tuist",
  "description": "Tuist Registry を Swift パッケージで利用する方法を学びます。"
}
---
# Swift パッケージ {#swift-package}

Swift パッケージを作業している場合、依存関係がレジストリで利用可能なときは `--replace-scm-with-registry` フラグを使ってレジストリから依存関係を解決できます。

```bash
swift package --replace-scm-with-registry resolve
```

依存関係を解決するたびに必ずレジストリを使用するようにしたい場合は、`Package.swift` ファイル内の `dependencies` を更新して、URL ではなくレジストリ識別子を使用してください。

<!-- @snippet: ./_registry-identifier -->
