---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# 선택적 테스트 {#selective-testing}

프로젝트가 성장함에 따라 테스트의 양도 늘어납니다. 오랫동안 모든 PR 또는 푸시에서 모든 테스트를 실행하거나 `메인` 으로 푸시하는 데 수십
초가 걸렸습니다. 하지만 이 솔루션은 팀에서 수행할 수 있는 수천 개의 테스트에 맞게 확장되지 않습니다.

CI에서 테스트를 실행할 때마다 변경 사항에 관계없이 모든 테스트를 다시 실행하는 경우가 대부분입니다. 튜이스트의 선택적 테스트는
<LocalizedLink href="/guides/features/projects/hashing">해싱 알고리즘</LocalizedLink>을
기반으로 마지막 테스트 실행 성공 이후 변경된 테스트만 실행하여 테스트 실행 속도를 크게 높일 수 있도록 도와줍니다.

선택적 테스트는 모든 Xcode 프로젝트를 지원하는 `xcodebuild` 에서 작동하거나, Tuist로 프로젝트를 생성하는 경우
<LocalizedLink href="/guides/features/cache">binary 캐시</LocalizedLink>와의 통합 등 몇
가지 추가 편의를 제공하는 `tuist test` 명령을 대신 사용할 수 있습니다. 선택적 테스트를 시작하려면 프로젝트 설정에 따른 지침을
따르세요:

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">Generated project</LocalizedLink>

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
테스트와 소스 간의 코드 내 종속성을 감지할 수 없기 때문에 선택적 테스트의 최대 세분성은 대상 수준입니다. 따라서 선택적 테스트의 이점을
극대화하려면 대상을 작고 집중적으로 유지하는 것이 좋습니다.
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
테스트 커버리지 도구는 전체 테스트 스위트가 한 번에 실행된다고 가정하기 때문에 선택적 테스트 실행과 호환되지 않으며, 이는 테스트 선택을
사용할 때 커버리지 데이터가 현실을 반영하지 못할 수 있음을 의미합니다. 이는 알려진 한계이며, 그렇다고 해서 잘못하고 있는 것은 아닙니다.
팀에서는 이러한 상황에서 커버리지가 여전히 의미 있는 인사이트를 제공하고 있는지 생각해 보시고, 만약 그렇다면 향후 선택적 실행에서 커버리지가
제대로 작동하도록 하는 방법에 대해 이미 고민하고 있으니 안심하시기 바랍니다.
<!-- -->
:::


## 요청 댓글 풀/병합 {#pullmerge-request-comments}

::: warning Git과 통합 필요
<!-- -->
자동 풀/병합 요청 코멘트를 받으려면
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist 프로젝트</LocalizedLink>를 <LocalizedLink href="/guides/server/authentication">Git 플랫폼</LocalizedLink>과 통합하세요.
<!-- -->
:::

튜이스트 프로젝트가 [GitHub](https://github.com)와 같은 Git 플랫폼과 연결되고 `tuist xcodebuild
test` 또는 `tuist test` 를 CI 워크플로우의 일부로 사용하기 시작하면 튜이스트는 풀/머지 요청에 실행된 테스트와 건너뛴 테스트를
포함한 코멘트를 직접 게시합니다: ![튜이스트 미리보기 링크가 포함된 GitHub 앱
코멘트](/images/guides/features/selective-testing/github-app-comment.png).
