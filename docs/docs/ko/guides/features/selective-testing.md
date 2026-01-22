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

To run tests selectively with your
<LocalizedLink href="/guides/features/projects">generated
project</LocalizedLink>, use the `tuist test` command. The command
<LocalizedLink href="/guides/features/projects/hashing">hashes</LocalizedLink>
your Xcode project the same way it does for the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink>, and on success, it persists the hashes to determine what
has changed in future runs. In future runs, `tuist test` transparently uses the
hashes to filter down the tests and run only the ones that have changed since
the last successful test run.

`tuist test` integrates directly with the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink> to use as many binaries from your local or remote storage
to improve the build time when running your test suite. The combination of
selective testing with module caching can dramatically reduce the time it takes
to run tests on your CI.

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

Once your Tuist project is connected with your Git platform such as
[GitHub](https://github.com), and you start using `tuist test` as part of your
CI workflow, Tuist will post a comment directly in your pull/merge requests,
including which tests were run and which skipped: ![GitHub app comment with a
Tuist Preview
link](/images/guides/features/selective-testing/github-app-comment.png)
