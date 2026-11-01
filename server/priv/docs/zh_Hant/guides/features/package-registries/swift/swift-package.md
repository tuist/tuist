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

若要確保每次解析相依性時都使用註冊表，你需要更新 `dependencies` 中的 `Package.swift` 檔案，改用註冊表識別碼而非 URL。註冊表識別碼的格式一律為 `{organization}.{repository}`。例如，若要為 `swift-composable-architecture` 套件使用註冊表，請執行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
