---
title: tuist test
titleTemplate: :title · Develop · Guides · Tuist
description: Tuist로 효율적으로 테스트하는 방법을 배웁니다.
---

# Test {#test}

Tuist는 프로젝트 생성이 필요하면 프로젝트를 생성하고 그런 다음에 플랫폼 별 빌드 툴 (예: Apple 플랫폼의 경우 `xcodebuild`) 로 테스트를 수행하는 <LocalizedLink href="/cli/test">`tuist test`</LocalizedLink> 명령어를 제공합니다.

<LocalizedLink href="/cli/test">`tuist test`</LocalizedLink> 사용하는 것이 <LocalizedLink href="/cli/generate">`tuist generate`</LocalizedLink>로 프로젝트를 생성하고 플랫폼별 빌드 툴로 테스트를 수행하는 것과 어떠한 차이가 있는지 궁금할 수 있습니다.

- **단일 명령어:** <LocalizedLink href="/cli/test">`tuist test`</LocalizedLink>는 프로젝트를 컴파일하기 전에 필요한 경우 프로젝트를 생성하도록 보장합니다.
- **보기좋은 출력:** Tuist는 출력을 더 사용자 친화적으로 만들어 주는 [xcbeautify](https://github.com/cpisciotta/xcbeautify)와 같은 툴을 사용하여 출력합니다.
- <0><1>캐시:</1></0> 원격 캐시에서 빌드 artifact를 재사용하여 빌드를 최적화 합니다.
- <LocalizedLink href="/guides/develop/test/selective-testing"><bold>선택적 테스트:</bold></LocalizedLink> 필요한 테스트만 실행되므로 시간과 리소스를 절약할 수 있습니다.
- <LocalizedLink href="/guides/develop/test/flakiness"><bold>불안정성:</bold></LocalizedLink> 불안정한 테스트를 방지하고, 감지, 그리고 수정할 수 있습니다.

## 사용법 {#usage}

프로젝트의 테스트를 수행하기 위해 `tuist test` 명령어를 사용할 수 있습니다. 이 명령어는 필요한 경우 프로젝트를 생성한 다음에 플랫폼별 빌드 툴을 사용하여 테스트를 수행합니다. `--` 구분자를 사용하여 이후의 모든 인자를 직접 빌드 툴로 전달하는 것을 지원합니다.

::: code-group

```bash [Running scheme tests]
tuist test MyScheme
```

```bash [Running all tests without binary cache]
tuist test --no-binary-cache
```

```bash [Running all tests without selective testing]
tuist test --no-selective-testing
```

:::

## Pull/merge request 의견 {#pullmerge-request-comments}

> [!IMPORTANT] 요구 사항\
> Pull/merge request 의견을 자동으로 받으려면 <LocalizedLink href="/server/introduction/accounts-and-projects">원격 프로젝트</LocalizedLink>를 <LocalizedLink href="/server/introduction/integrations#git-platforms">Git 플랫폼</LocalizedLink>과 통합해야 합니다.

CI 환경에서 테스트를 수행할 때 트리거된 CI 빌드의 pull/merge request와 테스트 결과를 연동할 수 있습니다. 이를 통해 pull/merge request에 테스트 결과를 게시할 수 있습니다.

![GitHub App example](/images/contributors/scheme-arguments.png)
