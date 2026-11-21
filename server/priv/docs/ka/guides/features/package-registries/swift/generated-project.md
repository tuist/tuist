---
{
  "title": "გენერირებული პროექტი Xcode-ის პაკეტების ინტეგრაციით",
  "titleTemplate": ":title · Swift · პაკეტების რეესტრები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ Tuist Registry გენერირებულ Xcode-ის პროექტში Xcode-ის პაკეტების ინტეგრაციის მეშვეობით."
}
---
# გენერირებული პროექტი Xcode-ის პაკეტების ინტეგრაციით {#generated-project-with-xcode-based-integration}

თუ იყენებთ <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode-ის ნაგულისხმევ ინტეგრაციას</.localized_link> პაკეტებთან Tuist Projects-ში, პაკეტის დამატებისას URL-ის ნაცვლად უნდა გამოიყენოთ რეესტრის იდენტიფიკატორი:
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
> არ არის საჭირო ყველა პაკეტის რეესტრის იდენტიფიკატორით დამატება. ბრძანების `tuist registry setup` გაშვება პროექტის გენერირების შემდეგ ასევე აკონფიგურირებს Xcode-ს, რომ რეესტრიდან ამოიცნოს ის პაკეტები, რომლებიც წყაროს კონტროლის URL-ითაა განსაზღვრული; ამას `registryEnabled` თავისთავად არ აკეთებს. იხილეთ <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">წყაროს კონტროლის პაკეტების ამოცნობა</.localized_link>.
