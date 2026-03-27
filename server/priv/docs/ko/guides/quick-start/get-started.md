---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# 시작하기 {#get-started}

어떤 디렉토리나 Xcode 프로젝트나 워크스페이스의 디렉토리에서 Tuist를 시작하는 가장 간단한 방법은 다음과 같습니다:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

이 명령어는 <LocalizedLink href="/guides/features/projects">생성된 프로젝트를 만들거나</LocalizedLink> 기존 Xcode 프로젝트나 워크스페이스를 통합하는 과정을 안내합니다. 이 명령어는 또한 원격 서버와의
연결을 설정하여 <LocalizedLink href="/guides/features/selective-testing">선택 테스트</LocalizedLink>,
<LocalizedLink href="/guides/features/previews">프리뷰</LocalizedLink>,
<LocalizedLink href="/guides/features/registry">레지스트리</LocalizedLink>와 같은 기능을
활용할 수 있도록 해줍니다.

::: info 기존 프로젝트 마이그레이션
<!-- -->
기존 프로젝트를 생성된 프로젝트로 마이그레이션하여 개발자 경험을 증진시키고
<LocalizedLink href="/guides/features/cache">캐시</LocalizedLink>를 활용하려면
<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">마이그레이션 가이드</LocalizedLink>를 참고바랍니다.
<!-- -->
:::
