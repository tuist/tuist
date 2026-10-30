---
{
  "title": "Swift პაკეტი",
  "titleTemplate": ":title · Swift · პაკეტების რეესტრები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ Tuist Registry Swift პაკეტში."
}
---
# Swift პაკეტი {#swift-package}

თუ Swift პაკეტზე მუშაობთ, შეგიძლიათ გამოიყენოთ `--replace-scm-with-registry` ფლაგი დამოკიდებულებების რეესტრიდან ამოსაცნობად, თუ ისინი ხელმისაწვდომია:

```bash
swift package --replace-scm-with-registry resolve
```

თუ გსურთ უზრუნველყოთ, რომ რეესტრი ყოველ ჯერზე იქნას გამოყენებული დამოკიდებულებების ამოცნობისას, უნდა განაახლოთ `dependencies` თქვენს `Package.swift` ფაილში, რათა გამოიყენოთ რეესტრის იდენტიფიკატორი URL-ის ნაცვლად. რეესტრის იდენტიფიკატორი ყოველთვის არის `{organization}.{repository}` ფორმატში. მაგალითად, `swift-composable-architecture` პაკეტისთვის რეესტრის გამოსაყენებლად, გააკეთეთ შემდეგი:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
