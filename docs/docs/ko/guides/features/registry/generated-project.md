---
title: Generated project with the Xcode package integration
titleTemplate: :title · Registry · Develop · Guides · Tuist
description: 생성된 Xcode 프로젝트에서 Xcode 패키지 통합을 사용하여 Tuist Registry를 사용하는 방법을 배워봅니다.
---

# Generated project with the Xcode package integration {#generated-project-with-xcode-based-integration}

<LocalizedLink href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode의 기본 통합</LocalizedLink>을 사용하여 Tuist 프로젝트에 패키지를 추가하는 경우 URL 대신 레지스트리 식별자를 사용해야 합니다:

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
    .target(
        name: "App",
        product: .app,
        bundleId: "io.tuist.App",
        dependencies: [
            .package(product: "ComposableArchitecture"),
        ]
    )
)
```
