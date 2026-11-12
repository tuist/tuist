Kayıt defteri tanımlayıcısı her zaman `{organization}.{repository}` biçimindedir. Örneğin, `swift-composable-architecture` paketi için kayıt defterini kullanmak üzere aşağıdakileri yapın:

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
]
```
