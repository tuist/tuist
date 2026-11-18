El identificador del registro siempre tiene el formato `{organization}.{repository}`. Por ejemplo, para usar el registro del paquete `swift-composable-architecture`, haz lo siguiente:

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
]
```
