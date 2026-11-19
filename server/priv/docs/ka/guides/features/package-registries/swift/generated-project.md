---
{
  "title": "გენერირებული პროექტი Xcode-ის პაკეტის ინტეგრაციით",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ Tuist Registry გენერირებულ Xcode-ის პროექტში Xcode-ის პაკეტის ინტეგრაციის საშუალებით."
}
---
# გენერირებული პროექტი Xcode-ის პაკეტების ინტეგრაციით {#generated-project-with-xcode-based-integration}

თუ იყენებთ <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode-ის ნაგულისხმევ ინტეგრაციას</.localized_link> Tuist Projects-თან ერთად, პაკეტის დამატებისას URL-ის ნაცვლად უნდა გამოიყენოთ რეესტრის იდენტიფიკატორი:
```swift
import ProjectDescription

let project = Project(
    name: "MyProject",
    packages: [
        // Source control resolution
        // .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
        // Registry resolution
        .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            dependencies: [
                .package(product: "ComposableArchitecture"),
            ]
        )
    ]
)
```

> [!TIP]
> არ არის აუცილებელი ყველა პაკეტის რეესტრის იდენტიფიკატორით დამატება. ბრძანების `tuist registry setup` გაშვება პროექტის გენერირების შემდეგ ასევე აკონფიგურირებს Xcode-ს ისეთი პაკეტების ამოსაცნობად, რომლებიც მითითებულია წყაროს კონტროლის URL-ით რეესტრიდან, რასაც `registryEnabled` თავისთავად არ აკეთებს. იხილეთ <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">წყაროს კონტროლის პაკეტების ამოცნობა</.localized_link>.
