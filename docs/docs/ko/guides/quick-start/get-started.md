---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# 시작하기 {#get-started}

모든 디렉토리 또는 Xcode 프로젝트 또는 작업 공간의 디렉토리에서 Tuist를 시작하는 가장 쉬운 방법입니다:

::: 코드 그룹

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
:::

이 명령은 <LocalizedLink href="/guides/features/projects">생성된 프로젝트</LocalizedLink>를
생성하거나 기존 Xcode 프로젝트 또는 워크스페이스를 통합하는 단계를 안내합니다. 설정을 원격 서버에 연결하여
<LocalizedLink href="/guides/features/selective-testing">선택적
테스트</LocalizedLink>,
<LocalizedLink href="/guides/features/previews">프리뷰</LocalizedLink> 및
<LocalizedLink href="/guides/features/registry">레지스트리</LocalizedLink>와 같은 기능에
액세스할 수 있도록 도와줍니다.

> [참고] 기존 프로젝트 마이그레이션 기존 프로젝트를 생성된 프로젝트로 마이그레이션하여 개발자 환경을 개선하고
> <LocalizedLink href="/guides/features/cache">cache</LocalizedLink>를 활용하려면
> <LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">마이그레이션
> 가이드</LocalizedLink>를 확인하세요.
