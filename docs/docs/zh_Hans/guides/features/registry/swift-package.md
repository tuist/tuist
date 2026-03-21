---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Swift 套件{#swift-package}

若处理Swift包，可使用`--replace-scm-with-registry` 参数从注册库解析依赖项（若可用）：

```bash
swift package --replace-scm-with-registry resolve
```

` 若需确保每次解析依赖项时都使用注册表，您需要在`的 Package.swift 文件中将`dependencies` 修改为使用注册表标识符替代
URL。注册表标识符始终采用`{organization}.{repository}`
格式。例如，要为`swift-composable-architecture` 包使用注册表，请执行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
