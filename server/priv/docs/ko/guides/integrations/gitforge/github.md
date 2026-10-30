---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git 포지 | 통합 | 가이드 | Tuist",
  "description": "향상된 워크플로를 위해 Tuist를 GitHub와 통합하는 방법을 알아보세요."
}
---
# GitHub 통합 {#github}

Git 리포지토리는 대부분의 소프트웨어 프로젝트에서 핵심입니다. Tuist는 GitHub와 통합하여 풀 리퀘스트 내에서 바로 Tuist 인사이트를 제공하고, 기본 브랜치 동기화와 같은 설정 작업을 줄여줍니다.

## 설정 {#setup}

조직의 `Integrations` 탭에서 Tuist GitHub 앱을 설치해야 합니다: ![통합 탭을 보여주는 이미지](/images/guides/integrations/gitforge/github/integrations.png)

GitHub에서 직접 앱을 설치할 수도 있습니다. 필요하면 Tuist에 로그인하고, Tuist가 설치에 대한 액세스 권한을 확인할 수 있도록 GitHub 앱에 권한을 부여한 후, 연결할 Tuist 조직을 선택하세요. 앱을 설치하는 GitHub 조직(또는 개인 GitHub 계정)의 소유자여야 합니다. 관리 중인 Tuist 조직과 개인 Tuist 계정만 표시됩니다. 계정이 하나뿐이면 선택 창 없이 자동으로 연결됩니다. Tuist에서 시작하면 조직이 이미 선택되어 있어 이 단계는 건너뜁니다.

그다음 GitHub 리포지토리와 Tuist 프로젝트 사이에 프로젝트 연결을 추가할 수 있습니다:

![프로젝트 연결 추가를 보여주는 이미지](/images/guides/integrations/gitforge/github/add-project-connection.png)

앱을 설치한 후에는 대시보드 없이도 프로젝트를 연결할 수 있습니다:

- **CLI:** `tuist project repository connect owner/name`, 그리고 `tuist project repository disconnect`로 연결을 제거합니다.
- **REST API:** `PUT` 및 `DELETE`를 `/api/projects/{account_handle}/{project_handle}/vcs-connection`에서 사용합니다.
- **Model Context Protocol:** `connect_project_repository` 및 `disconnect_project_repository` 도구.

리포지토리는 GitHub 앱 설치가 액세스할 수 있는 것이어야 하며, 프로젝트는 리포지토리의 기본 브랜치를 채택합니다. 계정 토큰에는 `project:admin:write` 범위가 필요합니다.

> [!TIP]
> **IP 허용 목록**
>
> GitHub 조직이 [IP 허용 목록](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization)을 사용하거나 GitHub 인스턴스가 방화벽 뒤에 있다면, 통합이 리포지토리와 통신할 수 있도록 Tuist의 <.localized_link href="/guides/server/network#outbound-ip-addresses">아웃바운드 IP 주소</.localized_link>를 허용 목록에 추가하세요.

### GitHub Enterprise Server {#github-enterprise-server}

Tuist는 자체 호스팅된 GitHub Enterprise Server(GHES) 인스턴스와도 통합됩니다. GitHub 통합 카드에서 **Enterprise server** 탭으로 전환하고, GHES 기본 URL(예: `https://github.example.com`)을 입력한 후 설치를 클릭하세요.

GitHub 앱은 단일 GitHub 인스턴스 범위로 제한되므로, Tuist는 github.com용 앱을 GHES에서 재사용할 수 없습니다. 대신 설치 버튼을 누르면 GitHub의 [앱 매니페스트 흐름](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)이 진행됩니다. GHES는 관리자가 인스턴스에 새로운 Tuist 앱을 등록하도록 안내한 후, 새 앱의 자격 증명을 Tuist에 전달합니다. Tuist는 해당 자격 증명을 설치별로 암호화하여 저장하고, 이후 모든 API 호출, 웹후크 서명, 리포지토리 링크에 사용합니다.

추가 Tuist 서버 구성은 필요하지 않습니다. 매니페스트 흐름이 모든 것을 자동으로 생성하고 프로비저닝합니다.

#### 앱 권한 및 웹후크 이벤트 {#github-app-permissions}

Tuist는 PR 댓글과 번들 크기 확인을 위해 다음 **리포지토리 권한**이 필요합니다:

| 권한 | 액세스 | 사용 목적 |
|---|---|---|
| 메타데이터(`metadata`) | 읽기 전용 | 기본 리포지토리 메타데이터; GitHub가 모든 앱에 요구 |
| 풀 리퀘스트(`pull_requests`) | 읽기 및 쓰기 | 풀 리퀘스트 읽기(헤드 커밋 SHA 포함), PR 댓글 나열, 게시 및 업데이트 |
| 검사(`checks`) | 읽기 및 쓰기 | 체크 실행 생성 및 업데이트(번들 크기 통과/실패 검사 포함) |

