---
{
  "title": "Entire",
  "titleTemplate": ":title | Git 포지 | 통합 | 가이드 | Tuist",
  "description": "Tuist 빌드, 테스트, 번들 및 미리보기 인사이트를 Entire Trails에 게시합니다."
}
---
# Entire 통합 {#entire}

Tuist는 [Entire](https://entire.com) 저장소의 공개 및 초안 [Trails](https://docs.entire.com/guides/trails/overview)에 빌드, 테스트, 미리보기 및 번들 인사이트를 게시할 수 있습니다. 각 Trail에는 실행 보고서, 실패 및 불안정한 테스트에 대한 전체 변경 사항 발견 항목, 그리고 새 인사이트가 도착할 때마다 Tuist가 업데이트하는 요약 댓글이 포함된 Tuist 게이트가 제공됩니다. 매번 업로드할 때마다 새 댓글을 게시하는 대신 기존 댓글을 업데이트합니다.

플러그인을 설치해도 빌드나 테스트가 실행되지 않습니다. 기존 워크플로는 계속 결과를 Tuist에 업로드하며, 이 통합은 해당 결과를 여러분의 Trails로 가져옵니다.

## 설정 {#setup}

Tuist 계정 관리자가 플러그인을 설치한 후, <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> 및 <.localized_link href="/guides/integrations/gitforge/origin">Origin</.localized_link> 통합과 마찬가지로 저장소를 Tuist 프로젝트에 연결합니다.

1. 계정의 **Settings → Integrations**을 엽니다.
2. Entire 카드에서 **Install Entire plugin**을 선택합니다. Tuist와 공유하려는 Entire 프로젝트 및 저장소를 선택합니다.

   ![계정 통합에서 Entire 플러그인 설치](/images/guides/integrations/gitforge/entire/integrations.png)

3. Tuist로 돌아와 **Add new project connection**을 선택합니다. **Choose repository to connect to**에서 Tuist 프로젝트와 Entire 저장소를 선택한 후 **Create Connection**을 선택합니다. 사용 가능한 Tuist 프로젝트가 하나만 있는 경우 자동으로 선택됩니다.

   ![Tuist 프로젝트를 Entire 저장소에 연결](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. 기존의 인증된 Tuist 명령(예: <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> 사용)을 사용하여 CI에서 결과 업로드를 계속합니다. Tuist는 결과를 각 Trail의 현재 헤드 커밋과 일치시키므로 Entire 전용 플래그가 필요하지 않습니다.

Tuist 프로젝트는 GitHub 연결을 유지하면서 Entire에도 게시할 수 있으며, 이는 Entire 저장소가 GitHub 저장소를 미러링할 때 유용합니다. 이 통합은 Tuist의 CI 실행기를 필요로 하지 않으며 CI 제공자를 변경하지도 않습니다.

## 보고서 및 권한 {#reports-and-permissions}

플러그인을 설치할 때, Trails를 찾고 보고서를 게시하는 데 필요한 권한을 부여합니다:

| 권한 | 사용 목적 |
| --- | --- |
| 저장소 내용: 읽기 | Trail 이벤트를 수신하고 헤드 커밋이 있는 공개 및 초안 Trails를 찾습니다. |
| 검사: 쓰기 | Trail의 헤드 커밋에 Tuist 게이트를 게시합니다. |
| 발견 항목: 쓰기 | 실패한 테스트와 불안정한 테스트를 발견 항목으로 게시하고, 새 보고서가 대체하는 발견 항목을 해결합니다. |
| 토론: 쓰기 | 요약 댓글을 게시하고 업데이트합니다. 이 권한이 없어도 Tuist는 게이트와 발견 항목을 계속 게시합니다. |

Tuist는 소스 코드에 대한 쓰기 액세스나 Trails를 병합할 수 있는 권한이 필요하지 않습니다.

Tuist는 각 Trail에 세 가지 항목을 게시합니다:

- **게이트:** Tuist 검사는 **Gates** 아래에 실행 보고서 및 Tuist의 프로젝트 링크와 함께 표시됩니다. GitHub 미러의 **Checks** 게이트와 별도로 Tuist 플러그인 아래에 나열됩니다. 업로드된 결과가 예상된 모든 CI 작업이 완료되었는지 Tuist에 알리지 않기 때문에 `neutral` 결론으로 완료되며, Entire에서는 이를 통과로 표시합니다. 발견 항목이 있더라도 병합을 차단하지 않으므로, 통과/실패 강제를 위해 CI 제공자의 필수 검사를 유지하세요.
- **발견 항목:** 실패한 테스트와 불안정한 테스트는 Tuist의 테스트 케이스로 연결되는 전체 변경 사항 발견 항목으로 표시됩니다. 발견 항목은 Entire의 Agent 검토 게이트에 기여하지 않습니다.
- **요약 댓글:** GitHub 및 Origin의 풀 리퀘스트 댓글과 마찬가지로, 각 프로젝트는 Trail당 하나의 Tuist 실행 보고서 댓글을 유지합니다. 삭제하면 다음 보고서가 다시 게시합니다.

새 결과가 도착하면 Tuist는 Trail의 현재 헤드 커밋에 대한 업데이트된 보고서를 게시하고 대체되는 발견 항목을 해결합니다. 재시도는 중복 리뷰, 발견 항목 또는 댓글을 생성하지 않으며, 이는 Entire의 게시 응답이 손실된 경우에도 포함됩니다. Trail을 열거나 다시 열면 헤드 커밋에 대해 이미 업로드된 결과를 가져옵니다. 현재 헤드 커밋에 대한 결과가 없으면 Tuist는 아무것도 새로 게시하지 않으므로, 이전 커밋의 게이트는 새 헤드의 요구 사항을 충족할 수 없습니다. 종료되거나 병합된 Trails는 업데이트되지 않습니다.

Entire 카드에는 프로젝트 대 저장소 연결 목록이 표시됩니다. 플러그인을 제거하지 않고 보고를 중지하려면 프로젝트 연결에서 **Manage → Remove connection**을 선택합니다. 이미 게시된 보고서는 Entire에 남아 있으며, 다시 연결하면 새 보고서가 시작됩니다. 플러그인의 저장소 액세스를 변경하거나 제거하려면 Entire의 프로젝트 **Plugins** 설정을 사용하세요.

## 자체 호스팅 서버 {#server-configuration}

자체 Tuist 서버를 호스팅하는 경우, 먼저 배포용 Entire 플러그인을 등록하고 구성하세요. <.localized_link href="/guides/server/self-host/server#platform-entire">Entire 자체 호스팅 지침</.localized_link>을 따른 후, 위의 설정 단계로 돌아가 계정과 프로젝트를 연결하세요.
