---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# Swift Package에서 Tuist 사용 <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist는 프로젝트를 위한 DSL로 `Package.swift` 사용을 지원하며 패키지 타겟을 네이티브 Xcode 프로젝트와 타겟으로
변환합니다.

::: warning
<!-- -->
이 기능의 목적은 개발자가 Swift Package에 Tuist를 도입했을 때의 영향을 쉽게 파악할 수 있도록 하는 것입니다. 따라서 Swift
Package Manager의 모든 기능을 제공할 계획은 없으며,
<LocalizedLink href="/guides/features/projects/code-sharing">프로젝트 설명 도우미</LocalizedLink>와 같은 Tuist의 고유한 기능도 제공할 계획이 없습니다.
<!-- -->
:::

::: info 최상위 폴더
<!-- -->
Tuist 명령어는 `Tuist`나 `.git` 디렉토리로 루트가 식별되는 특정
<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">디렉토리 구조</LocalizedLink>를 요구합니다.
<!-- -->
:::

## Swift Package에서 Tuist 사용 {#using-tuist-with-a-swift-package}

Swift Package를 포함하는 [TootSDK Package](https://github.com/TootSDK/TootSDK) 리포지토리에
Tuist를 사용해 봅니다. 먼저 해야할 일은 리포지토리를 복제하는 것입니다:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

리포지토리의 디렉토리에서 Swift Package Manager 의존성을 설치해야 합니다:

```bash
tuist install
```

내부적으로 `tuist install`은 Swift Package Manager를 사용해 패키지의 의존성을 확인하고 가져옵니다. 의존성 확인이
완료되면, 프로젝트를 생성할 수 있습니다:

```bash
tuist generate
```

Voilà! 이 프로젝트를 열고 작업을 시작할 수 있는 네이티브 Xcode 프로젝트가 생성됩니다.