Tuist는 `check_run` 웹후크 이벤트를 사용하여 번들 크기 확인 작업을 처리합니다. 매니페스트 흐름이 이 구독을 자동으로 구성합니다.

자체 호스팅 Tuist 서버와 함께 github.com에서 앱을 수동으로 설정하려면 <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">자체 호스팅 가이드</.localized_link>를 참조하세요.

#### 브라우저 URL과 API URL 분리 {#separate-browser-and-api-urls}

엔지니어가 내부 호스트명으로 GitHub Enterprise에 접근하고 서드파티 서비스가 외부 프록시를 사용하는 경우, 설치를 클릭하기 전에 두 주소를 모두 구성하세요:

| 필드 | 예시 | 사용처 |
|---|---|---|
| **Server URL** | `https://github.internal.company.com` | 브라우저에서 앱 등록 및 설치, 그리고 Tuist에서 GitHub로 연결하는 링크에 사용 |
| **API URL** | `https://github-proxy.company.com/api/v3` | Tuist 서버에서 매니페스트 코드 교환, 액세스 토큰, 리포지토리 접근, PR 댓글 및 검사에 사용 |

API URL은 `/api/v3` 또는 프록시가 노출하는 해당 경로를 포함한 전체 REST API 기본 URL입니다. Tuist는 명시적인 API URL에 `/api/v3`를 추가하지 않습니다. 브라우저와 Tuist 모두에서 하나의 호스트명으로 작동한다면 이 필드를 비워 두세요. 기존 연결은 계속 `<Server URL>/api/v3`를 사용합니다.

두 주소 모두 **동일한 GitHub Enterprise 인스턴스**로 라우팅되어야 합니다. 브라우저는 Server URL에만 도달하면 되며 API 프록시는 필요하지 않습니다. Tuist 서버는 API URL에만 도달하면 되며 내부 브라우저 호스트명은 필요하지 않습니다.

외부 프록시의 경우:

- Tuist 서버가 신뢰하는 인증서와 공개 IP 주소로 해결되는 공개 DNS를 사용하는 HTTPS를 사용하세요. API URL 재정의는 Tuist의 사설 IP/SSRF 보호를 우회하지 않습니다. 재정의 대상은 `github.com`이나 `*.github.com` 엔드포인트가 아닌 귀하의 Enterprise 인스턴스여야 합니다.
- 모든 Tuist <.localized_link href="/guides/server/network#outbound-ip-addresses">아웃바운드 IP 주소</.localized_link>를 허용 목록에 추가하세요.
- Tuist가 사용하는 REST API 엔드포인트(`POST /api/v3/app-manifests/{code}/conversions`, `POST /api/v3/app/installations/{installation_id}/access_tokens` 포함)와 댓글 및 검사를 위한 리포지토리 API 엔드포인트를 전달하세요. 이들은 GitHub의 업스트림 경로이므로, 프록시가 다른 접두사를 노출한다면 이를 변환해야 합니다.
- HTTP 리다이렉트나 상호작용형 로그인 페이지 없이 GitHub로 요청을 전달하세요. Tuist는 Enterprise API 리다이렉트를 자동으로 따르지 않으므로 공개 IP 검사를 우회할 수 없습니다. 매니페스트 변환 엔드포인트는 Tuist가 앱 자격 증명을 갖기 전인 설정 중에 도달 가능해야 합니다. GitHub Actions 로그 다운로드는 예외입니다: Tuist는 HTTPS를 통한 서명된 아카이브 리다이렉트만 따르며, 모든 대상을 공개 IP로 확인하고 고정하며, 설치 토큰은 전달하지 않습니다.

GitHub는 내부 호스트명을 사용하여 페이지네이션 링크를 반환할 수 있습니다. Tuist는 구성된 GitHub 인스턴스의 링크를 API URL로 재기준화하여 프록시의 경로 접두사를 유지하며, 관련 없는 출처로의 링크는 거부됩니다.

별도로, GitHub는 웹후크를 `https://tuist.dev/webhooks/github`(또는 자체 호스팅 Tuist 서버의 `/webhooks/github`)로 전달할 수 있어야 합니다. 엔지니어는 브라우저 콜백을 완료하기 위해 Tuist로 돌아갈 수 있어야 합니다. API URL은 이러한 대상 중 어느 것도 변경하지 않습니다.

조직 관리자는 통합 카드의 **Save API URL**을 사용하여 기존 Enterprise 통합의 API URL을 변경하거나 지울 수 있습니다. 앱 재설치나 프로젝트 재연결이 필요하지 않습니다. 지우면 `<Server URL>/api/v3`로 복원됩니다. 저장은 URL 형식을 검증하지만 프록시 연결성은 검증하지 않습니다. 설치 조회가 캐시되므로 웹후크 처리가 변경된 주소를 반영하는 데 최대 1분이 걸릴 수 있으며, 이미 진행 중인 요청은 이전 주소를 계속 사용할 수 있습니다.

