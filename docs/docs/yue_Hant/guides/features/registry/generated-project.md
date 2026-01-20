---
{
  "title": "Generated project with the Xcode package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the Xcode package integration."
}
---
# Generated project with the Xcode package integration {#generated-project-with-xcode-based-integration}

If you are using the
<LocalizedLink href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode's default integration</LocalizedLink> of packages with Tuist Projects, you need to
use the registry identifier instead of a URL when adding a package:
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
