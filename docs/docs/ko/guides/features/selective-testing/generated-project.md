---
title: Generated project
titleTemplate: :title · Selective testing · Develop · Guides · Tuist
description: 생성된 프로젝트에서 선택적 테스트를 활용하는 방법을 배워봅니다.
---

# Generated project {#generated-project}

> [!IMPORTANT] 요구 사항
>
> - <LocalizedLink href="/guides/features/projects">생성된 프로젝트</LocalizedLink>
> - <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist 계정과 프로젝트</LocalizedLink>

생성된 프로젝트에서 선택적으로 테스트를 실행하려면 `tuist test` 명령어를 사용하세요. 이 명령어는 <LocalizedLink href="/guides/features/build/cache#cache-warming">캐시 워밍</LocalizedLink>과 동일한 방식으로 Xcode 프로젝트를 <LocalizedLink href="/guides/features/projects/hashing">해시</LocalizedLink>하며, 성공적으로 실행되면 다음 실행 시 변경 사항을 파악하기 위해 해시 값을 저장합니다.

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

`tuist test`는 바이너리 캐싱을 활용하여 테스트를 실행할 때 로컬이나 원격 스토리지에서 가능한 많은 바이너리를 사용함으로써 빌드 시간을 단축합니다. 선택적 테스트와 바이너리 캐싱의 조합은 CI에서 테스트를 수행하는 시간을 극적으로 줄일 수 있습니다.

## UI 테스트 {#ui-tests}

Tuist는 UI 테스트의 선택적 테스트를 지원합니다. 그러나 Tuist는 사전에 테스트 대상을 알아야 합니다. 다음과 같이, `destination` 파라미터를 지정한 경우에만, Tuist는 선택적 UI 테스트를 수행할 수 있습니다:

```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
