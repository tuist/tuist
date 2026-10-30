---
{
  "title": "Origin",
  "titleTemplate": ":title | Git 포지 | 통합 | 가이드 | Tuist",
  "description": "네이티브 Cursor Origin 리포지토리를 Tuist 풀 리퀘스트 보고서에 연결합니다."
}
---
# Origin 통합 {#origin}

Tuist는 네이티브 [Cursor Origin](https://cursor.com/docs/api/origin) 저장소의 풀 리퀘스트에 빌드, 테스트, 미리보기 및 번들 보고서를 게시할 수 있습니다. 업로드마다 새 댓글을 게시하는 대신 앱의 기존 Tuist 실행 보고서를 업데이트합니다.

앱을 설치해도 빌드나 테스트가 실행되지 않습니다. 기존 워크플로는 계속 결과를 Tuist에 업로드하며, 이 통합은 해당 결과를 풀 리퀘스트로 가져옵니다.

## 설정 {#setup}

Tuist 계정 관리자는 **Settings → Integrations**을 열고, Origin 카드에서 **Install Origin App**을 선택한 후 Cursor에서 액세스를 승인해야 합니다. Tuist가 액세스해야 하는 Origin 계정 또는 네임스페이스와 저장소를 선택한 다음 Tuist로 돌아갑니다. 연결은 개별 프로젝트가 아닌 Tuist 계정에 속합니다.

Origin에서 직접 앱을 설치할 수도 있습니다. 액세스를 승인한 후 필요하면 Tuist에 로그인하고 연결할 조직을 선택하세요. 관리 중인 조직과 개인 계정만 표시됩니다. 계정이 하나만 있으면 Tuist는 선택기를 표시하지 않고 자동으로 연결합니다. Tuist에서 시작하면 조직이 이미 선택되어 있으므로 이 단계는 건너뜁니다.

저장소 선택 모달을 열려면 **Add new project connection**을 선택하세요. 연결되지 않은 Tuist 프로젝트와 연결된 Origin 계정에서 발견된 저장소 중 하나를 선택한 다음 **Create Connection**을 선택하세요. 여러 Origin 계정이 연결되어 있으면 먼저 계정을 선택하세요. 네이티브 Origin 저장소만 연결할 수 있습니다. Tuist는 프로젝트를 연결하기 전에 풀 리퀘스트 액세스를 다시 확인하고 저장소의 기본 브랜치를 채택합니다.

새 탭에서 Cursor의 동의 흐름을 열고 저장소 액세스를 조정하거나 다른 Origin 계정을 연결하려면 **Manage integration**을 사용하세요. 저장소 로드 실패 시 성공적인 빈 저장소 목록과 구분되어 **Retry**가 표시됩니다.

결과 업로드를 인증하려면 <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>을 사용하세요.

## 보고서 및 권한 {#reports-and-permissions}

앱을 승인할 때 저장소 연결 및 보고서 게시에 필요한 권한을 부여합니다:

| 권한 | 사용 목적 |
| --- | --- |
| 풀 리퀘스트: 읽기 | 보고된 커밋에 대한 열린 풀 리퀘스트를 찾습니다. |
| 풀 리퀘스트 리뷰: 읽기 및 쓰기 | Tuist 실행 보고서 댓글을 읽고, 게시하고, 업데이트합니다. |
| 저장소 메타데이터: 읽기 | 저장소와 기본 브랜치를 검색합니다. Origin에 의해 자동으로 포함됩니다. |

Tuist는 소스 코드에 대한 액세스나 풀 리퀘스트 병합 권한이 필요하지 않습니다.

결과를 풀 리퀘스트와 연결하려면 업로드에 저장소의 Origin 클론 URL, Git 참조 및 전체 커밋 SHA가 포함되어야 합니다. Tuist는 이러한 정보가 현재 헤드 커밋에서 단일 열린 풀 리퀘스트를 식별할 때만 보고서를 게시합니다. 대체된 커밋의 결과는 현재 보고서를 덮어쓰지 않습니다.

Origin 카드는 프로젝트 대 저장소 연결을 나열합니다. 앱을 제거하지 않고 보고를 중지하려면 프로젝트 연결에서 **Manage → Remove connection**을 선택하세요. Cursor에서 앱을 제거하여 액세스를 취소하세요. Tuist는 설치 알림을 처리할 때 설치 및 프로젝트 연결을 제거합니다.

## 자체 호스팅 서버 {#server-configuration}

자체 Tuist 서버를 호스팅하는 경우 먼저 배포용 Origin 앱을 등록하고 구성하세요. <.localized_link href="/guides/server/self-host/server#platform-origin">Origin self-hosting instructions</.localized_link>를 따른 다음 위의 설정 단계로 돌아가 계정과 프로젝트를 연결하세요.
