---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHub 통합 {#github}

Git 저장소는 대부분의 소프트웨어 프로젝트에서 핵심 역할을 합니다. 우리는 GitHub와 연동하여 풀 리퀘스트 내에서 바로 Tuist
인사이트를 제공하고, 기본 브랜치 동기화와 같은 설정을 간소화합니다.

## 설정 {#setup}

조직의 GitHub 통합 설정( `)에서 '` ' 탭에 Tuist GitHub 앱을 설치해야 합니다: ![통합 탭을 보여주는
이미지](/images/guides/integrations/gitforge/github/integrations.png)

그 후 GitHub 저장소와 Tuist 프로젝트 간 프로젝트 연결을 추가할 수 있습니다:

![프로젝트 연결 추가를 보여주는
이미지](/images/guides/integrations/gitforge/github/add-project-connection.png)

## Pull/병합 요청 댓글 {#pullmerge-request-comments}

GitHub 앱은 Tuist 실행 보고서를 게시하며, 여기에는 최신
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">프리뷰</LocalizedLink>
또는
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">테스트</LocalizedLink>
링크를 포함한 PR 요약이 포함됩니다:

![풀 리퀘스트 코멘트를 보여주는
이미지](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
CI 실행이
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">인증</LocalizedLink>된
경우에만 댓글이 게시됩니다.
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
PR 커밋이 아닌 GitHub 댓글 등에 트리거되는 커스텀 워크플로를 사용하는 경우, `GITHUB_REF` 변수가 다음 중 하나로 설정되어
있는지 확인해야 합니다: `refs/pull/<pr_number>/merge` 또는
`refs/pull/<pr_number>/head`</pr_number></pr_number>

관련 명령어(예: `tuist share`)를 실행할 때, 환경 변수 `GITHUB_REF` 를 접두사로 붙여 사용하세요:
<code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist
share</code>
<!-- -->
:::
