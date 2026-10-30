---
{
  "title": "XcodeProj 기반 패키지 통합을 사용한 프로젝트 생성",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "생성된 프로젝트에서 XcodeProj 기반 패키지 통합과 함께 Tuist Registry를 사용하세요."
}
---
# XcodeProj 기반 패키지 통합으로 생성된 프로젝트 {#generated-project-with-xcodeproj-based-integration}

<.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj 기반 통합</.localized_link>을 사용할 때, 레지스트리에 의존성이 있으면 ``--replace-scm-with-registry`` 플래그를 사용해 레지스트리에서 의존성을 해결할 수 있습니다. 이를 `Tuist.swift` 파일의 `installOptions`에 추가하세요:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

의존성을 해결할 때마다 레지스트리를 사용하도록 하려면, `Tuist/Package.swift` 파일의 `dependencies`을 업데이트하여 URL 대신 레지스트리 식별자를 사용해야 합니다. 레지스트리 식별자는 항상 `{organization}.{repository}` 형식입니다. 예를 들어, `swift-composable-architecture` 패키지에 레지스트리를 사용하려면 다음을 수행하세요:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
