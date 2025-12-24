---
{
  "title": "Generated project with the Xcode package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the Xcode package integration."
}
---
# Xcode 패키지 통합으로 생성된 프로젝트 {#generated-project-with-xcode-based-integration}

<LocalizedLink href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode의 기본 패키지 통합</LocalizedLink>을 튜이스트 프로젝트와 사용하는 경우 패키지를 추가할 때 URL 대신 레지스트리
식별자를 사용해야 합니다:
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
