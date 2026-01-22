---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Swift 软件包 {#swift-packages}

若您正在处理 Swift 包，可使用 ``--replace-scm-with-registry`` 参数从注册库解析依赖项（若可用）：

```bash
swift package --replace-scm-with-registry resolve
```

` 若需确保每次解析依赖项时都使用注册库，您需要在`的 Package.swift 文件中将`dependencies` 修改为使用注册库标识符替代
URL。注册库标识符始终采用`{organization}.{repository}`
的格式。例如，要为`swift-composable-architecture` 包使用注册库，请执行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
