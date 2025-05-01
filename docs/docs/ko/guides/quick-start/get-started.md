---
title: Get started
titleTemplate: :title · Quick-start · Guides · Tuist
description: Tuist를 설치하는 방법을 알아보세요.
---

# Get started {#get-started}

어떤 디렉토리나 Xcode 프로젝트 또는 워크스페이스 디렉토리에서 Tuist를 시작하는 가장 쉬운 방법은 다음과 같습니다:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```

:::

이 명령어는 <LocalizedLink href="/guides/develop/projects">생성된 프로젝트를 만들거나</LocalizedLink> 기존의 Xcode 프로젝트 또는 워크스페이스를 통합하는 과정을 안내합니다. 이 설정을 서버에 연결하여 <LocalizedLink href="/guides/develop/selective-testing">선택적 테스트</LocalizedLink>, <LocalizedLink href="/guides/share/previews">프리뷰</LocalizedLink>, <LocalizedLink href="/guides/develop/registry">레지스트리</LocalizedLink>와 같은 기능을 사용할 수 있도록 도와줍니다.

> [!NOTE] 기존 프로젝트 마이그레이션\
> 더 나은 개발자 경험과 <LocalizedLink href="/guides/develop/cache">캐시</LocalizedLink>를 활용하기 위해 기존 프로젝트를 생성된 프로젝트로 마이그레이션 하기 원한다면 <LocalizedLink href="/guides/develop/projects/adoption/migrate/xcode-project">마이그레이션 가이드</LocalizedLink>를 참고 바랍니다.
