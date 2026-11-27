レジストリ識別子は常に `{organization}.{repository}` の形式です。たとえば、`swift-composable-architecture` パッケージのレジストリを使用するには、次のようにします。

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
]
```
