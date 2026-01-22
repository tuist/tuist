---
{
  "title": "Generated project with the Xcode package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the Xcode package integration."
}
---
# Xcodeパッケージ統合によるプロジェクト生成{#generated-project-with-xcode-based-integration}

<LocalizedLink href="/guides/features/projects/dependencies#xcodes-default-integration">Xcodeのデフォルト統合</LocalizedLink>でTuist
Projectsとパッケージを連携している場合、パッケージ追加時にはURLではなくレジストリ識別子を使用する必要があります：
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
