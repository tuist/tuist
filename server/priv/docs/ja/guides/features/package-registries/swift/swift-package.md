---
{
  "title": "Swift パッケージ",
  "titleTemplate": ":title · Swift · Package Registries · 機能 · ガイド · Tuist",
  "description": "Swift パッケージで Tuist Registry を使用する方法を学びます。"
}
---
# Swift パッケージ {#swift-package}

Swift パッケージを作業している場合、レジストリで利用可能な依存関係を解決するために `--replace-scm-with-registry` フラグを使用できます。

```bash
swift package --replace-scm-with-registry resolve
```

依存関係の解決時に毎回レジストリが使用されるようにするには、`Package.swift` ファイル内の `dependencies` を更新して、URL ではなくレジストリ識別子を使用する必要があります。

<!-- @snippet: ./_registry-identifier -->