> [!NOTE]
> **호스팅된 Tuist 서버에서는 Enterprise 플랜 전용**
>
> 호스팅된 Tuist 서버(`https://tuist.dev`)에서는 GitHub Enterprise Server 통합이 **Enterprise** 플랜의 조직에만 제공됩니다. 자체 호스팅 Tuist 배포는 모든 플랜에서 사용할 수 있습니다.

## 풀/머지 리퀘스트 댓글 {#pull-merge-request-comments}

GitHub 앱은 최신 <.localized_link href="/guides/features/previews#pullmerge-request-comments">프리뷰</.localized_link> 또는 <.localized_link href="/guides/features/selective-testing#pullmerge-request-comments">테스트</.localized_link> 링크를 포함한 PR 요약을 담은 Tuist 실행 보고서를 게시합니다:

Tuist는 결과가 도착함에 따라 하나의 댓글을 업데이트합니다. Gradle 빌드는 각 루트 프로젝트와 요청된 작업 세트별로 별도로 표시되며, 동일한 작업을 다시 실행하면 해당 호출의 이전 결과가 대체됩니다. 전체 빌드 기록은 Tuist에서 계속 확인할 수 있습니다.

댓글은 기본적으로 활성화되어 기존 통합의 보고를 유지합니다. 프로젝트별로 댓글을 끄거나 켜려면 **Project Settings → Integrations**을 열고 **GitHub → Run report comments**를 토글하세요. 각 프로젝트에는 고유한 설정이 있으며, 리포지토리 연결은 조직 설정에서 관리됩니다.

댓글을 비활성화해도 빌드 또는 테스트 업로드, GitHub Actions 작업 요약, 리포지토리 연결 또는 기타 GitHub 통합 기능이 비활성화되지 않습니다. 기존 댓글은 삭제되지 않습니다.

![풀 리퀘스트 댓글을 보여주는 이미지](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **요구 사항**
>
> 댓글은 CI 실행이 <.localized_link href="/guides/integrations/continuous-integration#authentication">인증됨</.localized_link>일 때만 게시됩니다.

> [!NOTE]
> **Github_ref**
>
> PR 커밋이 아니라 예를 들어 GitHub 댓글로 트리거되는 custom workflow가 있는 경우, `GITHUB_REF` 변수가 `refs/pull/<PR_NUMBER>/merge` 또는 `refs/pull/<PR_NUMBER>/head`로 설정되었는지 확인해야 할 수 있습니다.
>
> 접두사가 붙은 `GITHUB_REF` 환경 변수와 함께 `tuist share`과 같은 관련 명령을 실행할 수 있습니다: <code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions 작업 요약 {#github-actions-job-summary}

Tuist CLI와 Gradle 플러그인은 GitHub Actions의 [작업 요약](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/)에 테스트 및 빌드 결과를 기록합니다. 요약에는 불안정한 테스트와 번들 크기 차이 등 더 풍부한 통찰력을 제공하는 Tuist의 전체 보고서 링크가 포함됩니다.

Gradle의 경우, 성공적으로 업로드된 각 빌드 또는 테스트 보고서는 자체 요약을 추가하며 `gradle/actions/setup-gradle`과 같은 도구가 작성한 다른 콘텐츠를 보존합니다. 이는 작업 요약 지원을 포함하는 플러그인 버전이 필요하며, 이전 Gradle 플러그인 버전은 GitHub 앱의 PR 댓글을 통해서만 보고합니다. 작업 요약에는 GitHub 앱 연결이 필요하지 않으며, **Run report comments**를 비활성화해도 영향을 받지 않습니다.

GitHub Actions 요약 대상이 사용 가능한 경우, Gradle은 `uploadInBackground`이 활성화되어 있더라도 업로드와 요약을 기다린 후 종료됩니다. GitHub는 워크플로우 단계가 완료될 때 요약을 캡처합니다.

![GitHub Actions 작업 요약에 표시된 Tuist 실행 보고서를 보여주는 이미지](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

이는 [머지 큐](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)와 함께 사용할 때 특히 유용합니다. 머지 큐 실행은 풀 리퀘스트에 첨부되지 않으므로 댓글이 게시되지 않지만, 작업 요약은 여전히 결과를 표시합니다.

> [!NOTE]
> **요구 사항**
>
> 작업 요약에는 성공적인 보고서 업로드가 필요합니다. 호스팅된 Tuist 서버에서는 CI 실행이 <.localized_link href="/guides/integrations/continuous-integration#authentication">인증됨</.localized_link>이어야 합니다. 자체 호스팅 인스턴스는 네트워크 신뢰 보고서 게시가 활성화된 경우 자격 증명 없는 보고서도 수용할 수 있습니다.
