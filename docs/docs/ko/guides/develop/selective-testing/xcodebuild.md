---
title: xcodebuild
titleTemplate: :title · Selective testing · Develop · Guides · Tuist
description: Learn how to leverage selective testing with `xcodebuild`.
---

# xcodebuild {#xcodebuild}

> [!IMPORTANT] 요구 사항
>
> - <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist 계정과 프로젝트</LocalizedLink>

To run tests selectively using `xcodebuild`, you can prepend your `xcodebuild` command with `tuist` – for example, `tuist xcodebuild test -scheme App`. The command hashes your project and on success, it persists the hashes to determine what has changed in future runs.

In future runs `tuist xcodebuild test` transparently uses the hashes to filter down the tests to run only the ones that have changed since the last successful test run.

예를 들어, 다음과 같은 의존성 그래프가 있다고 가정해 봅니다:

- `FeatureA`는 `FeatureATests`를 가지며, `Core`에 의존
- `FeatureB`는 `FeatureBTests`를 가지며, `Core`에 의존
- `Core`는 `CoreTests`를 가짐

`tuist xcodebuild test` will behave as such:

| Action                             | Description                                                | Internal state                                               |
| ---------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------ |
| `tuist xcodebuild test` invocation | `CoreTests`, `FeatureATests`, 그리고 `FeatureBTests`에서 테스트 실행 | `FeatureATests`, `FeatureBTests`, 그리고 `CoreTests`의 해시 저장     |
| `FeatureA` 업데이트                    | 개발자가 해당 타겟의 코드를 수정                                         | 이전과 동일                                                       |
| `tuist xcodebuild test` invocation | `FeatureATests`의 해시가 변경되었으므로 `FeatureATests`의 테스트 실행       | `FeatureATests`의 새로운 해시 저장                                   |
| `Core` 업데이트                        | 개발자가 해당 타겟의 코드를 수정                                         | 이전과 동일                                                       |
| `tuist xcodebuild test` invocation | `CoreTests`, `FeatureATests`, 그리고 `FeatureBTests`에서 테스트 실행 | `FeatureATests`, `FeatureBTests`, 그리고 `CoreTests`의 새로운 해시 저장 |

To use `tuist xcodebuild test` on your CI, follow the instructions in the <LocalizedLink href="/guides/automate/continuous-integration">Continuous integration guide</LocalizedLink>.
