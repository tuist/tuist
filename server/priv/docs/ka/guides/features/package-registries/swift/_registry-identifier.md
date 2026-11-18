რეესტრის იდენტიფიკატორი ყოველთვის `{organization}.{repository}` ფორმატითაა. მაგალითად, `swift-composable-architecture` პაკეტის რეესტრის გამოსაყენებლად გააკეთეთ შემდეგი:

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
]
```
