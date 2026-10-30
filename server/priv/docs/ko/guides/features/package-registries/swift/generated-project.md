---
{
  "title": "Xcode 패키지 통합을 사용한 프로젝트 생성",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "Xcode 패키지 통합이 적용된 생성된 Xcode 프로젝트에서 Tuist Registry를 사용하는 방법을 알아보세요."
}
---
# Xcode 패키지 통합으로 생성된 프로젝트 {#generated-project-with-xcode-based-integration}

Tuist Projects에서 패키지에 <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode의 기본 통합</.localized_link>을 사용하는 경우, 패키지를 추가할 때 URL 대신 레지스트리 식별자를 사용해야 합니다:
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
> 모든 패키지를 레지스트리 식별자로 추가할 필요는 없습니다. 프로젝트가 생성된 후 `tuist registry setup`를 실행하면 Xcode가 소스 제어 URL로 선언된 패키지를 레지스트리에서 해결하도록 구성되며, 이는 `registryEnabled`만으로는 수행되지 않습니다. 자세한 내용은 <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">소스 제어 패키지 해결</.localized_link>을 참조하세요.
