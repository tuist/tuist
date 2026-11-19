Registry 識別碼一律採用 `{organization}.{repository}` 格式。例如，若要使用 `swift-composable-architecture` 套件的 Registry，請執行以下操作：

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
]
```
