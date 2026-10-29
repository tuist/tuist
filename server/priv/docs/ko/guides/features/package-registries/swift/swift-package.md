---
{
  "title": "Swift 패키지",
  "titleTemplate": ":title · Swift · 패키지 레지스트리 · 기능 · 가이드 · Tuist",
  "description": "Swift 패키지에서 Tuist Registry를 사용하는 방법을 알아봅니다."
}
---
# Swift 패키지 {#swift-package}

Swift 패키지를 작업 중이라면, 의존성이 레지스트리에 있을 경우 `--replace-scm-with-registry` 플래그를 사용하여 레지스트리에서 의존성을 해결할 수 있습니다.

```bash
swift package --replace-scm-with-registry resolve
```

의존성을 해결할 때마다 레지스트리가 사용되도록 하려면, `Package.swift` 파일의 `dependencies`을 URL 대신 레지스트리 식별자를 사용하도록 업데이트해야 합니다. 레지스트리 식별자는 항상 `{organization}.{repository}` 형식입니다. 예를 들어, `swift-composable-architecture` 패키지에 대해 레지스트리를 사용하려면 다음을 수행하세요.
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
