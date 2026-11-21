რეესტრის იდენტიფიკატორი ყოველთვის `{organization}.{repository}` ფორმატშია. მაგალითად, `swift-composable-architecture` პაკეტის რეესტრის გამოყენებისთვის, გააკეთეთ შემდეგი:

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
]
```
