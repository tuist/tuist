---
{
  "title": "Swift 패키지",
  "titleTemplate": ":title · Swift · 패키지 레지스트리 · 기능 · 가이드 · Tuist",
  "description": "Swift 패키지에서 Tuist Registry를 사용하는 방법을 알아보세요."
}
---
# Swift 패키지 {#swift-package}

Swift 패키지를 작업 중이라면, 의존성이 레지스트리에 있을 경우 `--replace-scm-with-registry` 플래그를 사용하여 레지스트리에서 의존성을 해결할 수 있습니다:

```bash
swift package --replace-scm-with-registry resolve
```

매번 의존성을 해결할 때 레지스트리가 사용되도록 하려면, `Package.swift` 파일의 `dependencies`을 URL 대신 레지스트리 식별자로 업데이트해야 합니다.

<!-- @snippet: ./_registry-identifier -->
