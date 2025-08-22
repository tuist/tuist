---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Develop · Guides · Tuist",
  "description": "Swift Package에서 Tuist Registry를 사용하는 방법을 학습합니다."
}
---
# Swift package {#swift-package}

Swift Package를 작업 중이라면, 레지스트리에 해당 의존성이 등록되어 있는 경우 `--replace-scm-with-registry` 플래그를 사용하여 레지스트리에서 의존성을 가져올 수 있습니다.

```bash
swift package --replace-scm-with-registry resolve
```

의존성을 가져올 때마다 항상 레지스트리를 사용하게 하려면, `Package.swift` 파일의 `dependencies` 에서 URL 대신 레지스트리 식별자(registry identifier)를 사용해야 합니다. 레지스트리 식별자는 항상 `{organization}.{repository}` 형식으로 구성됩니다. 예를 들어, `swift-composable-architecture` 패키지를 레지스트리를 통해 가져오고자 할 경우, 다음과 같이 작성합니다.

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
