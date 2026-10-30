---
{
  "title": "Swift პაკეტი",
  "titleTemplate": ":title · Swift · პაკეტების რეესტრები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაიგეთ, როგორ გამოიყენოთ Tuist Registry Swift პაკეტში."
}
---
# Swift-ის პაკეტი {#swift-package}

თუ Swift-ის პაკეტზე მუშაობთ, შეგიძლიათ გამოიყენოთ `--replace-scm-with-registry` ფლაგი რეესტრიდან დამოკიდებულებების ამოსაცნობად, თუ ისინი ხელმისაწვდომია:

```bash
swift package --replace-scm-with-registry resolve
```

თუ გსურთ უზრუნველყოთ, რომ რეესტრი ყოველ ჯერზე გამოყენებული იქნას დამოკიდებულებების ამოცნობისას, `dependencies` უნდა განაახლოთ თქვენს `Package.swift` ფაილში ისე, რომ URL-ის ნაცვლად რეესტრის იდენტიფიკატორი გამოიყენოთ. რეესტრის იდენტიფიკატორი ყოველთვის `{organization}.{repository}` ფორმატისაა. მაგალითად, `swift-composable-architecture` პაკეტისთვის რეესტრის გამოსაყენებლად, გააკეთეთ შემდეგი:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
