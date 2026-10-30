---
{
  "title": "Swift Package와 함께 Tuist 사용하기",
  "titleTemplate": ":title · 도입 · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Swift Package와 함께 Tuist를 사용하는 방법을 알아보세요."
}
---
# Swift 패키지와 함께 Tuist 사용하기 <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist는 프로젝트의 DSL로 `Package.swift`를 사용하는 것을 지원하며, 패키지 타깃을 네이티브 Xcode 프로젝트와 타깃으로 변환합니다.

> [!WARNING]
> 이 기능의 목적은 개발자가 Swift 패키지에 Tuist 도입 시 영향을 쉽게 평가할 수 있도록 하는 것입니다. 따라서 우리는 Swift Package Manager의 모든 기능을 지원하지 않으며, <.localized_link href="/guides/features/projects/code-sharing">프로젝트 설명 헬퍼</.localized_link>와 같은 Tuist의 고유한 기능을 패키지 영역으로 가져올 계획도 없습니다.


> [!NOTE]
> **루트 디렉터리**
>
> Tuist 명령어는 루트가 `Tuist` 또는 `.git` 디렉터리로 식별되는 특정 <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">디렉터리 구조</.localized_link>를 예상합니다.


## Swift 패키지와 함께 Tuist 사용하기 {#using-tuist-with-a-swift-package}

Swift 패키지를 포함하는 [TootSDK 패키지](https://github.com/TootSDK/TootSDK) 저장소에서 Tuist를 사용해 보겠습니다. 먼저 해야 할 일은 저장소를 클론하는 것입니다:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

저장소 디렉터리로 이동한 후, Swift Package Manager 의존성을 설치해야 합니다:

```bash
tuist install
```

내부적으로 `tuist install`는 Swift Package Manager를 사용하여 패키지의 의존성을 해결하고 가져옵니다. 해결이 완료되면 프로젝트를 생성할 수 있습니다:

```bash
tuist generate
```

자, 이제 열어서 작업을 시작할 수 있는 네이티브 Xcode 프로젝트가 준비되었습니다.
