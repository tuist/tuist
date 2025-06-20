---
title: Use Tuist with a Swift Package
titleTemplate: :title · Adoption · Projects · Develop · Guides · Tuist
description: Swift Package와 함께 Tuist를 사용하는 방법에 대해 알아봅니다.
---

# Using Tuist with a Swift Package <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist는 프로젝트에 DSL로 `Package.swift` 사용을 지원하고 패키지 타겟을 Xcode 프로젝트와 타겟으로 변환합니다.

> [!WARNING]\
> 이 기능의 목적은 개발자가 Swift Package에 Tuist를 도입했을 때 영향도를 쉽게 파악하기 위함입니다. 따라서 우리는 Swift Package Manager의 모든 기능을 지원하거나 <LocalizedLink href="/guides/develop/projects/code-sharing">프로젝트 설명 도우미</LocalizedLink>와 같은 Tuist의 기능을 패키지 분야에 제공할 계획도 없습니다.

> [!NOTE] 루트 디렉토리\
> Tuist 명령어는 특정 <LocalizedLink href="/guides/develop/projects/directory-structure#standard-tuist-projects">디렉토리 구조</LocalizedLink>를 요구하며 루트는 `Tuist` 또는 `.git` 디렉토리로 식별됩니다.

## Swift Package와 함께 Tuist 사용 {#using-tuist-with-a-swift-package}

Swift Package가 포함된 [TootSDK Package](https://github.com/TootSDK/TootSDK) 리포지토리와 함께 Tuist를 사용해 봅니다. 가장 먼저 해야 할 일은 리포지토리를 복제하는 것입니다:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

리포지토리 디렉토리에서 Swift Package Manager 의존성을 설치해야 합니다:

```bash
tuist install
```

`tuist install`은 패키지의 의존성을 해결하고 가져오기 위해 Swift Package Manager를 사용합니다.
완료되면 프로젝트를 생성할 수 있습니다.

```bash
tuist generate
```

Voilà! 열고 작업을 시작할 수 있는 Xcode 프로젝트가 생성됐습니다.
