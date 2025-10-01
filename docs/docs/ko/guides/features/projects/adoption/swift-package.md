---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# 스위프트 패키지와 함께 튜이스트 사용하기 <Badge type="warning" text="beta" /> {#사용-투이스트를-스위프트-패키지와-함께-사용하기-배지-타입경고-텍스트베타-}

Tuist는 프로젝트의 DSL로 `Package.swift` 사용을 지원하며, 패키지 타깃을 기본 Xcode 프로젝트 및 타깃으로 변환합니다.

> [!경고] 이 기능의 목적은 개발자가 Swift 패키지에 Tuist를 채택했을 때 미치는 영향을 쉽게 평가할 수 있는 방법을 제공하는
> 것입니다. 따라서 Swift 패키지 관리자 기능의 전체 범위를 지원하거나
> <LocalizedLink href="/guides/features/projects/code-sharing">프로젝트 설명
> 도우미</LocalizedLink>와 같은 모든 Tuist의 고유 기능을 패키지 세계에 도입할 계획은 없습니다.

> [참고] ROOT DIRECTORY Tuist 명령은 특정
> <LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">
> 디렉터리 구조</LocalizedLink>를 예상하며, 그 루트는 `Tuist` 또는 `.git` 디렉터리로 식별됩니다.

## 스위프트 패키지와 함께 튜이스트 사용하기 {#using-tuist-with-a-swift-package}

Swift 패키지가 포함된 [TootSDK 패키지](https://github.com/TootSDK/TootSDK) 리포지토리와 함께
Tuist를 사용하겠습니다. 가장 먼저 해야 할 일은 리포지토리를 복제하는 것입니다:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

저장소 디렉토리에 들어가면 Swift 패키지 관리자 종속 요소를 설치해야 합니다:

```bash
tuist install
```

내부적으로 `tuist install` 은 Swift 패키지 관리자를 사용하여 패키지의 종속성을 해결하고 가져옵니다. 해결이 완료되면 프로젝트를
생성할 수 있습니다:

```bash
tuist generate
```

짜잔! 이제 네이티브 Xcode 프로젝트를 열고 작업을 시작할 수 있습니다.
