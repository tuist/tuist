注册表标识符始终采用 `{organization}.{repository}` 的形式。例如，要为 `swift-composable-architecture` 包使用注册表，请执行以下操作：

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
]
```
