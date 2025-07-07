---
title: Selective testing
titleTemplate: :title · Features · Guides · Tuist
description: 마지막 성공한 테스트 수행 이후에 변경된 테스트만 수행하기 위해 선택적 테스트를 사용합니다.
---

# Selective testing {#selective-testing}

프로젝트가 커질 수록 테스트 수도 증가합니다. 오랜 시간 동안 모든 PR 또는 `main`에 푸시할 때마다 전체 테스트를 수행하면 수 초의 시간이 걸렸습니다. 하지만 이 방법은 팀이 가진 수천 개의 테스트에는 적합하지 않습니다.

CI에서 테스트를 실행할 때마다 변경 사항에 관계없이 모든 테스트를 다시 실행할 가능성이 높습니다. Tuist의 선택적 테스트는 우리의 <LocalizedLink href="/guides/features/projects/hashing">hashing algorithm</LocalizedLink>을 기반으로 마지막 성공적인 테스트 이후에 변경된 테스트만 실행하여 테스트 자체의 실행 속도를 크게 높일 수 있도록 도와줍니다.

선택적 테스트는 모든 Xcode 프로젝트를 지원하는 `xcodebuild` 에서 작동합니다. 또한, Tuist를 사용하여 프로젝트를 만들었을 경우 <LocalizedLink href="/guides/features/build/cache">binary cache</LocalizedLink>와 같은 추가 편의성을 제공하는 `tuist test` 명령어를 대신 사용할 수도 있습니다. 선택적 테스트를 시작하려면, 프로젝트 설정에 따른 지침을 따르세요:

- <LocalizedLink href="/guides/features/selective-testing/xcodebuild">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">생성된 프로젝트</LocalizedLink>

> [!WARNING] 모듈 VS 파일 단위 세분화\
> 테스트와 소스 코드 간의 의존성을 코드 내에서 파악할 수 없으므로 선택적 테스트의 세분화는 파일 단위에서만 가능합니다. 따라서 선택적 테스트의 이점을 극대화 하려면 파일을 작고 집중적으로 유지하길 권장합니다.

> [!WARNING] 테스트 커버리지\
> 테스트 커버리지 도구는 전체 테스트 스위트가 한 번에 실행된다는 전제를 기반으로 하기 때문에, 선택적 테스트 수행과는 호환되지 않습니다. 이는 커버리지 데이터가 실제 상황을 반영하지 않을 수 있다는 것을 의미합니다. 이것은 이미 알려진 문제이며, 잘못된 사용은 아닙니다. 커버리지가 유의미한 인사이트를 제공하는지 고민해 보길 바랍니다. 만약 그렇다면, 선택적 수행에서도 커버리지가 제대로 동작할 수 있도록 개선하는 방안을 이미 고민하고 있다는 점에서 안심해도 됩니다.

## Pull/merge request 의견 {#pullmerge-request-comments}

> [!IMPORTANT] GIT 플랫폼 연동 필요\
> 자동으로 pull/merge request 의견을 받으려면, <0>Tuist 프로젝트</0>를 <1>Git 플랫폼</1>과 연동해야 합니다.

Tuist 프로젝트를 [GitHub](https://github.com)와 같은 Git 플랫폼과 연결하고, CI 워크플로우로 `tuist xcodebuild test`나 `tuist test`를 사용하기 시작하면, Tuist는 실행된 테스트와 건너뛴 테스트 정보를 포함하여 pull/merge request에 직접 의견을 남깁니다:
![Tuist Preview 링크를 사용하는 GitHub 앱 의견](/images/guides/features/selective-testing/github-app-comment.png)
