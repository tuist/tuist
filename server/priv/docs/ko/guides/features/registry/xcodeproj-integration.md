---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# XcodeProj 기반 패키지 통합으로 생성된 프로젝트 {#generated-project-with-xcodeproj-based-integration}

<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj 기반 통합</LocalizedLink>을 사용하는 경우 ``--replace-scm-with-registry`` 플래그를
사용하여 레지스트리에서 종속성을 해결할 수 있습니다(사용 가능한 경우). ` Tuist.swift` 파일의 `installOptions` 에
추가합니다:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

종속성을 해결할 때마다 레지스트리가 사용되도록 하려면 `Tuist/Package.swift` 파일에서 `의존성` 을 업데이트하여 URL 대신
레지스트리 식별자를 사용하도록 해야 합니다. 레지스트리 식별자는 항상 `{조직}.{저장소}` 형식입니다. 예를 들어
`swift-composable-architecture` 패키지의 레지스트리를 사용하려면 다음과 같이 하세요:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
