---
{
  "title": "Generated project with the Xcode package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the Xcode package integration."
}
---
# Generated project with the Xcode package integration {#generated-project-with-xcode-based-integration}

If you are using the <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode's default integration</.localized_link> of packages with Tuist Projects, you need to use the registry identifier instead of a URL when adding a package:
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
> You don't have to add every package by its registry identifier. `tuist registry setup` and `tuist registry login` also configure Xcode to resolve packages that are declared with a source control URL from the registry, which `registryEnabled` doesn't do on its own. See <.localized_link href="/guides/features/registry/xcode-project#resolving-source-control-packages">Resolving source control packages</.localized_link>.
