---
{
  "title": "Generated project with the Xcode package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the Xcode package integration."
}
---
# Xcode paket entegrasyonu ile oluşturulmuş projele {#generated-project-with-xcode-based-integration}

Tuist Projects ile
<LocalizedLink href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode'un varsayılan paket entegrasyonunu</LocalizedLink> kullanıyorsanız, bir paket
eklerken URL yerine kayıt tanımlayıcısını kullanmanız gerekir:
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
