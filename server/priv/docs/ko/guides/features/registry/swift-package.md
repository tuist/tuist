---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# 스위프트 패키지 {#swift-package}

Swift 패키지로 작업하는 경우 `--replace-scm-with-registry` 플래그를 사용하여 레지스트리에서 종속성을 사용할 수 있는
경우 이를 해결할 수 있습니다:

```bash
swift package --replace-scm-with-registry resolve
```

종속성을 해결할 때마다 레지스트리가 사용되도록 하려면 `Package.swift` 파일에서 `의존성` 을 업데이트하여 URL 대신 레지스트리
식별자를 사용하도록 해야 합니다. 레지스트리 식별자는 항상 `{조직}.{리포지토리}` 형식입니다. 예를 들어
`swift-composable-architecture` 패키지의 레지스트리를 사용하려면 다음과 같이 하세요:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
