---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Swift 软件包 {#swift-packages}

如果您正在处理 Swift 软件包，可以使用`--replace-scm-with-registry` 标志来解析注册表中的依赖项（如果有的话）：

```bash
swift package --replace-scm-with-registry resolve
```

如果要确保每次解析依赖关系时都使用注册表，则需要更新`Package.swift` 文件中的`依赖关系` ，以使用注册表标识符而非
URL。注册表标识符的形式始终是`{organization}.{repository}`
。例如，要使用`swift-composable-architecture` 软件包的注册表，请执行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
