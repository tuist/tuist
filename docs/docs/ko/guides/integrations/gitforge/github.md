---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHub 통합 {#github}

Git 리포지토리는 대부분의 소프트웨어 프로젝트의 중심입니다. 당사는 GitHub와 통합하여 풀 리퀘스트에서 바로 Tuist 인사이트를 제공하고
기본 브랜치 동기화와 같은 일부 구성을 절약할 수 있습니다.

## 설정 {#setup}

조직의 `통합` 탭에서 Tuist GitHub 앱을 설치해야 합니다: ![통합 탭을 표시하는
이미지](/images/guides/integrations/gitforge/github/integrations.png)

그런 다음 GitHub 리포지토리와 Tuist 프로젝트 사이에 프로젝트 연결을 추가할 수 있습니다:

![프로젝트 연결 추가를 보여주는
이미지](/images/guides/integrations/gitforge/github/add-project-connection.png)

## 요청 댓글 풀/병합 {#pull-merge-request-comments}

GitHub 앱은 최신
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">previews</LocalizedLink>
또는
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">tests</LocalizedLink>에
대한 링크를 포함하여 PR 요약이 포함된 Tuist 실행 보고서를 게시합니다:

![풀 리퀘스트 댓글을 표시하는
이미지](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
댓글은 CI 실행이
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">인증</LocalizedLink>된
경우에만 게시됩니다.
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
PR 커밋에서 트리거되지 않는 사용자 지정 워크플로우(예: GitHub 댓글)가 있는 경우 `GITHUB_REF` 변수가
`refs/pull/<pr_number>/merge` 또는 `refs/pull/<pr_number>/head` 로 설정되어 있는지 확인해야 할
수 있습니다.</pr_number></pr_number>

`tuist share` 와 같이 관련 명령을 실행하고 `GITHUB_REF` 환경 변수를 접두사로 붙일 수 있습니다:
<code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist
share</code>
<!-- -->
:::
