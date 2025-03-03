---
title: Selective testing
titleTemplate: :title · Develop · Guides · Tuist
description: 마지막 성공한 테스트 수행 이후에 변경된 테스트만 수행하기 위해 선택적 테스트를 사용합니다.
---

# Selective testing {#selective-testing}

> [!IMPORTANT] 요구사항
>
> - <LocalizedLink href="/guides/develop/projects">생성된 프로젝트</LocalizedLink>
> - <LocalizedLink href="/server/introduction/accounts-and-projects">서버 계정과 프로젝트</LocalizedLink>

프로젝트가 커질 수록 테스트 수도 증가합니다. 오랜 시간동안 모든 PR 또는 `main`에 푸시할 때마다 전체 테스트를 수행하면 수 초의 시간이 걸렸습니다. 하지만 이 방법은 팀이 가진 수천 개의 테스트에는 적합하지 않습니다.

CI에서 매번 테스트를 수행하면 변경 사항과 상관없이 정리된 Derived Data를 사용하여 프로젝트를 빌드하고 모든 테스트를 다시 수행할 것입니다. `tuist test`는 빌드 시간을 크게 줄이고 그런 다음에 테스트 실행 시간을 단축하는데 도움을 줍니다.

## 선택적으로 테스트 실행 {#running-tests-selectively}

선택적으로 테스트를 실행하기 위해 `tuist test` 명령어를 사용합니다. 이 명령어는 <LocalizedLink href="/guides/develop/build/cache#cache-warming">캐시 워밍</LocalizedLink>과 같은 방식으로 프로젝트를 해시하고 성공적으로 실행되면 다음 실행 시 변경 사항을 파악하기 위해 해시 값을 저장합니다.

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

선택적 테스트와 바이너리 캐싱의 조합은 CI에서 테스트를 수행하는 시간을 극적으로 줄일 수 있습니다.

> [!WARNING] 모듈 VS 파일 단위 세분화\
> 테스트와 소스 코드 간의 의존성을 코드 내에서 파악할 수 없으므로 선택적 테스트의 세분화는 파일 단위에서만 가능합니다. 따라서 선택적 테스트의 이점을 극대화 하려면 파일을 작고 집중적으로 유지하길 권장합니다.
