---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · 에이전트 코딩 · 기능 · 가이드 · Tuist",
  "description": "Tuist의 MCP 엔드포인트를 통해 AI 에이전트가 테스트 인사이트 등에 접근할 수 있게 하세요."
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro)은 인공지능 에이전트가 외부 서비스 및 데이터 소스와 상호작용할 수 있도록 하는 오픈 표준입니다. 이를 통해 [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/)와 같은 애플리케이션과 [Zed](https://zed.dev), [Cursor](https://www.cursor.com), [Visual Studio Code](https://code.visualstudio.com)와 같은 편집기가 Tuist와 연동됩니다.

Tuist는 `https://tuist.dev/mcp`에 서버 측 Model Context Protocol 엔드포인트를 호스팅합니다. 클라이언트를 여기에 연결하면 에이전트가 테스트 인사이트, 불안정한 테스트 분석 등을 포함한 Tuist 프로젝트 데이터에 접근할 수 있습니다. 대부분의 도구는 인증된 사용자가 대시보드에서 이미 볼 수 있는 Tuist 데이터를 읽습니다. 모든 도구는 읽기 전용인지, 복구가 어려운 변경을 일으킬 수 있는지(`destructiveHint`), Tuist 외부에 도달할 수 있는지(`openWorldHint`)를 나타내는 주석을 광고합니다. 상태를 변경하는 도구는 계정 또는 프로젝트에 대한 사용자의 권한에 따라 제한되며 다음과 같습니다:

- **조직 및 멤버**: `create_organization`, `add_organization_member`(기존 사용자를 추가하거나 멤버의 역할을 변경), `invite_organization_member`(모든 주소로 초대 이메일 발송), 그리고 `cancel_organization_invitation`.
- **프로젝트**: `create_project`, `start_project_logo_upload` 및 `complete_project_logo_upload`(로고 교체), `connect_project_repository` 및 `disconnect_project_repository`(GitHub 저장소 링크).
- **테스트**: `update_test_case`(테스트 케이스를 음소거, 건너뛰기, 다시 활성화하거나 불안정하다고 표시하며, 변경 사항은 계정의 웹훅 엔드포인트에 전달될 수 있음).
- **알림 규칙**: `create_notification_rule`, `update_notification_rule`, 그리고 `delete_notification_rule`.
- **CI 러너**: `create_runner_profile`, `update_runner_profile`(캐시 볼륨을 저장할 작업을 제한하면 대기 중인 저장이 삭제됨), `delete_runner_profile`, 그리고 `delete_runner_volume`(볼륨의 저장된 내용을 삭제).
- **샌드박스**: `create_sandbox`, `pause_sandbox`, `resume_sandbox`, `extend_sandbox`, `archive_sandbox`, 그리고 `delete_sandbox`(디스크를 삭제).
- **피드백**: `report_feedback`(도구나 프롬프트에 대한 보고서를 Tuist 팀에 전송; tuist.dev에서만 가능).
- **조직 AI**: `save_organization_ai_model`, `remove_organization_ai_model`, `set_organization_ai_default_model`, `save_organization_ai_task_route`, `remove_organization_ai_task_route`, 그리고 `remove_organization_ai_provider`(공급자의 키와 모델을 삭제하고 Anthropic에서 연결된 Claude 조직을 연결 해제).
- **에이전트 통합**: `connect_amp_workspace`(워크스페이스의 orbs가 계정에 CI 액세스 권한을 부여), `disconnect_amp_workspace`, 그리고 `connect_claude_environment`(Claude Managed Agents 환경이 Tuist 샌드박스에서 세션을 실행하도록 허용).

`add_organization_member`, `cancel_organization_invitation`, `complete_project_logo_upload`, `disconnect_project_repository`, `update_test_case`, `update_notification_rule`, `delete_notification_rule`, `update_runner_profile`, `delete_runner_profile`, `delete_runner_volume`, `delete_sandbox`, `disconnect_amp_workspace`, `remove_organization_ai_provider`, `remove_organization_ai_model`, 그리고 `remove_organization_ai_task_route`는 기존 상태를 대체하거나 제거하므로 `destructiveHint: true`을 광고합니다. `invite_organization_member`, `update_test_case`, `connect_claude_environment`, `remove_organization_ai_provider`, 그리고 `report_feedback`는 이메일을 보내거나, 외부 웹훅 엔드포인트에 알림을 보내거나, Anthropic을 호출하거나, Tuist 팀에 보고서를 전송하므로 `openWorldHint: true`을 광고합니다.

개인용 Claude 및 ChatGPT 구독은 대시보드의 AI 설정에서만 연결되므로, 구독 토큰과 로그인 정보는 Model Context Protocol 클라이언트를 통해 전달되지 않습니다. 계정 설정 도구는 사용자 인증이 필요합니다. 프로젝트 토큰이나 일반 계정 토큰으로는 사용할 수 없습니다. 사용자가 브라우저에서 클라이언트를 승인하거나 `auth.md` 등록을 주장(claim)하면, Tuist는 해당 자격 증명을 Model Context Protocol 엔드포인트에서만 사용자와 연관시켜 설정 도구가 요청된 워크플로를 완료할 수 있도록 합니다. 누구나 클라이언트를 등록할 수 있으므로, 브라우저에서 하나를 승인하면 클라이언트 이름과 액세스가 전송되는 호스트를 명시한 동의 페이지가 표시되며, Tuist는 사용자가 거기서 승인한 후에만 자격 증명을 발급합니다. 범위를 요청하지 않는 클라이언트는 `mcp` 범위 그룹을 받습니다. 클라이언트는 `S256`와 함께 PKCE를 사용해야 하며, 리디렉션 URI는 HTTPS, 루프백 주소의 HTTP 또는 애플리케이션 자체 스키마를 사용해야 합니다.

Tuist는 [2026-07-28 프로토콜](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)을 구현합니다. 요청은 무상태(stateless)입니다: 클라이언트는 각 요청과 함께 프로토콜 메타데이터를 전송하며 초기화 없이 도구를 직접 호출할 수 있습니다. `server/discover`는 서버의 식별자, 기능, 지원 버전 및 지침을 반환합니다. 세션 식별자나 독립적인 이벤트 스트림은 없습니다. 2025-06-18 또는 2025-03-26 초기화 흐름을 사용하는 클라이언트도 계속 지원되며, 이들 역시 서버 세션 없이 작동합니다.

## Model Context Protocol 대 스킬

Model Context Protocol 도구와 <.localized_link href="/guides/features/agentic-coding/skills">스킬</.localized_link>은 수행하는 작업이 중복될 수 있습니다. 현재 두 가지 간의 중복을 고려하여, 동일한 흐름에서 둘을 혼합하기보다 워크플로당 하나의 접근 방식을 선택하고 일관되게 사용하세요.

플러그인 설치를 지원하는 클라이언트의 경우, <.localized_link href="/guides/features/agentic-coding/plugins">Tuist 플러그인</.localized_link>을 사용하여 둘을 함께 설치하세요.

## 구성

클라이언트에 `https://tuist.dev/mcp`을 원격 Model Context Protocol 서버로 추가하세요. 서버의 초기화 지침과 공개 서버 카드는 동적 클라이언트 등록과 표준 브라우저 인증 흐름을 갖춘 OAuth 2.0을 인라인으로 설명하며, 에이전트가 외부 인증 문서를 가져오거나 따르도록 요구하지 않습니다. 이러한 서버 전체 지침은 워크플로 안내를 일반적으로 유지합니다: 도구 인증은 로컬 명령줄 도구나 빌드 시스템 통합을 인증하지 않으며, 에이전트는 관련 Tuist 도구를 통해 요청된 변경 사항을 확인해야 합니다. 빌드 시스템별 설정 및 인증 검사는 통합 가이드와 프롬프트에 문서화되어 있습니다. Tuist는 여전히 [Open Authorization](https://oauth.net/2/) 검색 메타데이터와 현재의 [auth.md 프로토콜](https://workos.com/auth-md)을 `https://tuist.dev/auth.md`에서 별도로 광고합니다.

조직 중 하나가 싱글 사인온(SSO)을 강제하는 경우, 브라우저에서 클라이언트를 승인하려면 해당 조직을 통해 로그인한 세션이 필요하며, Tuist는 필요시 먼저 제공자로 사용자를 보냅니다. <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">싱글 사인온</.localized_link>을 참조하세요.

엔드포인트는 이전의 세션 기반 라이프사이클과 함께 무상태 `2026-07-28` Model Context Protocol 요청 라이프사이클(예: `server/discover`)을 수용합니다. 기존 클라이언트는 현재 연결 방법을 계속 사용할 수 있습니다.

Model Context Protocol 이벤트를 지원하는 클라이언트는 프로젝트 이벤트에 구독할 수 있습니다. 사용 가능한 이벤트 및 전달 요구 사항에 대해서는 [이벤트](#events)를 참조하세요.

원격 브라우저 인증을 이미 지원하는 클라이언트는 브라우저에서 계속 인증할 수 있습니다. `auth.md`을 지원하는 클라이언트와 에이전트는 익명으로 등록하거나, 신뢰할 수 있는 제공자 신원 어설션을 제시하거나, 서비스 인증 이메일 클레임을 시작할 수 있습니다. 등록 시 Tuist가 서명한 신원 어설션이 반환되며, 에이전트는 이를 표준 토큰 엔드포인트에서 교환하여 1시간 유효한 액세스 토큰을 받습니다. Tuist는 공개 서명 키를 게시하며 표준 토큰 취소와 제공자 보안 이벤트 전달을 지원합니다.

인증되지 않은 에이전트는 Model Context Protocol 엔드포인트가 반환하는 `WWW-Authenticate` 헤더를 읽고, 보호된 리소스 메타데이터와 인증 서버 메타데이터를 가져온 후 해당 `agent_auth.skill` URL을 따라야 합니다. Tuist는 권한 없는 응답 본문에도 동일한 로컬 `auth_md` URL을 반환하므로, 언어 모델 기반 클라이언트가 네이티브 클라이언트 통합에 의존하지 않고도 흐름을 발견할 수 있습니다. 배포 로컬 문서는 엔드포인트 이름, 요청 본문, 클레임 폴링 및 어설션 교환에 대한 단일 진실 공급원입니다.

에이전트가 이메일 클레임을 시작하기 전에 사용자에게 Tuist 계정의 이메일 주소를 확인하도록 요청해야 합니다. 제공자 프로필, Git 구성, 환경 변수 또는 세션 메타데이터에서 해당 주소를 추론해서는 안 됩니다.

엔드포인트는 `mcp` 스코프 그룹을 사용합니다. 익명 사전 클레임 자격 증명은 기능을 발견하고 공개 통합 지침을 읽을 수 있지만, 로그인한 사용자로 취급되지는 않습니다. 브라우저 승인 또는 클레임 후 자격 증명은 사용자 범위로 지정되며 각 도구는 대시보드와 동일한 권한 검사를 적용합니다. 자세한 내용은 <.localized_link href="/guides/server/authentication#scope-groups">스코프 그룹 문서</.localized_link>를 참조하세요.

도구는 인증된 사용자가 이미 읽을 수 있는 프로젝트로 해결됩니다. Xcode 및 Gradle 빌드 도구는 빌드 UUID 또는 대시보드 URL을 허용합니다. UUID는 정확히 하나의 프로젝트를 식별해야 하며, 여러 프로젝트에 나타나는 경우 도구는 다른 프로젝트의 보고서를 선택하는 대신 '찾을 수 없음'을 반환합니다. 프로젝트 범위 대시보드 및 API 읽기는 계속 사용할 수 있습니다. 보고된 액터 식별자는 검증되지 않은 라벨이며, 자격 증명이나 추가 접근 권한이 아닙니다.

빌드 목록 및 상세 도구는 선택적 `tuist_version` 메타데이터를 노출합니다: Xcode 및 Cargo용 보고 Tuist CLI, Gradle용 Tuist Gradle 플러그인, Mix용 `tuist_ex` 라이브러리입니다. Xcode는 연결된 프로젝트 생성 이벤트에서 `tuist_generation_version`도 노출하며, 이는 업로드하는 CLI와 다를 수 있습니다. 누락된 관측값은 null이며, 서버나 다른 보고서에서 추론되지 않습니다. Bazel은 기존 `bazel_version`을 사용하며 Struo 실행 세부 정보는 `once_version`을 노출합니다. 이러한 필드는 보고된 버전을 설명하며, 검증된 신원이나 와이어 계약 버전이 아닙니다. REST 빌드 엔드포인트도 동일한 메타데이터를 노출합니다. 기존 통합 및 불안정 테스트 스킬은 버전 필드에 의존하지 않으며 워크플로 변경이 필요하지 않습니다.

Tuist 운영자가 고객의 계정을 조사할 때는 모든 호출을 기록하는 Tuist의 내부 운영 도구를 통해 수행하며, 이 엔드포인트에 직접 연결해도 사용자의 자체 멤버십을 넘어선 접근 권한은 부여되지 않습니다.

### Pulse

Pulse는 계정의 운영 지표, 로그, 트레이스 및 오류에 대한 읽기 전용 도구를 노출하며, 모두 `account_handle`로 주소 지정됩니다. 처음 세 가지는 Pulse 페이지와 해당 REST API를 미러링하며, 나머지 다섯 가지는 에이전트가 텔레메트리를 직접 탐색할 수 있게 하며 REST 대응 항목이 없습니다.

| 도구 | 목적 | `/api/accounts/:account_handle/pulse` 하의 REST 대응 항목 |
| --- | --- | --- |
| `query_pulse` | Pulse 페이지 테이블 | `GET /:signal` |
| `get_pulse_analytics` | Pulse 페이지 위젯 | `GET /:signal/analytics` |
| `get_pulse_error_issue` | 하나의 오류 이슈 및 해당 이벤트 | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | 즉시 또는 범위 PromQL | 없음 |
| `list_pulse_labels` | 라벨 이름 또는 하나의 라벨 값 | 없음 |
| `search_pulse_logs` | 필터링된 로그 항목 | 없음 |
| `search_pulse_traces` | 필터링된 스팬 | 없음 |
| `get_pulse_trace` | 하나의 트레이스에 포함된 모든 스팬 | 없음 |

Pulse는 계정이나 프로젝트가 공개되어 있더라도 서버 구성 조직의 현재 멤버로 제한됩니다. 사용자 인증 또는 사용자 연관 `mcp` 자격 증명과 계정 읽기 권한이 필요합니다. 프로젝트 토큰, 일반 계정 토큰, 익명 등록 및 조직 멤버십이 없는 운영자 접근 권한은 Pulse 접근을 부여하지 않습니다. 자격 증명은 다른 백엔드나 텔레메트리 테넌트를 선택할 수 없으며, 서버 구성 계정만 Pulse 텔레메트리를 가지므로 어떤 도구도 다른 계정의 데이터를 읽을 수 없습니다. 브라우저 에이전트는 해당 페이지의 계정 범위 내에서 Pulse 페이지에서만 이러한 도구를 받습니다.

REST는 사용자 자격 증명이 필요합니다. OAuth 및 `auth.md` 사용자 연관성은 `/mcp` 엔드포인트에서만 사용 가능하며, 관련 계정의 멤버십이나 가시성과 관계없이 현재 사용자가 없는 계정 자격 증명은 거부됩니다.

`query_pulse`은 `signal`(`metrics`, `logs`, `traces` 또는 `errors`), 선택적 `query` 및 `range`(`15m`, `1h`, `6h` 또는 `24h`, 기본값 `1h`)를 받습니다. 메트릭은 PromQL 표현식을 허용합니다. 로그, 트레이스 및 오류는 로그 본문, 스팬 이름 및 오류 이슈 제목과 일치하는 대소문자를 구분하지 않는 리터럴 텍스트를 허용하며, 기본값인 `*`은 모든 것을 선택합니다. 트레이스 행은 개별 스팬입니다. 오류 행은 이슈로, 서비스와 지문별로 그룹화된 이벤트이며 이벤트 수, 영향을 받은 계정, 윈도우 내 첫 번째 및 마지막 발생 시기, 그리고 최신 이벤트의 제목, 원인, 수준 및 플랫폼을 포함합니다. 테이블은 `search`, `page`(기본값 `1`), `page_size`(`1`–`100`, 기본값 `20`), `sort_by` 및 `sort_order`(`asc` 또는 `desc`)를 허용합니다. 정렬 열은 신호에 따라 다르며 도구 스키마에 나열됩니다. 필터에는 로그와 오류용 `service` 및 `level`이 포함됩니다. 필터 연산자는 해당하는 `_op` 인수(`eq`, `contains` 또는 `not_contains`)를 사용하며, 기본적으로 정확한 일치를 사용합니다.

정렬 열은 메트릭용 `name`/`value`, 로그용 `timestamp`/`service`/`level`/`message`/`trace_id`, 트레이스용 `timestamp`/`service`/`name`/`duration_ms`/`trace_id`, 오류용 `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level`입니다. 대시보드는 의도적으로 하위 집합만 노출하지만, API와 도구는 각 신호에 대한 전체 목록을 허용합니다.

테이블 응답에는 `rows`, `series`, `warnings` 및 `meta`가 포함됩니다. 페이지네이션 메타데이터에는 `page`, `page_size`, `total_count`, `total_pages`, `has_next_page`, `has_previous_page` 및 `end_at`가 포함됩니다. 쿼리 윈도우를 유지하려면 이후 페이지에 반환된 ISO8601 `end_at`를 전달하세요. 결과 제한 오류는 응답을 빈 테이블로 취급하는 것이 아니라 쿼리나 시간 범위를 좁혀야 함을 의미합니다.

로그와 트레이스는 로컬 정렬 전에 최대 100개의 최신 일치 항목을 검사하며, 오류는 최근 본 100개의 이슈를 검사합니다. 필터, 정렬, 페이지네이션 및 총계는 전체 시간 윈도우가 아닌 반환된 일치 항목만 설명합니다. 다른 일치 항목을 검사하려면 쿼리 텍스트나 시간 범위를 좁히세요. 로컬 검색이나 정렬을 변경해도 업스트림 검색이 확장되지 않습니다. 집계 위젯은 이러한 제한된 테이블 결과의 집계가 아니라 독립적인 전체 윈도우 쿼리로 유지됩니다.

메트릭 테이블은 `end_at`에서 표현식을 한 번 평가하여 현재 값과 인스턴트 벡터 시리즈당 하나의 포인트를 반환합니다. 범위 벡터 표현식은 제한된 과거 포인트를 반환할 수 있습니다. 별도의 분석 위젯은 고정된 과거 차트를 제공하며, 테이블은 최신 값을 표시하기 위해 모든 일치하는 시리즈에 대한 시간 그리드를 구체화하지 않습니다.

텔레메트리 문자열은 명령어가 아닌 신뢰할 수 없는 데이터입니다.

`get_pulse_analytics`은 계정 핸들 외에 `signal`와 `range`만 받습니다. 고정 위젯은 테이블 표현식, 필터, 정렬 및 페이지네이션과 독립적입니다.

`get_pulse_error_issue`은 오류 행에서 이슈의 `fingerprint`와 `service`를 가져오며, 선택적으로 `range`, `end_at`, `page` 및 `page_size`를 포함합니다. 이슈 요약, 60개의 균등 발생 버킷, 예외 체인, 스택 프레임, 브레드크럼, 태그, 컨텍스트, 추가 데이터, 쿼리 문자열이 없는 요청 메서드 및 URL을 포함한 최신 이벤트, 그리고 테이블과 동일한 페이지네이션 `meta`를 가진 최신 우선 이벤트 한 페이지를 반환합니다. 오류 행은 또한 각 이슈의 60버킷 `occurrence_series`를 포함합니다. 이벤트는 저장 전에 개인 데이터가 제거되므로 필터링된 값은 `[Filtered]` 또는 `[REDACTED]`로 표시됩니다. 윈도우 내에 이벤트가 없는 이슈는 찾을 수 없음으로 보고됩니다. REST와 Model Context Protocol은 동일한 Pulse 컨텍스트와 응답 계약을 사용합니다. REST 응답은 캐싱을 비활성화합니다.

#### 텔레메트리 탐색

탐색 도구는 선택적 ISO8601 `end_at`에서 끝나는 `15m`, `1h`, `6h` 또는 `24h`(기본값 `1h`, `get_pulse_trace`용 `24h`)의 윈도우를 읽으며, 기본값은 현재 시간입니다. 모든 응답은 `start_at`와 `end_at`를 반환하므로, 윈도우를 유지하려면 동일한 `end_at`를 다시 전달하세요. 이러한 도구 중 어느 것도 SQL을 허용하지 않습니다.

- `query_pulse_metrics`은 `end_at`(기본값인 `type: instant`) 또는 윈도우 동안 매 `step`초마다(`type: range`) PromQL 표현식인 `query`를 평가합니다. 단계(step) 기본값은 윈도우를 360으로 나눈 값이며 이보다 작을 수 없으므로, 시리즈는 최대 361개의 포인트를 가집니다. 결과는 최대 5,000개의 시리즈를 가집니다. 포인트는 `[unix_seconds, value]`이며, `NaN`와 무한대 값은 문자열입니다. 인스턴트 쿼리는 `range`와 `step`를 거부합니다.
- `list_pulse_labels`은 `signal`를 받습니다. `label` 없이 호출하면 라벨 이름을 목록으로 표시하고, `label`와 함께 호출하면 해당 라벨의 값을 목록으로 표시합니다. 메트릭의 경우 `__name__`는 메트릭 이름을 목록으로 표시하며, 다른 라벨의 값에는 `up`과 같은 시리즈 선택자인 `match`가 필요합니다. 로그와 트레이스 라벨 값은 `filters`를 허용하지만, 트레이스 라벨 이름은 트레이스 스키마에서 가져오므로 허용하지 않습니다. 로그와 트레이스 값은 윈도우 내 항목 수를 포함하며 빈도수가 높은 순서대로 정렬되므로 서비스별 오류와 같은 분류 자료로도 사용됩니다. `search`는 리터럴 텍스트를 포함하는 이름이나 값만 유지하며, `limit`는 `1`–`1000`(기본값 `100`)를 허용합니다. 로그 라벨 이름 검색은 각 종류의 고유 속성 집합을 최대 1,000개까지 검사하고 필터가 허용하는 키만 목록으로 표시합니다.
- `search_pulse_logs`은 본문에 `text`가 포함되고 모든 필터와 일치하는 최대 `limit`개의 항목(`1`–`100`, 기본값 `50`)을 `newest` 또는 `oldest` 우선 순위로 반환합니다. 각 항목은 `severity_text`, `body`, `trace_id`, `span_id`, `scope_name` 및 병합된 리소스와 로그 `attributes`를 포함합니다. `span_id`와 `scope_name`는 OTLP 로그 송신자만 설정하는 Kubernetes에서 수집된 로그의 경우 `null`입니다.
- `search_pulse_traces`은 모든 필터, 선택적 `min_duration_ms` 및 `max_duration_ms`, 그리고 `root_only`와 일치하는 최대 `limit`개의 스팬을 `newest`, `oldest` 또는 `slowest` 우선 순위로 반환합니다.
- `get_pulse_trace`은 윈도우 내에서 시작되는 `trace_id`의 스팬을 가장 오래된 순서로 최대 1,000개까지 반환합니다. 윈도우 이전에 시작된 트레이스는 일부만 반환되므로, 이를 위해 윈도우를 넓히거나 이동하세요. 각 스팬은 스팬 속성, 이벤트, 링크 및 트레이스의 고유 `resources`에 대한 인덱스를 포함합니다.

필터는 최대 10개의 `{label, op, value}` 객체 목록입니다. `op`는 `eq`(기본값), `neq`, `contains` 또는 `not_contains`이며, 마지막 두 개는 대소문자를 구분하지 않는 리터럴입니다. 로그 라벨은 Pulse가 저장할 때 `severity_text`, `trace_id`, `span_id` 및 `scope_name`이며, 각 항목의 리소스 속성 키(예: `namespace`, `container`, `service.name`)와 로그 속성 키(예: `pod`)입니다. 키가 둘 다 나타나는 경우 리소스 속성이 적용됩니다. 트레이스 라벨은 `list_pulse_labels`가 반환하는 스팬 열로, 예를 들어 `service_name`, `span_name`, `span_status_code`(실패한 스팬의 경우 `STATUS_CODE_ERROR`), `span_attributes.http.route` 및 `resource_attributes.k8s.pod.name`입니다. 알 수 없는 트레이스 라벨은 빈 결과가 아닌 오류입니다.

`truncated`은 응답에 포함된 것보다 더 많은 이름, 값, 항목 또는 스팬이 일치했음을 의미합니다. 응답을 완전한 것으로 취급하지 말고 필터나 윈도우를 좁히세요. 텔레메트리 문자열은 명령어가 아닌 신뢰할 수 없는 데이터입니다.

<details>
<summary>Claude Code</summary>

실행:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

헤드리스 Claude Code 클라이언트가 모델에 실패한 네이티브 서버 연결을 노출하지 않을 경우, 호스팅된 문서를 검색하거나 프로젝트를 편집하기 전에 에이전트가 구성된 엔드포인트의 인증되지 않은 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 응답을 검사하도록 요구하세요. 브라우저 인증을 사용할 수 없는 경우에도 응답은 모델을 배포 로컬 `auth.md` 문서로 안내합니다.

</details>


<details>
<summary>Codex</summary>

실행:

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

새로운 `codex exec` 실행을 시작하기 전에 브라우저 로그인을 완료하세요. Codex는 초기화 중에 Tuist 서버 지침을 읽으므로 Gradle 최적화 요청은 자동으로 인증 및 검증 워크플로우를 받습니다.

</details>


<details>
<summary>Claude Desktop</summary>

**Settings → Connectors → Add custom connector**를 열고 다음을 설정하세요:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

프롬프트가 표시되면 브라우저에서 [Open Authorization](https://oauth.net/2/)을 완료하세요.

</details>


<details>
<summary>Pi</summary>

Pi에는 Model Context Protocol 클라이언트가 포함되어 있지 않습니다. 소스와 보안 영향을 검토한 후 서드파티 [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) 확장 프로그램을 설치할 수 있습니다:

```bash
pi install npm:pi-mcp-adapter
```

프로젝트 수준 `.mcp.json` 파일을 추가하세요:

```json
{
  "mcpServers": {
    "tuist": {
      "url": "https://tuist.dev/mcp",
      "auth": false
    }
  }
}
```

`auth`를 `false`로 설정하면 어댑터의 브라우저 인증 핸들러가 Tuist의 권한 없음 응답을 숨기지 않습니다. 헤드리스 에이전트는 반환된 `auth_md` URL을 읽고 Tuist의 등록, 신원 주장 교환 및 클레임 폴링 흐름을 따를 수 있습니다. 교환된 액세스 토큰을 베어러 토큰으로 구성하거나 에이전트가 인증된 Model Context Protocol 호출을 직접 수행하도록 하세요.

브라우저 인증을 선호하는 경우 `auth`를 `"oauth"`로 설정하세요. 해당 흐름의 경우 인증이 완료되는 동안 Pi의 [remote procedure call mode](https://pi.dev/docs/latest/rpc)로 하나의 프로세스를 활성 상태로 유지하세요:

```bash
pi --mode rpc
```

콜백 상태를 소유한 프로세스가 종료되었으므로 대기 중인 브라우저 인증을 별도의 `pi --print` 호출로 분할하지 마세요.

</details>


<details>
<summary>OpenCode</summary>

Tuist Model Context Protocol 서버를 `opencode.json`에 추가하세요:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "tuist": {
      "type": "remote",
      "url": "https://tuist.dev/mcp"
    }
  }
}
```

그런 다음 서버를 인증하세요:

```bash
opencode mcp auth tuist
```

</details>


<details>
<summary>Cursor</summary>

**Cursor Settings → Tools & Integrations → Model Context Protocol Tools**를 열고 다음을 추가하세요:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

**Command Palette → MCP: Add Server**를 사용한 다음 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 서버를 다음과 같이 구성하세요:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Agent panel → Settings → Add Custom Server**를 열고 다음을 설정하세요:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

에이전트가 `auth.md`를 지원하는 경우 브라우저를 열지 않고 익명으로 시작할 수 있습니다. 신뢰할 수 있는 제공자 신원이 이미 연결되어 있는 경우에도 브라우저를 사용하지 않고 완료할 수 있습니다. 서비스 인증 이메일, 익명 클레임 또는 첫 번째 제공자 링크의 경우 에이전트는 Tuist 검증 링크와 6자리 코드를 표시합니다. 링크를 열고 로그인한 후 Tuist 페이지에서 에이전트의 코드를 입력하세요. 코드를 에이전트에 다시 보내지 마세요. Tuist의 인증 서버 메타데이터는 배포 자체의 `/auth.md`를 직접 가리키며, 여기에는 정확한 요청 및 폴링 형식이 포함되어 있습니다.

## Amp orbs 및 Claude Code 클라우드 세션의 에이전트

Tuist 계정에 연결된 샌드박스에서 실행되는 코딩 에이전트는 브라우저나 저장된 Tuist 자격 증명 없이 자체 신원 토큰으로 엔드포인트를 인증할 수 있습니다:

- 계정이 **Settings → Integrations → Amp**에서 연결한 Amp 워크스페이스 또는 프로젝트의 **Amp orbs**는 orb의 ID 토큰을 전송합니다. Amp에서 서버의 `Authorization` 헤더를 `Bearer ${amp:id-token}`로 설정하세요. Amp는 서버 URL의 출처에 대해 토큰을 발행하므로 URL은 이 Tuist 인스턴스의 자체 주소여야 하며 만료 전에 토큰을 새로 고칩니다. 다른 출처에 대해 발행된 토큰은 거부됩니다.
- 연결된 Claude Code 환경의 **Claude Code cloud sessions**은 Tuist가 `TUIST_OIDC_TOKEN`로 전달하는 세션 토큰을 전송합니다. 헤더를 `Bearer ${TUIST_OIDC_TOKEN}`로 설정하세요.

Tuist의 Linux 샌드박스는 서버를 자동으로 추가하지 않습니다. 대신 동일한 신원으로 로그인하는 Tuist CLI와 에이전트에게 프로젝트 기록과 결과를 비교할 시점을 알려주는 스킬을 제공합니다. 에이전트에도 MCP 도구를 제공하려면 위의 헤더와 함께 서버를 Amp 또는 Claude Code 설정, 혹은 프로젝트의 `.mcp.json`에 추가하세요.

이러한 토큰은 연결된 계정의 모든 프로젝트에 대한 읽기 전용 액세스 권한을 제공합니다. `mcp` 그룹의 읽기 범위를 포함하지만 데이터 생성, 변경 또는 삭제(테스트 음소거 또는 건너뛰기 등)와 관련된 범위는 포함하지 않습니다. 워크스페이스 또는 환경을 연결 해제하면 다음 요청부터 액세스가 중단되며, 액세스 권한은 토큰 자체보다 오래 지속되지 않습니다. 여러 Tuist 계정에 연결된 Amp 워크스페이스는 토큰이 특정 계정을 지칭하지 않기 때문에 거부됩니다. 연결이 누락된 경우 권한 없음 응답의 `error_description`에 해당 내용이 표시됩니다.

이 읽기 전용 액세스는 Model Context Protocol 엔드포인트에만 적용됩니다. 동일한 샌드박스의 명령줄 도구 및 빌드 시스템 통합은 여전히 토큰을 연결의 CI 액세스 권한과 교환합니다.

## WebMCP

[WebMCP](https://webmachinelearning.github.io/webmcp)를 지원하는 브라우저에서는 Tuist 페이지가 `document.modelContext`로 도구를 등록하므로 브라우저에 내장된 에이전트가 추가 구성 없이 이를 호출할 수 있습니다. 호출은 Tuist 서버에서 실행됩니다.

- **Website and documentation pages**는 문서화 및 소스 도구(`search_tuist`, `search_tuist_code`, `list_tuist_files` 및 `read_tuist_file`)를 등록합니다. 로그인이 필요하지 않습니다.
- 로그인한 상태에서는 **An account's dashboard pages**가 해당 계정의 Tuist 읽기 전용 도구를 등록합니다. 각 페이지는 표시하는 내용과 프로젝트의 빌드 시스템에 맞는 도구만 등록합니다. Gradle 프로젝트의 빌드 페이지는 Gradle 빌드 도구를, 테스트 페이지는 테스트 및 커버리지 도구를, 러너 페이지는 러너 도구를, 샌드박스 페이지는 샌드박스 도구를 받습니다. 모든 페이지는 문서화 도구인 `list_projects` 및 `get_project`도 받습니다. 도구는 로그인한 사용자로 실행되므로 대시보드에서 읽을 수 있는 데이터와 보고 있는 계정의 데이터에만 접근할 수 있습니다. 다른 페이지나 계정으로 이동하면 도구가 해당 페이지의 도구로 대체됩니다.

데이터를 생성, 변경 또는 삭제하는 도구는 WebMCP를 통해 사용할 수 없습니다. 브라우저 에이전트가 사용자가 추가하지 않은 도구를 수신하고 빌드 및 테스트가 생성한 콘텐츠를 읽기 때문입니다. 이러한 도구를 사용하려면 MCP 클라이언트를 `/mcp` 엔드포인트에 연결하세요.

조직이 단일 사인온(SSO)을 강제하는 경우, 해당 도구를 사용하려면 제공자를 통해 대시보드에 로그인하세요.

## 빌드 시스템 통합은 두 가지 자격 증명을 사용합니다

Model Context Protocol 도구에 사용되는 자격 증명은 Gradle 플러그인이나 Bazel의 원격 서비스를 인증하지 않습니다. 에이전트가 Gradle 또는 Bazel 통합을 편집하거나 검증하기 전에 다음을 실행해야 합니다:

```bash
tuist auth whoami --url https://tuist.dev
```

해당 명령어가 인증되지 않은 경우 에이전트는 중지하고 사용자에게 다음을 실행하도록 요청해야 합니다:

```bash
tuist auth login --url https://tuist.dev
```

로컬 또는 자체 호스팅 배포의 경우 두 명령어와 `tuist.toml`의 URL을 교체하세요. 모든 곳에서 호스트명 표기를 동일하게 유지하세요. 예를 들어 `localhost`와 `127.0.0.1`는 별도의 저장된 자격 증명을 사용합니다.


## 기능

### 도구

다음 도구는 Tuist Model Context Protocol 서버를 통해 사용할 수 있습니다:

모든 도구는 명시적인 입력 및 출력 스키마와 함께 사람이 읽을 수 있는 설명을 게시합니다. 성공적인 호출은 광고된 출력 스키마를 준수하는 구조화된 콘텐츠를 반환하며, 아직 구조화된 콘텐츠를 소비하지 않는 클라이언트를 위해 텍스트로 직렬화된 동일한 결과도 함께 반환합니다.

`build_run_id`, `test_run_id`, `test_case_id`, `bundle_id`, `run_id`, `generation_id` 또는 `cache_run_id`과 같이 단일 레코드의 식별자를 받는 도구는 해당 레코드의 Tuist 대시보드 URL도 허용합니다. 식별자를 추출하지 말고 브라우저에서 URL을 직접 붙여넣으세요.

`get_xcode_build`, `get_test_run`, `get_gradle_build` 및 `get_project`에는 `side_quests`가 포함될 수 있습니다. 이는 프로젝트가 사용하지 않지만 레코드에서 도움이 될 것으로 표시된 Tuist 기능입니다. 각각은 `id`, 근거를 명시하는 `tip`, 그리고 `docs` 링크를 가집니다. 에이전트는 사용자의 요청을 먼저 완료하고, 해당 사이드 퀘스트를 언급하며, 사용자가 동의할 때만 하나를 실행하도록 요청받습니다. 이러한 정보는 사용자 세션, MCP 토큰 또는 에이전트 신원으로 연결하든 상관없이 프로젝트 계정의 멤버에게만 반환됩니다:

| ID | 도구 | 제안 시기 |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | Xcode 26 이상으로 처리된 클린 빌드가 캐시 가능한 컴파일 작업을 실행하지 않았습니다. |
| `gradle_build_cache` | `get_gradle_build` | 빌드가 Gradle의 빌드 캐시가 키를 계산하지 않은 채로 캐시 가능한 작업을 실행했습니다. 즉, 빌드 캐시가 꺼져 있었습니다. |
| `flaky_test_quarantine` | `get_test_run` | 실행에 불안정한 테스트가 있었고, 프로젝트에서 이를 음소거하거나 건너뛰는 자동화가 활성화되어 있지 않았습니다. Struo 프로젝트에는 권장되지 않습니다. |
| `test_sharding` | `get_test_run` | Tuist가 샤딩할 수 있는 빌드 시스템에서 샤딩되지 않은 CI 실행이 10분 이상 소요되었습니다. 팁은 선택적 테스팅이 이미 건너뛴 테스트 수와 시기를 알려줍니다. |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | CI 실행이 GitHub Actions, Bitrise, GitLab CI 또는 Buildkite 머신을 사용했으며, 계정이 Tuist Runners에서 작업을 실행한 적이 없습니다. tuist.dev에서만 제공됩니다. |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | GitHub Actions 실행이 GitHub 리포지토리에 연결되지 않은 프로젝트에 속해 있습니다. |
| `other_build_systems` | `get_project` | 계정이 모든 지원되는 빌드 시스템에서 Tuist를 사용하지 않습니다. 팁은 다른 시스템을 식별하는 파일을 나열하므로 에이전트가 리포지토리를 확인할 수 있습니다. |

#### 문서 및 커뮤니티 검색

이 읽기 전용 도구는 문서 웹사이트를 구동하는 동일한 검색 엔진을 통해 Tuist의 문서, [애플리케이션 프로그래밍 인터페이스](https://en.wikipedia.org/wiki/API) 참조, GitHub 릴리스, 커뮤니티 포럼 및 GitHub 이슈를 검색합니다. 릴리스 결과에는 제품, 버전, 발행 날짜 및 프리릴리스 상태가 포함됩니다. 기본적으로 안정 릴리스가 검색되며, `include_prereleases`를 사용하여 프리릴리스를 포함할 수 있습니다. 이 도구는 `https://tuist.dev/mcp`의 Tuist 호스팅 서버에서만 사용할 수 있습니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `search_tuist` | 공개 Tuist 문서, 애플리케이션 프로그래밍 인터페이스 참조, GitHub 릴리스, 커뮤니티 토론 및 GitHub 이슈를 검색합니다. 선택적으로 하나의 `source` (`docs`, `api_reference`, `releases`, `forum`, `issues`)로 제한할 수 있습니다. | `query` |

#### 피드백

에이전트는 Tuist 도구나 프롬프트가 예상대로 작동하지 않았을 때(예: 혼란스러운 결과, 오류, 누락된 데이터 또는 누락된 기능) Tuist 팀에 알릴 수 있습니다. 에이전트는 보고서를 제안하고 사용자가 동의할 때만 보내도록 요청받습니다. 각 보고서는 Tuist 지원팀과의 대화를 시작하며, 지원팀은 이메일로 답변할 수 있습니다. 보고서에는 에이전트의 기대 사항, 발생한 일, 선택적 제안, 사용자의 Tuist 사용자 ID, 핸들 및 이메일, 소속 조직이 포함됩니다. 에이전트는 문제가 발생한 계정과 프로젝트를 지정할 수도 있으므로 팀은 어떤 조직에 후속 조치를 취해야 할지 알 수 있습니다. 사용자가 소속된 계정만 허용됩니다. Tuist 사용자로 로그인한 에이전트만 보고서를 보낼 수 있으며, 각 사용자는 시간당 최대 10개의 보고서를 열 수 있습니다. 이 도구는 `https://tuist.dev/mcp`의 Tuist 호스팅 서버에서만 사용할 수 있습니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `report_feedback` | Tuist 도구 또는 프롬프트의 문제를 보고합니다. 선택적으로 `tool_name`, 문제가 발생한 `account_handle` 및 `project_handle`를 지정하고 `suggestion`를 추가할 수 있습니다. | `category`, `expected`, `actual` |

#### 소스 기반 답변

이러한 읽기 전용 도구를 사용하면 에이전트가 호스팅 서버와 함께 배포된 정확한 공개 Tuist 소스 리비전을 현재 동작에 의존하는 답변의 신뢰할 수 있는 출처로 사용할 수 있습니다. `https://tuist.dev/mcp`에서만 사용할 수 있습니다.

호환되는 클라이언트는 인라인 OAuth 인증 정보와 함께 초기화 중에 도구의 소스 리비전, 링크 및 결과 제한에 대한 사실적인 설명을 받습니다. 이러한 설명은 답변 스타일이나 검증 워크플로를 규정하지 않습니다. 사용자는 `ask_tuist` 프롬프트를 먼저 호출하지 않고 직접 질문할 수 있습니다. 명시적인 소스 기반 워크플로를 위해 프롬프트는 계속 사용할 수 있습니다.

모든 작업에는 동시성, 지속 시간, 탐색, 읽은 바이트 및 응답 크기에 대한 고정 제한이 있습니다. 검색 및 목록 결과에는 `truncated` 및 `truncation_reason` 필드가 포함됩니다. 결과가截断(truncated)되면 결과를 완전하다고 취급하지 말고 경로, 파일 패턴 또는 검색어를 좁히세요.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `search_tuist_code` | 소스 파일을 검색하여 현재 동작, 기본값, 구성, 기능 게이트, 오류 처리 또는 문서화되지 않은 세부 사항에 대한 질문에 답합니다. 결과에는 주변 줄, 리비전 고정 소스 링크 및 스캔 통계가 포함됩니다. | `pattern` |
| `list_tuist_files` | 관련 경로를 알 수 없을 때 소스 하위 시스템 또는 nearby 테스트를 발견합니다. 목록에는 깊이와 결과 수가 제한되어 있습니다. | 없음 |
| `read_tuist_file` | 관련 경로를 찾은 후 구현 파일, 호출 사이트 또는 테스트의 특정 줄 범위를 검사합니다.截断된 응답은 계속하기 위해 `next_start_line`를 제공합니다. | `path` |

#### 프로젝트

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_accounts` | 인증된 사용자가 사용할 수 있는 개인 및 조직 계정 핸들을 나열하며, 각 계정이 프로젝트를 생성할 수 있는지 여부도 포함합니다. | 없음 |
| `get_organization` | 조직의 구성원 디렉터리를 가져옵니다. 대기 중인 초대장은 대시보드와 동일한 관리자 권한이 필요하며, 초대 수락 토큰은 절대 반환되지 않습니다. | `account_handle` |
| `create_organization` | 인증된 사용자를 위한 Tuist 조직을 생성합니다. | `handle` |
| `create_project` | 인증된 사용자가 접근할 수 있는 계정 아래에 Tuist 프로젝트를 생성합니다. | `account_handle`, `project_handle` |
| `add_organization_member` | 기존 Tuist 사용자를 조직에 추가하거나 기존 구성원의 역할을 업데이트합니다. `user`(기본값), `admin` 또는 `viewer`를 허용하며, 뷰어는 대시보드와 실행 기록을 읽을 수 있지만 변경할 수는 없습니다. | `organization_handle`, `email` |
| `invite_organization_member` | 기존 Tuist 사용자의 이메일 주소인지 여부와 상관없이 조직으로 이메일 주소를 초대합니다. Tuist는 14일 후에 만료되는 수락 링크를 이메일로 보냅니다. 서버가 이메일을 보낼 수 없는 경우 `email_sent`가 `false`이며, 링크는 대시보드에서 복사해야 합니다. `user`(기본값), `admin` 또는 `viewer`를 허용합니다. 조직 관리자 권한이 필요합니다. | `organization_handle`, `email` |
| `cancel_organization_invitation` | 대기 중인 조직 초대를 취소하여 해당 링크를 더 이상 수락할 수 없도록 합니다. 조직 관리자 권한이 필요합니다. | `organization_handle`, `email` |
| `list_projects` | 인증된 사용자가 접근할 수 있는 모든 프로젝트를 나열합니다. | 없음 |
| `get_project` | 프로젝트 구성과 연결된 저장소 URL을 가져옵니다. | `account_handle`, `project_handle` |
| `connect_project_repository` | 계정의 GitHub 앱 설치가 접근할 수 있는 GitHub 저장소에 프로젝트를 연결합니다. 프로젝트는 저장소의 기본 브랜치를 채택합니다. 프로젝트 관리자 권한이 필요합니다. | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 프로젝트의 GitHub 저장소 연결을 제거합니다. 프로젝트 관리자 권한이 필요합니다. | `account_handle`, `project_handle` |

#### 계정 토큰

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_account_tokens` | 토큰 값을 노출하지 않고 계정 토큰 메타데이터를 나열합니다. | `account_handle` |
| `get_account_token` | 값을 노출하지 않고 계정 토큰 메타데이터를 가져옵니다. | `account_handle`, `token_id` |
| `list_project_tokens` | 토큰 값을 노출하지 않고 프로젝트 토큰 메타데이터를 나열합니다. | `account_handle`, `project_handle` |

#### 알림 규칙

이 도구들은 인증된 사용자의 자체 알림 규칙을 관리합니다. 새로운 미리보기와 같은 이벤트가 규칙의 프로젝트(목록이 없는 경우 알림을 받을 수 있는 모든 프로젝트)에서 발생하고 조건을 충족하면 푸시 알림과 같은 작업이 Tuist 앱 기기로 실행됩니다. 규칙이 없으면 알림을 받지 못합니다. 사용자 인증이 필요하며, 본인의 규칙에만 작동하고 사용자가 소속된 계정의 프로젝트만 허용합니다. 규칙은 모든 계정에 걸쳐 적용되므로 대시보드 페이지에는 제공되지 않습니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_notification_events` | 규칙이 구독할 수 있는 이벤트 유형을 나열하며, 각 유형에는 조건에 대한 JSON 스키마가 포함되어 있습니다. | 없음 |
| `list_notification_condition_options` | 프로젝트의 이벤트에 대한 조건 값을 제안합니다. 예를 들어 최근 미리보기의 트랙과 브랜치 등입니다. | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 사용자의 규칙을 나열합니다. | 없음 |
| `create_notification_rule` | 이벤트, 선택적 프로젝트 및 조건, 그리고 최소 하나의 작업으로부터 규칙을 생성합니다. | `event`, `actions` |
| `update_notification_rule` | 규칙의 활성화 상태, 프로젝트, 조건 또는 작업을 변경합니다. | `rule_id` |
| `delete_notification_rule` | 규칙을 삭제합니다. | `rule_id` |

#### 지속적 통합 러너

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_runner_jobs` | 계정의 지속적 통합 러너 작업을 나열합니다. | `account_handle` |
| `get_runner_job` | 지속적 통합 러너 작업을 가져옵니다. 머신이 메모리 부족 상태를 겪었는지, 무엇이 중단되었는지, 무엇을 변경해야 하는지 포함합니다. | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 지속적 통합 러너 작업에 대해 기록된 단계를 나열합니다. | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 지속적 통합 러너 작업에 대해 기록된 머신 지표를 나열합니다. | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 지속적 통합 러너 작업에 대해 캡처된 로그를 최대 500줄까지 나열합니다. | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 계정의 지속적 통합 워크플로 요약 정보를 나열합니다. | `account_handle` |
| `list_runner_profiles` | 계정의 지속적 통합 러너 프로필을 각 프로필의 `runs-on` 레이블과 함께 나열합니다. | `account_handle` |
| `get_runner_catalog` | 러너 프로필이 사용할 수 있는 머신 형태와 Xcode 버전을 나열합니다. | `account_handle` |
| `create_runner_profile` | 플랫폼, 머신 형태 및 macOS의 경우 Xcode 버전으로 러너 프로필을 생성합니다. 선택적으로 캐시 볼륨을 저장할 브랜치를 설정할 수 있습니다. 계정 관리 권한 또는 `account:runners:write` 범위가 필요합니다. | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 러너 프로필의 머신 형태, Xcode 버전 또는 사용자 지정 캐시 볼륨 변경 사항을 저장할 브랜치를 변경합니다. 생략된 필드는 기존 값을 유지합니다. 계정 관리 권한 또는 `account:runners:write` 범위가 필요합니다. | `account_handle`, `profile_name` |
| `delete_runner_profile` | 사용자 확인 후 러너 프로필을 삭제합니다. 기본 프로필은 삭제할 수 없습니다. 계정 관리 권한 또는 `account:runners:write` 범위가 필요합니다. | `account_handle`, `profile_name` |

러너 볼륨 도구는 볼륨 대시보드와 동일한 데이터를 노출합니다. 읽기 도구에는 러너 접근 권한이 필요하며, 지우기 작업에는 계정 관리 권한 또는 `account:runners:write` 범위와 사용자 확인이 필요합니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_runner_volumes` | 이름과 저장소로 필터링하고, 볼륨을 정렬 및 페이지네이션합니다. | `account_handle` |
| `get_runner_volume` | 저장소, 플랫폼, 용량, 사용 공간 및 마지막 사용 정보. | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 페이지네이션된 작업 및 워크플로 참조, 캐시 상태, 히트 결과 및 마운트 시간. | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 작업에서 마운트된 볼륨. | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 스토리지 시계열, 작업 실행, 히트율 및 추세. 선택적 `volume_id`, `start` 및 `end`(ISO 8601); 기본값은 7일, 최대 90일. | `account_handle` |
| `delete_runner_volume` | 볼륨과 저장된 내용을 삭제합니다. 실행 중인 작업은 개인 복사본을 유지하지만 저장할 수 없으며, 동일한 키를 가진 이후의 작업은 빈 상태로 시작합니다. | `account_handle`, `volume_id` |

목록은 `page` 및 `page_size`(최대 100)를 허용합니다. 볼륨 인벤토리는 또한 `name` 및 `repository`(정확히 일치, AND 조건으로 결합), `sort_by`(`volume`, `repository`, `used_space`, `capacity`, `last_used`) 및 `sort_order`(`asc`, `desc`)를 허용합니다. 알 수 없는 측정값과 히트 결과는 `null`로 유지됩니다. 캐시 상태는 볼륨 변경 사항이 저장되었는지 여부를 나타내며, 작업 성공 여부를 나타내지는 않습니다.

#### 샌드박스

샌드박스 도구는 [API](https://tuist.dev/api/docs)와 동일한 접근 권한으로 샌드박스 대시보드와 동일한 데이터 및 작업을 노출합니다. 계정 구성원은 계정의 모든 샌드박스에서 모든 도구를 사용할 수 있습니다. 읽기 전용 뷰어는 사용할 수 없습니다. 계정에는 샌드박스가 활성화되어 있어야 합니다. 대시보드의 샌드박스 페이지는 읽기 전용 도구를 등록합니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_sandboxes` | 상태, 형태 및 타임스탬프와 함께 샌드박스를 페이지네이션합니다. 선택적 `search`(샌드박스 내 텍스트, Amp Orb 또는 Anthropic 세션 ID), `status`, `vcpus`, `sort_by`(`created`, `last_active`, `identifier`) 및 `sort_order`. | `account_handle` |
| `get_sandbox` | 샌드박스의 상태, 형태, 노드, 아카이브 및 타임스탬프. | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU 시간, 생성된 샌드박스, 세션, 설정 및 시작 소요 시간, 그리고 계정 한도에 대한 피크 vCPU, 메모리 및 디스크 사용량(추세 포함). 선택적 `start` 및 `end`(ISO 8601); 기본값은 30일, 최대 90일. | `account_handle` |
| `create_sandbox` | 빈 샌드박스를 부팅하고 실행되면 반환합니다. 선택적 `platform`(`linux` 또는 `darwin`), `xcode_version`(macOS 샌드박스의 정확한 Xcode 버전, 도구 설명에 나열된 것 중 하나; `darwin`를 의미함), `repository`(macOS 샌드박스의 github.com `owner/name`, 계정의 프로젝트 중 하나에 연결됨: Linux Claude Code 환경에 macOS 설정 스크립트가 있는 경우 Mac은 <.localized_link href="/guides/features/sandboxes/claude#remote-mac-snapshots">준비된 스냅샷</.localized_link>에서 부팅됨), `template`, `vcpus` 및 `memory_mb`(Linux: 2x4096, 4x8192 또는 8x16384, 기본값 2x4096; macOS: 8x8192, 8x16384 또는 8x24576, 기본값 8x8192) `workspace_gb` 및 `lifetime_seconds`(실행 명령이 취소되고 일시 중지 및 아카이브되기 전까지 실행될 수 있는 시간, 파일은 유지됨: 기본값 2시간, 최대 1일). 설명은 에이전트가 저장소가 빌드하는 Xcode(`.xcode-version`, mise, CI 구성 또는 문서)를 찾아 전달하도록 안내합니다. 다른 Xcode는 저장소의 캐시와 스냅샷을 놓치기 때문입니다. 또한 Mac이 `/opt/tuist/agent-guide.md`에携带하는 가이드를 읽도록 합니다. Mac의 Tuist는 저장소가 특정 버전을 고정하면 해당 고정 버전을 사용하며, 그렇지 않으면 <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">계정의 캐시를 자체적으로 사용</.localized_link>합니다. | `account_handle` |
| `pause_sandbox` | 실행 중인 샌드박스를 노드의 디스크에 스냅샷으로 저장합니다. | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 일시 중지되거나 아카이브된 샌드박스를 재개합니다. | `account_handle`, `sandbox_id` |
| `extend_sandbox` | 지금부터 샌드박스의 수명을 다시 시작합니다. 선택적 `lifetime_seconds`(최대 1일). 통합이 소유한 샌드박스에는 수명이 없습니다. | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 일시 중지된 샌드박스의 디스크를 객체 스토리지로 이동하도록 큐에 추가합니다. | `account_handle`, `sandbox_id` |
| `delete_sandbox` | 사용자 확인 후 샌드박스 및 디스크를 삭제합니다. | `account_handle`, `sandbox_id` |

샌드박스 도구의 오류는 `code: fleet_busy`과 같은 안정적인 코드로 시작하며, 그 뒤에 수행해야 할 작업이 표시됩니다. 대기 시간이 포함된 코드는 `retry_after_seconds:` 줄을 추가합니다. API는 오류 본문에 동일한 `code`를 전송합니다. 모든 호스트가 busy 상태일 때 `create_sandbox`는 `fleet_busy` 응답 전에 최대 25초 동안 대기합니다.

#### Amp 워크스페이스

이 도구들은 토큰 없이 orbs가 Tuist에 로그인할 수 있도록 하는 <.localized_link href="/guides/server/authentication#amp-orbs">Amp 워크스페이스 연결</.localized_link>을 관리합니다. 대시보드의 통합 페이지와 동일한 관리자 전용 권한을 사용합니다. orb 내의 에이전트는 `$AMP_WORKSPACE_ID` 및 `$AMP_PROJECT_ID`에서 자체 ID를 읽을 수 있습니다. 연결이 허용하는 모든 orb는 계정의 모든 프로젝트에 대한 CI 접근 권한을 얻으므로, 에이전트는 연결 전에 사용자와 확인해야 합니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | 계정에 연결된 Amp 워크스페이스와 각각 제한된 프로젝트(있는 경우)를 나열합니다. | `account_handle` |
| `connect_amp_workspace` | Amp 워크스페이스를 연결합니다. 선택적 `project_id`은 하나의 Amp 프로젝트 orbs에 대한 로그인을 제한합니다. | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | 워크스페이스 연결을 해제합니다. orbs가 이미 가진 세션은 만료될 때까지 유효하게 유지됩니다. | `account_handle`, `connection_id` |

#### Claude 환경

이 도구들은 Claude Managed Agents 자체 호스팅 환경을 연결하여, 설정 → 통합 → Claude와 마찬가지로 Tuist 샌드박스에서 세션이 실행되도록 합니다. 계정 관리 권한과 샌드박스 활성화가 필요합니다. 에이전트는 Anthropic의 API로 환경을 생성할 수 있지만, 환경 키는 Claude Console에서만 생성하므로 에이전트가 사용자에게 이를 요청합니다. Tuist는 Anthropic API 키 또는 워크로드 아이덴티티 페더레이션으로 세션을 시작하고, 해당 자격 증명으로 환경을 가져온 후 저장합니다. Anthropic 측 설정은 사용자의 Anthropic 자격 증명을 사용하며, Tuist는 이를 수신하지 않습니다. 키는 클라이언트와 모델을 통해 전달되므로 명시적으로만 제공해야 합니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_claude_environments` | 연결된 환경과 각 환경이 사용하는 자격 증명, 그리고 페더레이션 규칙이 신뢰해야 하는 발급자 URL 및 주제 접두사를 나열합니다. | `account_handle` |
| `connect_claude_environment` | `api_key`로 환경을 연결하거나, `organization_id`, `workspace_id`, `service_account_id` 및 `federation_rule_id`로 연결합니다. 선택적 `platform`, `vcpus` 및 `memory_mb`은 샌드박스 형상을 설정합니다. | `account_handle`, `environment_id`, `environment_key` |

#### 조직 AI

이 도구들은 설정 → AI와 마찬가지로 조직의 서버 측 AI 작업이 사용하는 모델을 관리하며, 동일한 규칙을 공유합니다: 조직 관리자 전용이며, AI 설정이 있는 조직에만 적용됩니다. `pulse_grouping` 또는 `pulse_explanation`와 같은 각 작업은 작업 경로가 있으면 이를 사용하고, 없으면 기본 모델을 사용합니다. 둘 다 없으면 요청을 보내지 않습니다. 모든 도구는 각 작업의 현재 모델과 그것이 경로, 기본값, 아니면 아무것도 아닌지 여부를 포함하여 전체 구성을 반환합니다. 제공자를 추가하거나 편집하려면 API 키가 필요하므로, 대시보드 또는 REST API(`/api/accounts/{handle}/ai`)에서 수행되며 이러한 도구를 통해 수행되지 않습니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `get_organization_ai_configuration` | 제공자(키 제외), 모델, 기본 모델, 작업 경로 및 각 작업의 현재 모델을 읽습니다. | `account_handle` |
| `save_organization_ai_model` | 모델(`name`, `provider_id`, `upstream_model_id`)을 추가하거나, `id`로 업데이트합니다. | `account_handle` |
| `remove_organization_ai_model` | 모델과 해당 작업 경로를 제거합니다. | `account_handle`, `model_id` |
| `set_organization_ai_default_model` | 기본 모델을 선택하거나 null로 지웁니다. | `account_handle`, `model_id` |
| `save_organization_ai_task_route` | `task`을 구성된 `model_id`로 라우팅하거나, `id`로 경로를 업데이트합니다. 작업은 최대 하나의 경로만 가질 수 있습니다. | `account_handle` |
| `remove_organization_ai_task_route` | 경로를 제거하여 작업이 다시 기본 모델을 사용하도록 합니다. | `account_handle`, `route_id` |
| `remove_organization_ai_provider` | 제공자와 해당 키, 모델 및 경로를 제거합니다; 연결된 Claude 조직을 연결 해제합니다. | `account_handle`, `provider_id` |

#### 웹훅

웹훅 도구는 대시보드와 동일한 관리자 전용 권한을 사용합니다. 전달 시도에는 엔드포인트에 대해 기록된 요청 및 응답 데이터가 포함되지만, 엔드포인트 서명 비밀은 포함되지 않습니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 계정의 웹훅 엔드포인트를 나열합니다. | `account_handle` |
| `get_webhook_endpoint` | 웹훅 엔드포인트를 가져옵니다. | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 엔드포인트의 전달 시도를 나열합니다. | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 전달 시도를 가져옵니다. | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 빌드

Xcode, Gradle, Bazel, Mix 및 Cargo용 빌드 상세 도구는 기존 `custom_metadata: {tags, values}` 형태를 노출하며, 보고된 경우 인프라 관찰 정보도 포함합니다. 값은 문자열로 유지되며 익숙하지 않은 키는 보존됩니다. 예를 들어, `tuist.cpu.available_processors`는 런타임에 사용 가능한 논리 프로세서를 설명하는 반면, `tuist.gradle.max_workers`는 Gradle 작업자 제한이고 `tuist.jvm.max_heap_bytes`는 JVM 힙 제한으로, 호스트 메모리가 아닙니다. 이들은 신뢰할 수 없는 클라이언트 관찰 정보이며, 검증된 러너 신원이 아닙니다. 관찰 정보가 없으면 그대로 누락됩니다; 가져온 로그와 이전 클라이언트에는 인프라 메타데이터가 없을 수 있습니다. Struo 메타데이터는 조정된 클라이언트/프로토콜 업데이트를 기다리고 있습니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_xcode_builds` | 프로젝트의 Xcode 빌드 실행을 나열합니다. | `account_handle`, `project_handle` |
| `get_xcode_build` | 특정 Xcode 빌드 실행에 대한 자세한 정보를 가져옵니다. 여기에는 원본 `.xcactivitylog`을 포함하는 아카이브의 임시 다운로드 URL이 포함됩니다. | `build_run_id` |
| `list_xcode_build_targets` | 특정 Xcode 빌드 실행의 빌드 타겟을 나열합니다. | `build_run_id` |
| `list_xcode_build_files` | 특정 Xcode 빌드 실행의 컴파일된 파일을 나열합니다. | `build_run_id` |
| `list_xcode_build_steps` | 로그 텍스트 없이 타이밍과 결과를 포함한 기록된 빌드 단계를 나열합니다. | `build_run_id` |
| `get_xcode_build_step` | 로그 및截断 플래그를 포함한 기록된 빌드 단계 하나를 가져옵니다. | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 특정 빌드 실행의 빌드 문제(경고 및 오류)를 나열합니다. | `build_run_id` |
| `list_xcode_build_cache_tasks` | 특정 Xcode 빌드 실행의 캐시 가능 작업(캐시 히트/미스)을 나열합니다. | `build_run_id` |
| `list_xcode_build_cas_outputs` | 특정 Xcode 빌드 실행의 [콘텐츠 주소 지정 스토리지](https://en.wikipedia.org/wiki/Content-addressable_storage) 출력을 나열합니다. | `build_run_id` |

`list_xcode_build_steps`는 기본적으로 20개 단계로 페이지를 반환하며(`page_size`를 통해 최대 100개), 탐색을 위해 `page`와 `pagination_metadata`를 제공합니다. `search`를 사용하여 제목, 프로젝트 또는 타겟을 일치시키거나, 정확한 `project`, `target`, `category`(예: `swiftCompilation`), 그리고 `status`(`success` 또는 `failure`)를 필터링합니다. 가장 느린 순으로 정렬하려면 `duration_ms`(기본값)를, 시간순으로 정렬하려면 `start_ms`를 사용하세요. 단계 ID는 동점 처리를 위해 사용되며 전체 64비트 정밀도를 유지하기 위해 십진수 문자열로 반환됩니다. ID는 빌드 범위로 한정되며 빌드 간에 일치시켜서는 안 됩니다.

선택적 `start_ms` 및 `end_ms`는 빌드 시작부터 밀리초 단위의 시간 범위와 겹치는 단계를 선택합니다(끝은 제외됨). 두 도구 모두 빌드 UUID 또는 대시보드 URL을 `build_run_id`로 허용합니다. 반환된 단계 `id`를 `step_id`로 변경 없이 전달하여 로그를 가져옵니다. 로그는 단계당 최대 64 KiB까지 보관되며, `log_truncated`는 생략된 출력을 나타냅니다.

단계는 Xcode 빌드가 처리될 때 기본적으로 수집됩니다. 기록된 단계 데이터는 90일 동안 보관됩니다. 목록 응답에는 `availability`이 포함됩니다: 필터가 아무것도 일치하지 않더라도 기록된 단계가 존재하면 `available`; 빌드가 여전히 처리 중이고 단계가 아직 없으면 `processing`; 단계가 기록되지 않았거나 만료되었으면 `unavailable`.

동일한 작업은 HTTP API에서 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 및 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}`로 사용할 수 있으며, 동일한 필터와 페이지네이션을 지원합니다. 둘 다 빌드 프로젝트에 대한 읽기 액세스 권한이 필요합니다.

#### Gradle 빌드

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 완전한 인증, 프로젝트 설정, Gradle 플러그인, 캐시 정책 및 이중 빌드 검증 워크플로를 반환합니다. 에이전트는 기존 Android 또는 Gradle 프로젝트를 편집하기 전에 이를 호출해야 합니다. | 없음 |
| `list_gradle_builds` | 프로젝트의 Gradle 빌드 실행을 custom metadata와 함께 나열합니다. 선택적 `tag` 매개변수를 사용하여 custom tag로 필터링합니다. | `account_handle`, `project_handle` |
| `get_gradle_build` | 빌드 메타데이터, 작업/캐시 카운트 및 `failures`을 가져옵니다: 각 실패한 작업 및 구성 단계의 실패 메시지. | `build_run_id` |
| `list_gradle_build_tasks` | 작업 결과, 복합 빌드 식별자, 캐시 가능성, 증분 상태 및 실패 메시지를 나열합니다. | `build_run_id` |
| `list_gradle_build_steps` | 검색, 메타데이터 및 중복 시간 필터를 사용하여 시간이 측정된 작업, 구성 및 변환을 나열합니다. | `build_run_id` |
| `get_gradle_build_step` | 불투명 ID로 기록된 단계 메타데이터를 검사합니다. 실패한 작업 또는 구성 단계의 `log`은 해당 실패 메시지입니다. | `build_run_id`, `step_id` |

Gradle 및 Bazel 단계 목록은 기본적으로 20개의 결과를 반환하며(최대 100개), `search`, 정확한 `project`, `target`, `category` 및 `status`, 중복되는 `start_ms` / `end_ms` 필터(끝 제외), 그리고 `duration_ms` 또는 `start_ms` 정렬을 지원합니다. 반환된 ID를 변경 없이 전달하세요. 이는 해당 빌드로 범위가 한정됩니다. 목록은 `time_origin` 및 `coverage`을 노출합니다. 이전 Gradle 보고서는 빌드 시작이 업로드되지 않았으므로 `first_recorded_timestamp`를 사용합니다. Bazel 프로파일은 `trace_profile` 커버리지와 시간 원점으로 `profile_start`를 사용하여 모든 기록된 간격을 노출합니다. 이전 빌드는 보존된 BEP 요약으로 대체됩니다. 소스 기록은 90일 후에 만료됩니다. Bazel 세부 정보에는 게시된 경우 정제된 작업 로그가 포함됩니다. 실패한 작업 또는 구성 단계의 Gradle 세부 정보에는 Tuist Gradle 플러그인이 `log`로 보고한 실패 메시지가 포함됩니다: Gradle 콘솔이 출력하는 예외 메시지 및 원인 체인으로, 스택 추적이나 작업 출력 없이, 프로젝트 내 경로는 상대 경로로 만들고 자격 증명 및 기타 로컬 경로는 삭제하며, 단계당 최대 16 KiB, 빌드당 최대 32개의 실패 단계입니다. 다른 Gradle 단계, 이전 플러그인 버전으로 보고된 빌드 및 자격 증명이 없는 보고서는 null `log`을 가집니다. 구성 단계는 실패했을 때 `failure`을 보고하고 그렇지 않으면 `unknown`을 보고합니다. `compare_builds` 프롬프트는 이 커버리지를 사용하여 전체 Bazel 추적과 보존된 요약을 구분하고, 더 광범위한 호출 출력을 확인하기 전에 에이전트를 작업 결과 및 로그를 위한 단계 세부 정보로 안내합니다.

단일 단계 도구 `get_gradle_build_step` 및 `get_bazel_build_step`는 ID로 단계를 검색하며 시간 필터를 허용하지 않습니다. 시간 범위로 단계를 필터링하려면 해당 목록 도구를 사용하세요.

보존된 요약에서 반환된 Bazel 단계 ID는 목록 조회와 단계 가져오기 사이에 전체 프로파일이 도착하면 여전히 읽을 수 있습니다. 단계 데이터가 만료된 인덱싱된 프로파일은 사용 불가로 보고됩니다. Gradle 단계 목록에는 지속 시간이 0인 캐시된 작업과 건너뛴 작업이 포함됩니다.

#### Bazel 호출

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 인증, 프로젝트 설정, Bazel 구성 및 검증 워크플로를 반환합니다. | 없음 |
| `list_bazel_invocations` | 완료된 [Bazel Build Event Protocol](https://bazel.build/remote/bep) 호출을 최신 순으로 나열하며, 빌드 지표, 제한된 실행 타임라인, 중요 경로 진단 및 프로젝트별 상관관계가 있는 원격 캐시 총계를 포함합니다. `status`, `git_branch`, `git_commit_sha`, `is_ci` 및 `command`로 필터링합니다. | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 빌드 지표, 제한된 실행 타임라인, 중요 경로 진단 및 상관관계가 있는 원격 캐시 총계가 포함된 완료된 Bazel 호출 하나를 가져옵니다. | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 필터와 명시적 커버리지가 포함된 기록된 Bazel 프로파일 간격을 나열합니다. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 기록된 Bazel 단계와 게시된 작업 결과 및 정제된 로그를 검사합니다. | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_remote_actions` | 호출에 대해 Tuist 원격 실행이 실행한 작업을 니모닉, 타겟, 작업 다이제스트, 종료 코드, 실행 경로 및 단계 타이밍과 함께 나열합니다. 선택적 `sort_by`(`duration` 또는 `queued_at`), `failed` 및 `mnemonic` 필터. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_remote_action` | 원격 작업의 argv, 환경(비밀처럼 보이는 값 마스킹), 플랫폼, 작업 디렉터리, 출력 경로, 작업자, 종료 코드, stdout 및 stderr의 첫 16 KiB, stderr에서 인식된 컴파일러 `errors`, 단계 타이밍 및 작업 다이제스트를 가져옵니다. | `account_handle`, `project_handle`, `invocation_id`, `action_id` |
| `get_bazel_remote_action_log` | 바이트 오프셋별로 원격 작업의 stdout 또는 stderr에서 최대 64 KiB를 읽으며, 기본적으로 스트림의 끝까지 읽습니다. 긴 스트림은 전체가 복사되거나, 더 긴 경우 처음 16 KiB와 마지막 16 MiB가 유지됩니다. `recorded`는 사용 가능한 범위를 나열합니다. | `account_handle`, `project_handle`, `invocation_id`, `action_id`, `stream` |
| `list_bazel_invocation_logs` | 실행 순서대로 Bazel 호출에 대해 캡처된 정제된 로그를 나열합니다: Bazel 진행률 출력의 제한된 꼬리 부분과 `test.log` 아티팩트. 선택적 `stream`(`stdout` 또는 `stderr`), `source`(`progress` 또는 `test_log`), `target_label` 및 `errors` 필터로 결과를 좁힐 수 있습니다. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bazel 호출에 대해 캡처된 정제된 로그 조각 하나를 가져옵니다. | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 작업, 엔드포인트 및 관찰 시간이 포함된 원시 Bazel 원격 캐시 관찰을 나열하며, 선택적으로 호출, 결과 또는 작업으로 좁힐 수 있습니다. | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 원시 Bazel 원격 캐시 관찰 하나를 가져옵니다. | `account_handle`, `project_handle`, `cache_event_id` |

#### 원격 실행

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `get_remote_execution_activity` | 프로젝트의 실행 중인 Bazel 호출과 현재 실행 중이거나 대기 중인 원격 작업을 나열하며, 각 작업의 호출, 니모닉, 타겟, 작업 다이제스트, 머신 크기 및 해당 상태에 진입한 시점을 포함합니다. 실행 게이트웨이가 미리 준비한 VM에서 실행하는 작업은 완료될 때까지 목록에 표시되지 않습니다. | `account_handle`, `project_handle` |
| `get_remote_execution_usage` | `[from, to)` 동안 프로젝트의 원격 실행과 측정된 실행 시간을 총계, 머신 크기별, 디스패치 모드별 및 시간, 일 또는 월별로 가져옵니다. 기간은 기본적으로 최근 30일이며 최대 366일까지 지원합니다. | `account_handle`, `project_handle` |

`list_bazel_invocations` 필터는 정확히 일치해야 하며, 같은 초에 완료된 호출은 호출 ID 순으로 정렬됩니다. 브랜치에서 최신 실패 호출을 찾으려면 `status: "failure"`, `git_branch` 및 `page_size: 1`를 사용하여 호출합니다. REST 엔드포인트 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations`도 동일한 필터를 허용합니다.

`list_bazel_build_steps`에서 `remote_execution: true`를 설정하여 인덱싱된 프로파일에서 안전하게 연관된 서버 단계 타이밍이 있는 작업만 반환하도록 합니다. 목록 및 상세 응답은 선택적 nullable 값인 `remote_queue_ms`, `remote_input_fetch_ms`, `remote_execution_ms` 및 `remote_output_upload_ms`를 노출합니다. 값은 작업 내 재시도를 포함해 기록된 단계의 합계이며, 없거나 null인 값은 0이 아닌 사용 불가 상태를 의미합니다. 이는 프로파일 관찰 결과이며, 캐시된 서버 결과가 실행 메타데이터를 포함할 수 있으므로 청구 가능한 사용량이나 새로운 실행의 증명이 아닙니다. 클라이언트 업로드는 제외됩니다. 오래되거나 모호한 프로파일은 원격 작업이 발생했더라도 일치하는 작업을 반환하지 않을 수 있습니다. 단계 REST 엔드포인트도 동일한 `remote_execution=true` 필터를 허용합니다. 대시보드의 원격 실행 탭도 동일한 쿼리와 90일 보존 정책을 사용합니다.

테스트 로그는 출처인 테스트 결과의 `target_label` 및 시도 `status`를 포함하므로, `target_label: "//foo:bar_test"`는 해당 타겟의 테스트 로그만 반환합니다. `errors: true`는 실패한 시도의 테스트 로그와 Bazel 리포터가 `ERROR:`, `FAIL:` 또는 `TIMEOUT:`로 시작하는 줄을 포함하는 stderr 진행률 조각을 반환합니다. 진행률 출력은 타겟에 귀속되지 않으며, 귀속 정보가 기록되기 전에 작성된 로그는 필드가 비어 있습니다. 실패한 작업과 그 출력은 `list_bazel_build_steps`에서 타겟별로 제공되며, 테스트 케이스별 실패는 테스트 실행 도구에서 제공됩니다.

#### Cargo 빌드

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_cargo_builds` | 프로젝트의 Cargo 빌드를 최신 순으로 나열합니다. `git_branch`, `status`, `is_ci` 또는 `command`로 필터링합니다. Cargo 테스트 실행 결과는 이 빌드 목록이 아닌 테스트 도구를 통해 제공됩니다. | `account_handle`, `project_handle` |
| `get_cargo_build` | 빌드 메타데이터, 집계된 캐시 카운터 및 진단 정보가 포함된 최대 500개의 기록된 컴파일러 작업을 가져옵니다. `compilations_truncated`는 생략된 작업을 나타내며, 진단 정보는 반환된 작업에만 적용됩니다. | `account_handle`, `project_handle`, `build_id` |

`get_cargo_build`에서 `include_cache_inspection: true`를 설정하여 검증된 작업 결정과 CAS 작업을 검색하며, 크기는 4 MB로 제한됩니다. 기본적으로 레코드가 없거나 유효하지 않은 경우 `cache_inspection`는 null입니다. 부분 캡처 `truncated` 플래그를 준수하세요. 전송은 각 작업 히트의 로컬/원격 출처를 입증하지 않습니다. HTTP 상세 엔드포인트도 동일한 쿼리 매개변수를 허용합니다.

#### Mix 빌드

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_mix_builds` | 프로젝트의 Mix(Elixir) 컴파일 빌드를 최신 순으로 나열하며, 사용자 정의 메타데이터를 포함합니다. `git_branch`, `status`, `is_ci` 또는 `mix_env`로 필터링합니다. | `account_handle`, `project_handle` |
| `get_mix_build` | 빌드 메타데이터, 진단 카운트 및 의존성 캐시 요약을 가져옵니다. | `account_handle`, `project_handle`, `build_id` |

#### 빌드 트레이스

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `get_build_trace` | Xcode, Gradle, Bazel 또는 Mix 빌드의 타임라인을 [Perfetto](https://ui.perfetto.dev)에서 열 수 있는 트레이스 파일로 다운로드할 링크를 가져옵니다. | `account_handle`, `project_handle`, `build_id` |

`build_id`는 빌드 실행 ID(Bazel의 경우 호출 ID) 또는 빌드의 대시보드 URL입니다. 반환된 `trace_url`는 [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON 파일을 제공합니다. 링크를 가진 사람은 `expires_at`까지 다른 자격 증명 없이 해당 빌드의 트레이스를 다운로드할 수 있으며, 이는 호출 후 1시간입니다. 에이전트는 `curl`로 다운로드하거나, Perfetto에서 열 수 있도록 전달하거나, Perfetto의 `trace_processor`로 쿼리할 수 있습니다. 트레이스에는 병렬 처리에 따라 레인으로 압축된 기록된 단계, 전체 빌드를 아우르는 트랙, 그리고 빌드가 머신 지표를 기록했을 때의 CPU 및 메모리 카운터가 포함됩니다. 로그를 제외하면 위의 단계 도구와 동일한 데이터를 보유합니다. 대시보드도 각 빌드의 타임라인 탭에서 동일한 파일을 제공합니다.

#### Struo 실행

<a id="once-runs"></a>

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_once_runs` | 프로젝트의 Struo 실행을 최신 순으로 나열합니다. `kind`(`build`, `test` 또는 `generic`), `status`, `is_ci` 또는 `git_branch`로 필터링합니다. 완료되지 않은 실행의 상태는 `in_progress`입니다. | `account_handle`, `project_handle` |
| `get_once_run` | 실행과 그 작업 총계, 캐시 요약, 그리고 테스트 실행의 경우 테스트 총계를 가져옵니다. | `account_handle`, `project_handle`, `run_id` |

Cargo 빌드, Mix 빌드 및 Struo 실행 ID는 프로젝트 내에서 고유합니다. HTTP API를 통해 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, `.../mix/builds` 및 `.../once/runs`에서 동일한 읽기가 가능하며, 각각 하나의 ID에 대한 상세 엔드포인트를 제공합니다.

#### 작업, 액션, 모듈 및 파일

이 프로젝트 범위 도구는 실행 간에 지속되는 빌드 식별자를 검사합니다. `list_build_entities`로 시작한 후, 반환된 안정적인 `id`와 동일한 `kind`를 `get_build_entity` 또는 `list_build_entity_history`에 전달하며, `account_handle` 및 `project_handle`도 함께 포함합니다. 빌드 또는 호출 식별자는 필요하지 않습니다.

| 도구 | 설명 | 필수 매개변수 |
| --- | --- | --- |
| `list_build_entities` | 프로젝트의 빌드 전반에서 관찰된 한 종류의 작업, 모듈, 액션 또는 파일을 나열합니다. | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 선택한 기간에 대한 네이티브 식별자 및 분석 정보가 포함된 빌드 엔티티 하나를 가져옵니다. | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 하나의 빌드 엔티티에 대해 기록된 실행, 컴파일 또는 캐시 이벤트를 최신 순으로 나열합니다. | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 툴체인 | 히스토리 목록 |
| --- | --- | --- |
| `bazel_actions` | Bazel 액션 | BEP 보고된 액션 실행 |
| `gradle_tasks` | Gradle 작업 | 작업 실행 |
| `xcode_modules` | Xcode 모듈 | 컴파일 및 모듈 캐시 이벤트 |
| `once_actions` | Struo 액션 | 실행 |
| `mix_files` | Mix 컴파일 파일 | 컴파일 |
| `mix_modules` | Mix 컴파일 모듈 | 컴파일 |
| `cargo_crates` | Cargo 크레이트 | 기록된 rustc 호출 |

이 도구들은 점진적으로 출시되며 활성화된 프로젝트에 대해서만 데이터를 반환합니다. 다른 프로젝트에서는 빈 결과 대신 오류를 반환합니다. 한 종류는 해당 빌드 툴체인을 사용하는 프로젝트에서만 사용할 수 있습니다. 이 도구들은 제한된 `start_at`/`end_at` 필터, `environment`(`any`, `ci` 또는 `local`) 및 정확한 `branch`을 허용합니다. `list_build_entities`은 `q`을 허용하며, `list_build_entity_history`은 불투명한 `after`/`before` 커서를 지원합니다. 알 수 없는 타이밍 또는 캐시 관측치는 0 또는 미스로 처리되지 않고 그대로 사용 불가 상태로 유지됩니다. 히스토리는 기존 실행 도구를 사용한 드릴다운을 위해 기록된 부모 및 네이티브 실행을 참조합니다.

`get_build_entity` 지표에는 기록된 타이밍이 있는 관측치 수인 `duration_samples`가 포함됩니다. 실제 0 지속 시간은 계산되지만, 누락된 타이밍은 계산되지 않습니다. 이 카운트는 관측치 수보다 낮을 수 있으며, 사용 불가한 지속 시간 통계는 null로 유지됩니다.

Xcode 모듈 지속 시간은 빌드 로그에서 측정된 타겟 컴파일에서 비롯됩니다. 모듈 캐시 해결 및 컴파일 작업이 없는 타겟은 지속 시간 샘플에 기여하지 않습니다. 컴파일 관측치는 Xcode 빌드를 참조하며, 캐시 이벤트는 생성 또는 캐시 명령을 참조합니다.

Bazel 액션은 타겟 라벨, 니모닉 및 구성된 기본 출력으로 식별되어 입력 종속 캐시 다이제스트에 의존하지 않고 별도의 액션과 구성을 명확하게 구분합니다. 히스토리는 캐시 조회 또는 트레이스 프로필 단계를 제외하고 BEP 보고된 실행을 기록합니다. 완전한 실행 커버리지를 위해서는 `--build_event_publish_all_actions`가 필요합니다. 아티팩트 전달은 최선을 다해 이루어지므로, 누락된 관측치가 작업이 실행되지 않았다는 증거는 아닙니다. 안정적인 식별자 또는 실행 시작 정보가 없는 이전 Kura 페이로드는 여전히 허용되지만 인덱싱되지 않습니다. 종료 시간 측정이 없으면 사용 불가 상태로 유지되며 실제 0 지속 시간은 계산됩니다.

Mix 모듈 지속 시간은 독립적으로 측정된 모듈 작업이 아닌 포함하는 파일의 컴파일을 측정합니다. Struo 액션은 클라이언트가 타겟 매핑을 보고했을 때 선언된 타겟/기능/인덱스 슬롯을 사용합니다. 진단 라벨만으로는 안정적인 식별자가 되지 않습니다. 기존 클라이언트 및 실행 수준 도구는 변경 없이 계속 지원됩니다.

Cargo 크레이트는 정확히 기록된 크레이트 루트, 이름 및 종류별로 그룹화됩니다. 체크아웃 경로 변경은 히스토리를 분할할 수 있으며, 빌드 프로필, 기능 및 타겟 트리플은 구별되지 않습니다. 히스토리는 파일별 작업이나 캐시 히트가 아닌 rustc 호출을 측정합니다. 누락된 작업은 제거 또는 전체 워크스페이스 인벤토리를 확립하지 않습니다.

분석 읽기는 제한된 메모리 및 실행 시간을 가집니다. 쿼리가 이러한 제한을 초과하면 도구는 빈 결과를 생성하는 대신 오류를 반환합니다.

새로운 관측치는 배포 후 인덱싱됩니다. 이 기능은 기존 실택 텔레메트리를 백필하지 않습니다. 식별자 메타데이터는 <.localized_link href="/guides/server/data-retention">데이터 보존 정책</.localized_link>에 따라 개별 관측치보다 오래 유지됩니다.

#### 테스트

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_test_runs` | 프로젝트의 테스트 실행을 각각의 `selective_testing_strategy`와 함께 나열합니다. `selective_testing`(커버리지 기반 선택의 폴백을 포함하는 `coverage` 또는 `module_hash`)로 필터링합니다. `query` 필드는 `git_branch`, `scheme`, `status` 및 `selective_testing`입니다. `field:"value"`은 정확히 일치하며, `field~"value"`은 대소문자를 구분하지 않는 하위 문자열과 일치합니다(`selective_testing`에는 적용되지 않음). 앞에 `-`이 붙으면 두 연산자 중 하나를 부정합니다. 예를 들어, `-git_branch~"gh-readonly-queue"`는 병합 큐 브랜치를 제외합니다. 공백으로 구분된 쿼리 필터와 명시적 인수는 AND 의미론으로 결합됩니다. | `account_handle`, `project_handle` |
| `get_test_run` | 테스트 실행에 대한 상세 지표를 가져옵니다. 여기에는 자체 코드 커버리지(`coverage`: 측정 여부, 라인 및 수치, 부분적이었는지 또는 더티 체크아웃에서 실행되었는지), 선택적 테스팅 요약(`selective_testing`: 전략, 베이스라인 커밋, 요청된/선택된/스킵된/예상 테스트 수 - 테스트 선택 효과성 계산에 사용됨), 결과 번들(`.xcresult`) 및 이를 실행한 명령의 세션 아카이브(CLI 로그)에 대한 임시 다운로드 URL, 또는 실행에 연결된 명령이 없을 경우 `null`가 포함됩니다. 샤딩된 실행의 `result_bundle_url`는 첫 번째 보고 샤드의 번들입니다. `shard_result_bundles`는 CI 재시도를 포함하여 모든 샤드 보고서에 대한 번들을 샤드 인덱스 및 상태와 함께 나열하므로, 실패한 테스트 없이 실패한 샤드를 검사할 수 있습니다. | `test_run_id` |
| `list_test_module_runs` | 특정 테스트 실행에 대한 테스트 모듈 실행을 나열합니다. | `test_run_id` |
| `list_test_suite_runs` | 특정 테스트 실행에 대한 테스트 스위트 실행을 나열하며, 선택적으로 모듈로 필터링할 수 있습니다. | `test_run_id` |
| `list_test_cases` | 프로젝트의 테스트 케이스를 나열합니다(`flaky`와 같은 필터를 지원합니다). | `account_handle`, `project_handle` |
| `get_test_case` | 신뢰성 비율, 불안정성 비율 및 실행 횟수를 포함한 테스트 케이스에 대한 상세 지표를 가져옵니다. | `test_case_id` 또는 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 테스트 케이스 실행을 나열하며, 선택적으로 테스트 케이스 또는 테스트 실행으로 필터링할 수 있습니다. | `account_handle`, `project_handle` |
| `get_test_case_run` | 특정 테스트 케이스 실행에 대한 실패 세부 정보 및 반복 횟수를 가져오고, 해당 실행의 커버리지 기반 선택이 테스트를 유지했을 경우 그 이유(`selective_testing`: 결정, 이유, 일치한 변경 파일 및 샤드)도 가져옵니다. | `test_case_run_id` |
| `list_test_case_run_attachments` | 테스트 케이스 실행에 대한 첨부 파일을 나열합니다. 각 첨부 파일에는 임시 다운로드 URL이 포함됩니다. | `test_case_run_id` |
| `list_test_case_events` | 음소거 또는 스킵과 같은 테스트 케이스의 상태 변경 사항을 나열합니다. | `test_case_id` |
| `update_test_case` | 테스트 케이스의 상태나 불안정성(flaky) 분류를 업데이트합니다. 변경 사항은 외부 서비스를 포함한 구성된 웹훅 엔드포인트로 이벤트를 전송할 수 있습니다. | `test_case_id` 또는 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 테스트 실행에 대한 선택적 테스팅(selective-testing) 대상 결과를 나열합니다. | `test_run_id` |
| `list_selective_testing_tests` | 테스트 실행의 커버리지 기반 선택이 결정, 선택 및 스킵한 테스트를 나열하며, 각 결정의 이유, 이를 선택한 변경 파일, 샤드 및 실행 결과를 포함합니다. `decision`, `reason` 또는 `search`로 필터링할 수 있습니다. | `test_run_id` |
| `list_selective_testing_changed_files` | 테스트 실행의 커버리지 기반 선택 베이스라인 이후 변경된 파일을 나열하며, 각 파일이 선택한 테스트 수와 변경 시 선택이 폴백(fallback)되는 추적 파일인지 여부를 표시합니다. | `test_run_id` |
| `get_coverage` | 커밋 또는 브랜치의 최신 완료 커밋에서 대상별 프로젝트의 코드 커버리지를 가져옵니다. `git_commit_sha` 또는 `branch`가 없으면 기본 브랜치를 읽습니다. | `account_handle`, `project_handle` |
| `list_coverage_files` | 커밋 또는 브랜치의 최신 완료 커밋에서 해당 커밋의 코드 커버리지가 측정한 파일과 라인 커버리지를 나열합니다. `search`, 정렬 및 페이지네이션을 지원합니다. | `account_handle`, `project_handle` |
| `get_coverage_file` | 커밋 또는 브랜치의 최신 완료 커밋에서 파일의 코드 커버리지와 함수를 가져옵니다. 각 라인의 실행 횟수를 얻으려면 `include_lines`를 설정하세요. | `account_handle`, `project_handle`, `path` |
| `list_coverage_branches` | 코드 커버리지가 있는 브랜치를 나열하며, 기본 브랜치를 먼저 표시합니다. | `account_handle`, `project_handle` |
| `list_coverage_commits` | 브랜치의 커밋을 커버리지 상태(`complete`, `incomplete`, `in_progress`, `not_measured`), 수치 및 이전 완료 커밋 대비 변화량과 함께 최신순으로 나열합니다. 커서 기반 페이지네이션을 사용합니다. | `account_handle`, `project_handle` |
| `list_coverage_runs` | 커밋 또는 브랜치 뒤의 코드 커버리지가 있는 테스트 실행을 나열하며, 각각 `full`, `partial` 또는 `discarded`(더티 체크아웃)로 표시됩니다. 커서 기반 페이지네이션을 사용합니다. | `account_handle`, `project_handle` |
| `list_coverage_targets` | 커밋의 대상별 커버리지를 나열한 후, 커버리지 카운터 없이 바이너리 캐시에서 가져온 대상(`measured: false`)을 나열합니다. `search`, 정렬 및 페이지네이션을 지원합니다. | `account_handle`, `project_handle` |

코드 커버리지 도구는 코드 커버리지가 활성화된 계정에서 사용할 수 있습니다.

#### 번들

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_bundles` | 프로젝트의 번들(앱 바이너리)을 나열합니다. 선택적으로 `git_branch` 및 `tags`로 필터링할 수 있습니다(모든 태그는 정확히 일치해야 함). | `account_handle`, `project_handle` |
| `get_bundle` | 사용자 정의 태그를 포함한 특정 번들에 대한 상세 정보를 가져옵니다. | `bundle_id` |
| `get_bundle_artifact_tree` | 번들의 전체 아티팩트 트리를 경로별로 정렬된 평면 목록으로 가져옵니다. | `bundle_id` |

`list_bundles`는 빌드 유형이나 환경을 구분하기 위해 `tags: ["paid", "production"]`를 허용합니다. 태그는 대소문자를 구분하는 레이블로, 문자, 숫자, 하이픈 또는 밑줄만 포함할 수 있으며 태그는 최대 10개, 태그당 최대 50자까지 가능합니다. 목록 및 상세 결과에는 `custom_metadata.tags`가 포함됩니다. 페이지네이션 카운트와 브랜치 필터는 태그된 결과에 적용되며, `tags`를 생략하면 필터링되지 않은 동작이 유지됩니다. 잘못된 태그 필터는 쿼리를 확장하는 대신 오류를 반환합니다.

#### 제네레이션

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_generations` | 프로젝트의 제네레이션 실행을 나열합니다. | `account_handle`, `project_handle` |
| `get_generation` | 특정 제네레이션 실행에 대한 상세 정보를 가져옵니다. | `generation_id` |

#### 캐시 실행

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_cache_runs` | 프로젝트의 캐시 실행을 나열합니다. | `account_handle`, `project_handle` |
| `get_cache_run` | 세션 아카이브(CLI 로그)에 대한 임시 다운로드 URL을 포함한 특정 캐시 실행에 대한 상세 정보를 가져옵니다. | `cache_run_id` |
| `list_xcode_module_cache_targets` | 제네레이션 또는 캐시 실행에 대한 모듈 캐시 대상을 나열하며, 대상별 캐시 히트/미스 상태와 추가 해싱 입력을 포함한 진단 구성 요소 해시를 표시합니다. | `run_id` |

#### 프리뷰

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_previews` | 프로젝트의 공유 가능한 앱 프리뷰를 나열합니다. | `account_handle`, `project_handle` |
| `get_preview` | 프리뷰와 해당 빌드에 대한 임시 다운로드 URL을 가져옵니다. | `preview_id` |
| `get_latest_preview` | 실행 중인 앱 바이너리의 최신 프리뷰를 찾습니다. | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 자동화

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_automation_alerts` | 프로젝트의 자동화 알림을 나열합니다. | `account_handle`, `project_handle` |
| `get_automation_alert` | 자동화 알림을 가져옵니다. | `alert_id` |
| `list_automation_alert_revisions` | 자동화 알림의 수정 이력을 나열합니다. 작업 자격 증명은 마스킹 처리됩니다. | `alert_id` |
| `list_project_notification_alerts` | 프로젝트 알림 규칙을 나열합니다. 대시보드 설정 페이지와 동일한 관리자 권한이 필요합니다. 웹훅 주소는 마스킹 처리됩니다. | `account_handle`, `project_handle` |

### 이벤트

상태 비저장 `2026-07-28` 모델 컨텍스트 프로토콜 라이프사이클을 사용하는 클라이언트는 `events/list`를 호출하여 이벤트와 해당 페이로드 스키마를 검색할 수 있습니다:

| 이벤트 | 전송 시점 | 구독 필터 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 테스트 케이스가 불안정하지 않은 상태에서 불안정한 상태로 변경됩니다. | `account_handle`, `project_handle` |
| `build.failed` | 로컬 또는 지속적 통합 Xcode, Gradle 또는 Bazel 빌드가 실패로 완료됩니다. | `account_handle`, `project_handle` |
| `test_run.failed` | 로컬 또는 지속적 통합 테스트 실행이 실패로 완료되며, 병합된 샤드 실행 또는 중단된 실행도 포함됩니다. | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist 러너 작업이 실패로 완료됩니다. | `account_handle` |
| `pulse_symptom.opened` | Pulse가 보드 또는 페이지 티어에서 증상을 열거나 다시 엽니다. 감사 티어에서만 기록된 증상과 열린 증상에 대한 이후 변경 사항은 전송되지 않습니다. | `account_handle` |

구독하려면 클라이언트는 이벤트 이름, 위에 나열된 핸들(`arguments`), 그리고 `https://` 콜백 URL과 `whsec_` 서명 비밀을 포함하는 `webhook` 전달을 사용하여 `events/subscribe`를 호출합니다. 프로젝트 이벤트에는 계정 멤버십과 해당 테스트 또는 빌드 데이터에 대한 읽기 접근 권한이 필요합니다. 러너 작업 이벤트에는 계정 멤버십과 러너 읽기 접근 권한이 필요합니다. Pulse 증상 이벤트에는 조직 멤버십과 계정에 대한 Pulse 접근 권한이 필요하며, 계정 토큰은 해당 계정에 속해야 합니다. 인증된 [`auth.md`](https://workos.com/auth-md) 접근 토큰, 인증된 계정 토큰 및 브라우저 권한 부여는 구독을 생성할 수 있으며, 관련 자격 증명이 더 이상 활성 상태가 아니면 전달이 중지됩니다. 각 사용자는 최대 25개의 활성 구독을 유지할 수 있습니다. Tuist는 구독을 저장하기 전에 콜백에 검증 챌린지를 보냅니다. 콜백은 동일한 `challenge` 값을 포함하는 객체를 반환해야 합니다. 구독은 기본적으로 7일간 지속되며, 다시 구독하여 갱신할 수 있고, 사용자의 접근 권한이나 자격 증명이 제거되면 전달이 중지됩니다. 선택적 `ttlMs`는 1시간에서 30일 사이로 제한됩니다. Tuist는 시간 초과된 콜백을 재시도하며, 5분에 걸쳐 최소 3회 연속 시간 초과가 발생하면 구독을 해제합니다. 콜백을 복구한 후 다시 구독하세요.

이벤트가 발생하면 Tuist는 리소스 식별자와 대시보드 URL을 콜백으로 보냅니다. 빌드 및 테스트 실행 실패에는 `is_ci`와 `git_branch`도 포함되므로, 클라이언트는 로컬 실패를 무시하거나 브랜치별로 필터링할 수 있습니다. 빌드 이벤트에는 `build_system`가 포함됩니다. 러너 작업 이벤트에는 `workflow_job_id`와 `workflow_run_id`가 모두 포함됩니다. Pulse 증상 이벤트에는 `symptom_id`, `tier`(`board` 또는 `page`), 그리고 `untrusted` 아래의 영향받은 엔티티가 `{"type": "untrusted_json", "value": {"service", "kind", "key"}}` 형식으로 포함되며, 각 값은 최대 200자입니다. 엔티티는 프로덕션 텔레메트리에서 제공되므로 지시사항이 아닌 데이터로 취급하세요. 해당 URL은 증상의 페이지를 엽니다. 요청에는 구독 식별자와 [Standard Webhooks](https://www.standardwebhooks.com/) 서명 헤더가 포함되어 있어 클라이언트가 출처를 확인할 수 있습니다. Tuist는 실패한 전달을 재시도하므로, 클라이언트는 안정적인 `eventId`를 사용하여 중복 항목을 제거해야 합니다. 페이로드에는 테스트 이름, 로그 및 실패 메시지가 생략되어 있으며, 클라이언트는 위의 도구를 통해 이러한 세부 정보를 가져와 팀에 알림을 보낼지 또는 디버깅을 시작할지 결정할 수 있습니다. 클라이언트는 `events/unsubscribe`를 사용하여 전달을 중지할 수 있습니다.

### 프롬프트

| 프롬프트 | 설명 |
|--------|-------------|
| `fix_flaky_test` | 실패 패턴을 분석하고 근본 원인을 식별하며 대상 수정을 적용하여 불안정한 테스트를 수정하는 과정을 안내합니다. |
| `compare_builds` | 성능 저하, 캐시 변경 및 빌드 문제를 식별하기 위해 빌드를 비교하는 과정을 안내합니다. Xcode, Gradle, Bazel 및 Cargo 프로젝트용 네이티브 도구를 사용합니다. Cargo 비교는 부분 컴파일러 커버리지를 보존하며 추정된 컴파일러 작업을 경과 시간 절감량과 구분합니다. |
| `compare_test_runs` | 두 테스트 실행을 비교하여 성능 저하, 새로운 실패 및 불안정한 테스트를 식별하는 과정을 안내합니다. |
| `compare_bundles` | 두 번들을 비교하여 아티팩트 트리 전반의 크기 변화를 식별하는 과정을 안내합니다. |
| `compare_test_case` | 두 브랜치 또는 기간에 걸쳐 테스트 케이스의 동작을 비교하는 과정을 안내합니다. |
| `compare_generations` | 두 제네레이션 실행을 비교하여 성능 저하와 모듈 캐시 변경을 식별하는 과정을 안내합니다. |
| `compare_cache_runs` | 두 캐시 실행을 비교하여 캐시 효율성 변화와 대상 수준에서의 성능 저하를 식별하는 과정을 안내합니다. |
| `integrate_gradle_project` | 기존 Gradle 프로젝트에 Tuist를 통합하는 과정을 안내합니다. 별도의 도구 및 Gradle 인증, 계정 탐색, 프로젝트 생성, 원격 캐시 정책, 빌드 인사이트 및 읽기 백 검증을 포함합니다. |
| `integrate_bazel_project` | Bazel 프로젝트를 생성하거나 선택하고, 명령줄을 인증하며, 원격 캐시와 빌드 인사이트를 구성한 다음, Tuist 빌드 데이터를 통해 통합을 검증하는 과정을 안내합니다. |
| `integrate_xcode_project` | 기존 Xcode 프로젝트에 Tuist를 통합하는 과정을 안내합니다. Xcode 캐시, 빌드 인사이트, 테스트 인사이트 및 테스트 샤딩을 지원합니다. |
| `ask_tuist` | 공개 자료를 컨텍스트로 사용하고, 집중된 구현 및 테스트 증거를 현재 동작의 신뢰할 수 있는 출처로 활용하여 Tuist 질문에 답변합니다. `question`가 필요하며 개정 버전 고정 증거를 인용합니다. |

프로젝트 데이터 프롬프트는 조사를 특정 프로젝트로 한정하기 위해 `account_handle`와 `project_handle`를 허용합니다. 비교 프롬프트는 또한 비교할 두 항목(ID, 대시보드 URL 또는 브랜치 이름으로 지정)을 지정하기 위해 `base`와 `head` 인수를 허용합니다. `ask_tuist`는 프로젝트 매개변수 대신 `question`를 허용합니다. `integrate_gradle_project`는 또한 적용할 Gradle 통합 목록인 쉼표로 구분된 `features`를 허용합니다: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests` 및 `test_sharding`. `integrate_bazel_project`는 자체 호스팅 또는 로컬 설치를 위한 선택적 `server_url`를 허용합니다. `integrate_xcode_project`는 `xcode_cache`, `build_insights`, `test_insights` 및 `test_sharding`를 포함한 `features`를 허용합니다.

#### Gradle 통합 프롬프트 기능

`integrate_gradle_project` 프롬프트와 `get_gradle_integration_guide` 도구는 전체 설정 워크플로를 문서화합니다. 이 도구는 서버의 초기화 지침에서도 참조되므로, 프롬프트를 열거하지 않는 에이전트도 발견할 수 있습니다.

| 기능 | 에이전트가 구성하는 내용 |
|---------|---------------------------|
| `remote_cache` | Gradle의 빌드 캐시를 활성화하고, Tuist 원격 캐시 업로드 정책을 구성하며, 로컬 읽기 전용 사용과 함께 지속적 통합 러너에서만 업로드하도록 권장합니다. |
| `build_insights` | Tuist Gradle 플러그인을 적용하고 필요 시 빌드 분석 업로드 동작을 구성합니다. |
| `test_insights` | Gradle `Test` 작업 결과가 자동으로 업로드되도록 Tuist Gradle 플러그인을 적용합니다. |
| `flaky_tests` | 불안정한 테스트 감지 설정, 선택적 Gradle Test Retry 플러그인 사용 및 테스트 격리 구성을 안내합니다. |
| `test_sharding` | `tuistPrepareTestShards`, 샤드 매트릭스 생성 및 `TUIST_SHARD_INDEX` 기반 테스트 실행을 위한 지속적 통합 워크플로를 추가합니다. |

`features`가 생략되면, 프롬프트는 에이전트에게 사용자가 원하는 통합을 명확히 하거나 요청에서 가장 작은 유용한 집합을 추론한 후 Gradle 프로젝트를 편집하도록 요청합니다.

#### Xcode 통합 프롬프트 기능

`integrate_xcode_project` 프롬프트는 Tuist가 지원하는 모든 Xcode 통합을 문서화합니다:

| 기능 | 에이전트가 구성하는 내용 |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`, 생성된 프로젝트 캐시 설정, 수동 Xcode 캐시 빌드 설정 및 지속적 통합 러너로 제한된 업로드 정책을 구성합니다. |
| `build_insights` | `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath` 및 `tuist setup insights`를 통한 선택적 머신 지표를 구성합니다. |
| `test_insights` | `tuist inspect test`, 스킴 테스트 사후 액션 및 지속적 통합 테스트 실행을 위한 결과 번들 생성을 구성합니다. |
| `test_sharding` | `TUIST_SHARD_INDEX`와 함께 Xcode 또는 생성된 프로젝트 샤드 계획 및 샤드 실행 워크플로를 추가합니다. |

`features`가 생략되면, 프롬프트는 에이전트에게 사용자가 원하는 통합을 명확히 하거나 요청에서 가장 작은 유용한 집합을 추론한 후 Xcode 프로젝트를 편집하도록 요청합니다.
