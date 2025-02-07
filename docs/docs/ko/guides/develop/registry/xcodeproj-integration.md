---
title: Generated project with the XcodeProj-based package integration
titleTemplate: :title · Registry · Develop · Guides · Tuist
description: XcodeProj 기반의 패키지 통합을 사용하는 Xcode 프로젝트에서 Tuist Registry를 어떻게 사용하는지 배웁니다.
---

# Generated project with the XcodeProj-based package integration {#generated-project-with-xcodeproj-based-integration}

When using the <LocalizedLink href="/guides/develop/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj-based integration</LocalizedLink>, you can use the `--replace-scm-with-registry` flag to resolve dependencies from the registry if they are available. `Tuist.swift` 파일의 `installOptions`에 추가합니다:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

If you want to ensure that the registry is used every time you resolve dependencies, you will need to update `dependencies` in your `Tuist/Package.swift` file to use the registry identifier instead of a URL. 레지스트리 식별자는 `{organization}.{repository}` 형식을 가집니다. For example, to use the registry for the `swift-composable-architecture` package, do the following:

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
