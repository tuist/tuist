---
title: Generated project
titleTemplate: :title · Selective testing · Develop · Guides · Tuist
description: Learn how to leverage selective testing with a generated project.
---

# Generated project {#generated-project}

> [!IMPORTANT] 요구 사항
>
> - <LocalizedLink href="/guides/develop/projects">생성된 프로젝트</LocalizedLink>
> - <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist 계정과 프로젝트</LocalizedLink>

생성된 프로젝트에서 선택적으로 테스트를 실행하려면 `tuist test` 명령어를 사용하세요. The command <LocalizedLink href="/guides/develop/projects/hashing">hashes</LocalizedLink> your Xcode project the same way it does for <LocalizedLink href="/guides/develop/build/cache#cache-warming">warming the cache</LocalizedLink>, and on success, it persists the hashes on to determine what has changed in future runs.

다음에 실행하면 `tuist test`는 해시를 사용하여 마지막으로 성공적으로 실행된 테스트 이후 변경된 테스트만 선별합니다.

예를 들어, 다음과 같은 의존성 그래프가 있다고 가정해 봅니다:

- `FeatureA`는 `FeatureATests`를 가지며, `Core`에 의존
- `FeatureB`는 `FeatureBTests`를 가지며, `Core`에 의존
- `Core`는 `CoreTests`를 가짐

`tuist test`는 다음과 같이 동작합니다:

| Action          | Description                                                | Internal state                                               |
| --------------- | ---------------------------------------------------------- | ------------------------------------------------------------ |
| `tuist test` 호출 | `CoreTests`, `FeatureATests`, 그리고 `FeatureBTests`에서 테스트 실행 | `FeatureATests`, `FeatureBTests`, 그리고 `CoreTests`의 해시 저장     |
| `FeatureA` 업데이트 | 개발자가 해당 타겟의 코드를 수정                                         | 이전과 동일                                                       |
| `tuist test` 호출 | `FeatureATests`의 해시가 변경되었으므로 `FeatureATests`의 테스트 실행       | `FeatureATests`의 새로운 해시 저장                                   |
| `Core` 업데이트     | 개발자가 해당 타겟의 코드를 수정                                         | 이전과 동일                                                       |
| `tuist test` 호출 | `CoreTests`, `FeatureATests`, 그리고 `FeatureBTests`에서 테스트 실행 | `FeatureATests`, `FeatureBTests`, 그리고 `CoreTests`의 새로운 해시 저장 |

`tuist test` integrates directly with binary caching to use as many binaries from your local or remote storage to improve the build time when running your test suite. 선택적 테스트와 바이너리 캐싱의 조합은 CI에서 테스트를 수행하는 시간을 극적으로 줄일 수 있습니다.
