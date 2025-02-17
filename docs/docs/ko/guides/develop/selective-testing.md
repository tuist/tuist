---
title: Selective testing
titleTemplate: :title · Develop · Guides · Tuist
description: 마지막 성공한 테스트 수행 이후에 변경된 테스트만 수행하기 위해 선택적 테스트를 사용합니다.
---

# Selective testing {#selective-testing}

프로젝트가 커질 수록 테스트 수도 증가합니다. 오랜 시간동안 모든 PR 또는 `main`에 푸시할 때마다 전체 테스트를 수행하면 수 초의 시간이 걸렸습니다. 하지만 이 방법은 팀이 가진 수천 개의 테스트에는 적합하지 않습니다.

On every test run on the CI, you most likely re-run all the tests, regardless of the changes. Tuist's selective testing helps you to drastically speed up running the tests themselves by running only the tests that have changed since the last successful test run based on our <LocalizedLink href="/guides/develop/projects/hashing">hashing algorithm</LocalizedLink>.

Selective testing works with `xcodebuild`, which supports any Xcode project, or if you generate your projects with Tuist, you can use the `tuist test` command instead that provides some extra convenience such as integration with the <LocalizedLink href="/guides/develop/build/cache">binary cache</LocalizedLink>. To get started with selective testing, follow the instructions based on your project setup:

- <LocalizedLink href="/guides/develop/selective-testing/xcodebuild">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/develop/selective-testing/generated-project">Generated project</LocalizedLink>

> [!WARNING] 모듈 VS 파일 단위 세분화\
> 테스트와 소스 코드 간의 의존성을 코드 내에서 파악할 수 없으므로 선택적 테스트의 세분화는 파일 단위에서만 가능합니다. 따라서 선택적 테스트의 이점을 극대화 하려면 파일을 작고 집중적으로 유지하길 권장합니다.

## Pull/merge request 의견 {#pullmerge-request-comments}

> [!IMPORTANT] INTEGRATION WITH GIT PLATFORM REQUIRED
> To get automatic pull/merge request comments, integrate your <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist project</LocalizedLink> with a <LocalizedLink href="/server/introduction/integrations#git-platforms">Git platform</LocalizedLink>.

Once your Tuist project is connected with your Git platform such as [GitHub](https://github.com), and you start using `tuist xcodebuild test` or `tuist test` as part of your CI wortkflow, Tuist will post a comment directly in your pull/merge requests, including which tests were run and which skipped:
![GitHub app comment with a Tuist Preview link](/images/guides/develop/selective-testing/github-app-comment.png)
