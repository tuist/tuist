---
{
  "title": "გენერირებული პროექტი XcodeProj-ზე დაფუძნებული პაკეტის ინტეგრაციით",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "გამოიყენეთ Tuist Registry XcodeProj-ზე დაფუძნებული პაკეტის ინტეგრაციით გენერირებულ პროექტებში."
}
---
# გენერირებული პროექტი XcodeProj-ზე დაფუძნებული პაკეტის ინტეგრაციით {#generated-project-with-xcodeproj-based-integration}

როდესაც იყენებთ <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj-ზე დაფუძნებულ ინტეგრაციას</.localized_link>, შეგიძლიათ გამოიყენოთ ``--replace-scm-with-registry`` ფლაგი რეპოსიტორიდან დამოკიდებულებების ამოსაცნობად, თუ ისინი ხელმისაწვდომია. დაამატეთ ის `installOptions`-ში თქვენს `Tuist.swift` ფაილში:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

თუ გსურთ უზრუნველყოთ, რომ რეპოსიტორი ყოველ ჯერზე გამოიყენება დამოკიდებულებების ამოცნობისას, მოგიწევთ `dependencies`-ის განახლება თქვენს `Tuist/Package.swift` ფაილში, რათა გამოიყენოთ რეპოსიტორის იდენტიფიკატორი URL-ის ნაცვლად. რეპოსიტორის იდენტიფიკატორი ყოველთვის არის `{organization}.{repository}` ფორმატში. მაგალითად, `swift-composable-architecture` პაკეტისთვის რეპოსიტორის გამოსაყენებლად, გააკეთეთ შემდეგი:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
