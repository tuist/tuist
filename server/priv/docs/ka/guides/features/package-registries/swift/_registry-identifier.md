რეგისტრის იდენტიფიკატორი ყოველთვის არის `{organization}.{repository}` ფორმატში. მაგალითად, `swift-composable-architecture` პაკეტის რეგისტრის გამოსაყენებლად, გააკეთეთ შემდეგი:

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
]
```
