---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# 선택적 테스트 {#selective-testing}

프로젝트가 성장함에 따라 테스트 수도 증가합니다. 오랫동안 `메인 브랜치에 대한 모든 PR이나 푸시(` )에 대해 모든 테스트를 실행하는 데
수십 초가 소요되었습니다. 그러나 이 솔루션은 팀이 보유할 수 있는 수천 개의 테스트까지 확장되지 않습니다.

CI에서 테스트를 실행할 때마다 변경 사항과 상관없이 모든 테스트를 다시 실행하는 경우가 대부분입니다. Tuist의 선택적 테스트는
<LocalizedLink href="/guides/features/projects/hashing">해싱 알고리즘</LocalizedLink>을
기반으로 마지막 성공적인 테스트 실행 이후 변경된 테스트만 실행함으로써 테스트 실행 속도를 획기적으로 높여줍니다.

<LocalizedLink href="/guides/features/projects">생성된 프로젝트</LocalizedLink>로 테스트를
선택적으로 실행하려면 `tuist test` 명령어를 사용하세요. 이 명령어는
<LocalizedLink href="/guides/features/cache/module-cache">모듈 캐시</LocalizedLink>와
동일한 방식으로 Xcode 프로젝트에
<LocalizedLink href="/guides/features/projects/hashing">해시</LocalizedLink>를
생성하며, 성공 시 해시를 저장하여 향후 실행 시 변경된 부분을 판단합니다. 향후 실행 시 `tuist test` 는 해시를 투명하게 활용하여
테스트를 필터링하고, 마지막 성공적인 테스트 실행 이후 변경된 테스트만 실행합니다.

`tuist 테스트` 는 <LocalizedLink href="/guides/features/cache/module-cache">모듈
캐시</LocalizedLink>와 직접 연동되어 로컬 또는 원격 저장소의 바이너리를 최대한 활용하여 테스트 스위트 실행 시 빌드 시간을
단축합니다. 선택적 테스트와 모듈 캐싱의 조합은 CI 환경에서 테스트 실행 시간을 획기적으로 줄일 수 있습니다.

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
테스트와 소스 간의 코드 내 의존성을 감지할 수 없기 때문에 선택적 테스트의 최대 세분화 수준은 대상 수준입니다. 따라서 선택적 테스트의 이점을
극대화하려면 대상의 규모를 작고 집중적으로 유지할 것을 권장합니다.
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
테스트 커버리지 도구는 전체 테스트 스위트가 한 번에 실행된다고 가정하므로 선택적 테스트 실행과 호환되지 않습니다. 즉, 테스트 선택 시
커버리지 데이터가 실제 상황을 반영하지 못할 수 있습니다. 이는 알려진 한계 사항이며, 사용자의 잘못이 아님을 알려드립니다. 팀에서는 이러한
상황에서 커버리지가 여전히 의미 있는 통찰력을 제공하는지 검토해 보시길 권장합니다. 만약 그렇다면, 향후 선택적 실행과 커버리지가 제대로
작동하도록 하는 방안을 이미 검토 중이니 안심하셔도 됩니다.
<!-- -->
:::


## Pull/병합 요청 댓글 {#pullmerge-request-comments}

::: warning Git과 통합 필요
<!-- -->
자동으로 Pull/병합 요청 댓글을 받으려면
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist
프로젝트</LocalizedLink>를 <LocalizedLink href="/guides/server/authentication">Git
플랫폼</LocalizedLink>과 통합하세요.
<!-- -->
:::

Tuist 프로젝트를 [GitHub](https://github.com)과 같은 Git 플랫폼에 연결하고 CI 워크플로우의 일환으로 `tuist
test` 를 사용하기 시작하면, Tuist는 실행된 테스트와 건너뛴 테스트를 포함하여 풀/병합 요청에 직접 코멘트를 게시합니다: ![Tuist
Preview 링크가 포함된 GitHub 앱
코멘트](/images/guides/features/selective-testing/github-app-comment.png)
