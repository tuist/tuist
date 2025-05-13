---
title: xcodebuild
titleTemplate: :title · Selective testing · Develop · Guides · Tuist
description: "`xcodebuild`를 이용한 선택적 테스팅을 활용하는 방법 배우기."
---

# xcodebuild {#xcodebuild}

> [!IMPORTANT] 요구 사항
>
> - <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist 계정과 프로젝트</LocalizedLink>

You can run the tests of your Xcode projects selectively through the command line. 예를 들어서, `tuist xcodebuild test -scheme App`와 같이 사용할 수 있습니다. The command hashes your project and on success, it persists the hashes to determine what has changed in future runs.

`tuist xcodebuild test`는 해시를 이용하여 테스트들을 필터링하고 가장 최근에 성공한 테스트 실행과 비교하여 변경된 부분이 있는 테스트만 재실행합니다.

예를 들어, 다음과 같은 의존성 그래프가 있다고 가정해 봅니다:

- `FeatureA`는 `FeatureATests`를 가지며, `Core`에 의존
- `FeatureB`는 `FeatureBTests`를 가지며, `Core`에 의존
- `Core`는 `CoreTests`를 가짐

`tuist xcodebuild test`는 다음과 같이 동작합니다:

| Action                     | Description                                                | Internal state                                               |
| -------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------ |
| `tuist xcodebuild test` 실행 | `CoreTests`, `FeatureATests`, 그리고 `FeatureBTests`에서 테스트 실행 | `FeatureATests`, `FeatureBTests`, 그리고 `CoreTests`의 해시 저장     |
| `FeatureA` 업데이트            | 개발자가 해당 타겟의 코드를 수정                                         | 이전과 동일                                                       |
| `tuist xcodebuild test` 실행 | `FeatureATests`의 해시가 변경되었으므로 `FeatureATests`의 테스트 실행       | `FeatureATests`의 새로운 해시 저장                                   |
| `Core` 업데이트                | 개발자가 해당 타겟의 코드를 수정                                         | 이전과 동일                                                       |
| `tuist xcodebuild test` 실행 | `CoreTests`, `FeatureATests`, 그리고 `FeatureBTests`에서 테스트 실행 | `FeatureATests`, `FeatureBTests`, 그리고 `CoreTests`의 새로운 해시 저장 |

`tuist xcodebuild test` 을 CI에서 사용하기 위해서는, <LocalizedLink href="/guides/automate/continuous-integration">Continuous integration guide</LocalizedLink>에 나와있는 설명을 참고하시면 됩니다.

Check out the following video to see selective testing in action:

<iframe title="Run tests selectively in your Xcode projects" width="560" height="315" src="https://videos.tuist.dev/videos/embed/1SjekbWSYJ2HAaVjchwjfQ" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
