---
{
  "title": "Generated project with the Xcode package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the Xcode package integration."
}
---
# Wygenerowany projekt z integracją pakietów opartą na XcodeProj {#generated-project-with-xcodeproj-based-integration}

Jeśli korzystasz z domyślnej integracji
<LocalizedLink href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode</LocalizedLink>
pakietów z Tuist Projects, musisz użyć identyfikatora rejestru zamiast adresu
URL podczas dodawania pakietu:
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
