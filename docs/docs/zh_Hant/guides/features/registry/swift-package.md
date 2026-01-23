---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Swift 套件{#swift-package}

` 若您正在處理 Swift 套件，可使用 ``--replace-scm-with-registry` 旗標從註冊表解析依賴項（若可用）：

```bash
swift package --replace-scm-with-registry resolve
```

` 若要確保每次解析依賴項時皆使用註冊表，您需在`的 Package.swift 檔案中更新`dependencies` 設定，改用註冊表識別碼取代
URL。註冊表識別碼格式固定為`{組織名稱}.{儲存庫名稱}` 。例如欲使用`swift-composable-architecture`
套件的註冊表，請執行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
