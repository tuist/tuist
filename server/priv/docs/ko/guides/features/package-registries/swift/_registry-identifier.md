레지스트리 식별자는 항상 `{organization}.{repository}` 형식입니다. 예를 들어, `swift-composable-architecture` 패키지에 대한 레지스트리를 사용하려면 다음을 수행하세요:

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
]
```
