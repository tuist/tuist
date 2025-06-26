---
title: XcodeProj 기반으로 패키지를 구성한 프로젝트
titleTemplate: :title · Registry · Develop · Guides · Tuist
description: Tuist Registry를 XcodeProj 방식으로 구성된 Xcode 프로젝트에서 활용하는 방법을 학습합니다.
---

# XcodeProj 기반으로 패키지를 구성한 프로젝트 {#generated-project-with-xcodeproj-based-integration}

<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj 기반 구성</LocalizedLink>을 사용할 경우, 의존성이 레지스트리에 등록되어 있다면 `--replace-scm-with-registry` 플래그를 사용해 레지스트리에서 의존성을 가져올 수 있습니다. `Tuist.swift` 파일의 `installOptions`에 추가합니다:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

의존성을 가져올 때마다 항상 레지스트리를 사용하게 하려면, `Tuist/Package.swift` 파일의 `dependencies` 에서 URL 대신 레지스트리 식별자(registry identifier)를 사용해야 합니다. 레지스트리 식별자는 항상 `{organization}.{repository}` 형식으로 구성됩니다. 예를 들어, `swift-composable-architecture` 패키지를 레지스트리를 통해 가져오고자 할 경우, 다음과 같이 작성합니다.

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
