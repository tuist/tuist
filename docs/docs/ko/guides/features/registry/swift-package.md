---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Swift 패키지 {#swift-packages}

` Swift 패키지를 작업 중이라면, 레지스트리에서 사용 가능한 경우 의존성을 해결하기 위해 `
`--replace-scm-with-registry` 플래그를 사용할 수 있습니다:

```bash
swift package --replace-scm-with-registry resolve
```

의존성을 해결할 때마다 레지스트리가 사용되도록 하려면, `Package.swift` 파일에서 `dependencies` 를 URL 대신
레지스트리 식별자를 사용하도록 업데이트해야 합니다. 레지스트리 식별자는 항상 `{organization}.{repository}` 형식입니다.
예를 들어, `swift-composable-architecture` 패키지의 레지스트리를 사용하려면 다음을 수행하세요:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
