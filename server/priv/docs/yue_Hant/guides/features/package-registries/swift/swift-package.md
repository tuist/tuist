---
{
  "title": "Swift 套件",
  "titleTemplate": ":title · Swift · Package Registries · 功能 · 指南 · Tuist",
  "description": "了解如何在 Swift 套件中使用 Tuist Registry。"
}
---
# Swift 套件 {#swift-package}

如果你正在開發 Swift 套件，可以使用 `--replace-scm-with-registry` 旗標從註冊表解析依賴項（如果可用）：

```bash
swift package --replace-scm-with-registry resolve
```

如果你想確保每次解析依賴項時都使用註冊表，就需要更新 `Package.swift` 檔案中的 `dependencies`，改用註冊表識別碼而非 URL。註冊表識別碼的格式始終為 `{organization}.{repository}`。例如，要為 `swift-composable-architecture` 套件使用註冊表，請執行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
