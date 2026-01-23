---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# XcodeProj 기반 패키지 통합으로 생성된 프로젝트 {#generated-project-with-xcodeproj-based-integration}

<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj
기반 통합</LocalizedLink>을 사용할 때, 레지스트리에서 사용 가능한 경우 의존성을 해결하기 위해
` ``--replace-scm-with-registry``` 플래그를 사용할 수 있습니다. 이 플래그를 ` ``의 `Tuist.swift``
파일 내 ` ``의 `installOptions`` 에 추가하세요:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

의존성을 해결할 때마다 레지스트리를 사용하도록 하려면, `Tuist/Package.swift` 파일에서 `dependencies` 를
업데이트하여 URL 대신 레지스트리 식별자를 사용해야 합니다. 레지스트리 식별자는 항상 `{organization}.{repository}`
형식입니다. 예를 들어, `swift-composable-architecture` 패키지의 레지스트리를 사용하려면 다음과 같이 하세요:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
