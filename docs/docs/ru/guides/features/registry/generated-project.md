---
{
  "title": "Generated project with the Xcode package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the Xcode package integration."
}
---
# Сгенерированный проект с интеграцией пакета Xcode {#generated-project-with-xcode-based-integration}

Если вы используете интеграцию пакетов
<LocalizedLink href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode по умолчанию</LocalizedLink> с Tuist Projects, вам нужно использовать
идентификатор реестра вместо URL при добавлении пакета:
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
