---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# 快速套裝{#swift-package}

如果您正在處理 Swift 套件，您可以使用`--replace-scm-with-registry` 標誌來解析來自註冊表的依存關係，如果它們是可用的話：

```bash
swift package --replace-scm-with-registry resolve
```

如果您想確保每次解析相依性時都使用註冊表，則需要更新`Package.swift` 檔案中的`dependencies` ，以使用註冊表識別符而非
URL。註冊表識別符的形式總是`{organization}.{repository}`
。例如，要使用`swift-composable-architecture` 软件包的注册表，请执行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
