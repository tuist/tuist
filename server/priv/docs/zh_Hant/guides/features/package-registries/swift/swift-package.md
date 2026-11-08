---
{
  "title": "Swift 套件",
  "titleTemplate": ":title · Swift · 套件註冊表 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Swift 套件中使用 Tuist Registry。"
}
---
# Swift 套件 {#swift-package}

如果你正在開發 Swift 套件，可以使用 `--replace-scm-with-registry` 旗標從註冊表解析相依性（若可用）：

```bash
swift package --replace-scm-with-registry resolve
```

若要確保每次解析相依性時都使用註冊表，你需要更新 `Package.swift` 檔案中的 `dependencies`，改用註冊表識別碼而非 URL。

<!-- @snippet: ./_registry-identifier -->
