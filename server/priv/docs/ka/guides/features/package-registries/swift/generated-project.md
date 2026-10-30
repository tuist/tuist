---
{
  "title": "Xcode-ის პაკეტის ინტეგრაციით გენერირებული პროექტი",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ Tuist Registry Xcode package integration-ით გენერირებულ Xcode პროექტში."
}
---
# გენერირებული პროექტი Xcode-ის პაკეტების ინტეგრაციით {#generated-project-with-xcode-based-integration}

თუ იყენებთ <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode-ის ნაგულისხმევ ინტეგრაციას</.localized_link> პაკეტებისთვის Tuist Projects-თან ერთად, პაკეტის დამატებისას URL-ის ნაცვლად უნდა გამოიყენოთ რეესტრის იდენტიფიკატორი:
```swift
import ProjectDescription

let project = Project(
    name: "MyProject",
    packages: [
        // Source control resolution
        // .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
        // Registry resolution
        .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "App",
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
> არ არის საჭირო თითოეული პაკეტის რეესტრის იდენტიფიკატორით დამატება. `tuist registry setup`-ის გაშვება პროექტის გენერირების შემდეგ ასევე აკონფიგურირებს Xcode-ს, რათა მან რეესტრიდან ამოიცნოს ის პაკეტები, რომლებიც წყაროს კონტროლის URL-ითაა განცხადებული — რასაც `registryEnabled` თავისთავად არ აკეთებს. იხილეთ <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">წყაროს კონტროლის პაკეტების ამოცნობა</.localized_link>.
