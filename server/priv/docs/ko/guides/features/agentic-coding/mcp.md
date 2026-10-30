---
{
  "title": "모델 컨텍스트 프로토콜(MCP)",
  "titleTemplate": ":title · 에이전트 코딩 · 기능 · 가이드 · Tuist",
  "description": "Tuist의 MCP 엔드포인트를 통해 AI 에이전트가 테스트 인사이트 등에 접근할 수 있도록 합니다."
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro)는 인공지능 에이전트가 외부 서비스 및 데이터 소스와 상호작용할 수 있도록 하는 오픈 표준입니다. 이를 통해 [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/)와 같은 애플리케이션과 [Zed](https://zed.dev), [Cursor](https://www.cursor.com), [Visual Studio Code](https://code.visualstudio.com)와 같은 편집기가 Tuist와 연동될 수 있습니다.

Tuist는 `https://tuist.dev/mcp`에 서버 측 Model Context Protocol 엔드포인트를 호스팅합니다. 클라이언트를 이 엔드포인트에 연결하면 에이전트가 테스트 인사이트, 불안정한(flaky) 테스트 분석 등 Tuist 프로젝트 데이터에 접근할 수 있습니다. 대부분의 도구는 읽기 전용이며 인증된 Tuist 프로젝트 데이터로 범위가 제한됩니다. 계정 설정 도구는 인증된 사용자가 필요한 권한을 가진 경우 계정을 나열하고, 조직을 생성하며, 프로젝트를 만들고, 기존 사용자를 조직에 추가할 수 있습니다. 모든 도구는 읽기 전용인지, 복구가 어려운 변경을 유발할 수 있는지, 공개 인터넷 상태를 변경할 수 있는지를 명시하는 어노테이션을 광고합니다. 계정 설정 도구는 사용자 인증이 필요합니다. 프로젝트 토큰이나 일반 계정 토큰으로는 사용할 수 없습니다. 사용자가 브라우저에서 클라이언트를 승인하거나 `auth.md` 등록을 요청하면, Tuist는 해당 자격 증명을 Model Context Protocol 엔드포인트에서만 사용자와 연결하므로 설정 도구가 요청된 워크플로를 완료할 수 있습니다.

Tuist는 [2026-07-28 프로토콜](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)을 구현합니다. 요청은 상태가 없습니다(stateless). 클라이언트는 각 요청과 함께 프로토콜 메타데이터를 전송하며 초기화 없이 직접 도구를 호출할 수 있습니다. `server/discover`는 서버의 식별자, 기능, 지원되는 버전 및 지침을 반환합니다. 세션 식별자나 독립적인 이벤트 스트림은 없습니다. 2025-06-18 또는 2025-03-26 초기화 흐름을 사용하는 클라이언트도 계속 지원되며, 이들 역시 서버 세션 없이 작동합니다.

## Model Context Protocol 대 Skills

Model Context Protocol 도구와 <.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link>는 수행하는 작업이 중복될 수 있습니다. 현재 두 방식 간 중복이 있으므로, 워크플로당 한 가지 접근 방식을 선택하여 일관되게 사용하고 동일한 흐름에서 둘을 혼합하지 마세요.

플러그인 설치를 지원하는 클라이언트의 경우, <.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link>를 사용하여 둘을 함께 설치하세요.

## 구성

클라이언트에 `https://tuist.dev/mcp`를 원격 Model Context Protocol 서버로 추가하세요. 서버의 초기화 지침과 공개 서버 카드는 동적 클라이언트 등록 및 표준 브라우저 승인 흐름을 갖춘 OAuth 2.0을 인라인으로 설명하며, 에이전트가 외부 인증 문서를 가져오거나 따르도록 요구하지 않습니다. 이러한 서버 전체 지침은 워크플로 안내를 일반적으로 유지합니다. 도구 인증은 로컬 명령줄 도구나 빌드 시스템 통합을 인증하지 않으며, 에이전트는 관련 Tuist 도구를 통해 요청된 변경 사항을 검증해야 합니다. 빌드 시스템별 설정 및 인증 검사는 통합 가이드와 프롬프트에 문서화되어 있습니다. Tuist는 여전히 [Open Authorization](https://oauth.net/2/) 검색 메타데이터와 현재의 [auth.md 프로토콜](https://workos.com/auth-md)을 `https://tuist.dev/auth.md`에서 별도로 광고합니다.

엔드포인트는 이전의 세션 기반 라이프사이클과 함께 상태 없는 `2026-07-28` Model Context Protocol 요청 라이프사이클(예: `server/discover`)을 허용합니다. 기존 클라이언트는 현재 연결 방법을 계속 사용할 수 있습니다.

Model Context Protocol 이벤트를 지원하는 클라이언트는 프로젝트 이벤트를 구독할 수 있습니다. 사용 가능한 이벤트 및 전달 요구 사항은 [Events](#events)를 참조하세요.

원격 브라우저 인증을 이미 지원하는 클라이언트는 브라우저에서 인증을 계속할 수 있습니다. `auth.md`를 지원하는 클라이언트와 에이전트는 익명으로 등록하거나, 신뢰할 수 있는 제공자 신원 어설션을 제시하거나, 서비스 인증 이메일 클레임을 시작할 수 있습니다. 등록 시 Tuist가 서명한 신원 어설션이 반환되며, 에이전트는 이를 표준 토큰 엔드포인트에서 교환하여 1시간 유효한 액세스 토큰을 받습니다. Tuist는 공개 서명 키를 게시하며 표준 토큰 취소와 제공자 보안 이벤트 전달을 지원합니다.

인증되지 않은 에이전트는 Model Context Protocol 엔드포인트에서 반환된 `WWW-Authenticate` 헤더를 읽고, 보호된 리소스 메타데이터를 가져오고, 인증 서버 메타데이터를 가져온 후 해당 `agent_auth.skill` URL을 따라야 합니다. Tuist는 또한 무단 응답 본문에 동일한 로컬 `auth_md` URL을 반환하므로, 언어 모델 기반 클라이언트가 네이티브 클라이언트 통합에 의존하지 않고도 흐름을 발견할 수 있습니다. 배포 로컬 문서는 엔드포인트 이름, 요청 본문, 클레임 폴링 및 어설션 교환에 대한 단일 진실 공급원(source of truth)입니다.

에이전트가 이메일 클레임을 시작하기 전에 사용자에게 Tuist 계정의 이메일 주소를 확인하도록 요청해야 합니다. 제공자 프로필, Git 구성, 환경 변수 또는 세션 메타데이터에서 해당 주소를 추론해서는 안 됩니다.

엔드포인트는 `mcp` 스코프 그룹을 사용합니다. 익명의 사전 클레임 자격 증명은 기능을 발견하고 공개 통합 지침을 읽을 수 있지만, 로그인한 사용자로 취급되지는 않습니다. 브라우저 승인 또는 클레임 후에는 자격 증명이 사용자 범위로 제한되며, 각 도구는 대시보드와 동일한 권한 검사를 적용합니다. 자세한 내용은 <.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>을 참조하세요.

도구는 인증된 사용자가 이미 읽을 수 있는 프로젝트로 해결됩니다. Xcode 및 Gradle 빌드 도구는 빌드 UUID 또는 대시보드 URL을 허용합니다. UUID는 정확히 하나의 프로젝트를 식별해야 합니다. 여러 프로젝트에 나타나는 경우, 도구는 다른 프로젝트의 보고서를 선택하는 대신 '찾을 수 없음'을 반환합니다. 프로젝트 범위의 대시보드 및 API 읽기는 계속 가능합니다. 보고된 액터 식별자는 검증되지 않은 라벨일 뿐이며, 자격 증명이나 추가 접근 권한을 의미하지 않습니다.

빌드 목록 및 세부 정보 도구는 선택적 `tuist_version` 메타데이터를 노출합니다: Xcode 및 Cargo용 보고 Tuist CLI, Gradle용 Tuist Gradle 플러그인, 그리고 Mix용 `tuist_ex` 라이브러리입니다. Xcode는 연결된 프로젝트 생성 이벤트에서 `tuist_generation_version`도 노출하며, 이는 업로드하는 CLI와 다를 수 있습니다. 누락된 관찰 값은 null이며, 서버나 다른 보고서에서 추론되지 않습니다. Bazel은 기존 `bazel_version`을 사용하며, Once 실행 세부 정보는 `once_version`를 노출합니다. 이러한 필드는 보고된 버전을 설명할 뿐이며, 검증된 신원이나 와이어 계약 버전을 의미하지 않습니다. REST 빌드 엔드포인트도 동일한 메타데이터를 노출합니다. 기존 통합 및 flaky-test 스킬은 버전 필드에 의존하지 않으며 워크플로 변경이 필요하지 않습니다.

Tuist 운영자는 고객의 계정을 조사할 때 모든 호출을 기록하는 Tuist의 내부 운영 도구를 통해 수행합니다. 이 엔드포인트에 직접 연결해도 사용자의 멤버십 외에는 추가 접근 권한이 부여되지 않습니다.

<details>
<summary>Claude Code</summary>

실행:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

헤드리스 Claude Code 클라이언트가 모델에 네이티브 서버 연결 실패를 노출하지 않는 경우, 에이전트가 호스팅된 문서를 검색하거나 프로젝트를 편집하기 전에 구성된 엔드포인트의 인증되지 않은 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 응답을 검사하도록 요구하세요. 브라우저 인증이 불가능한 경우에도 응답은 모델을 배포 로컬 `auth.md` 문서로 안내합니다.

</details>


<details>
<summary>Codex</summary>

실행:

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

새로운 `codex exec` 실행을 시작하기 전에 브라우저 로그인을 완료하세요. Codex는 초기화 중에 Tuist 서버 지침을 읽으므로 Gradle 최적화 요청은 자동으로 인증 및 검증 워크플로를 받게 됩니다.

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

Pi에는 Model Context Protocol 클라이언트가 포함되어 있지 않습니다. 소스 및 보안 영향을 검토한 후 서드파티 [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) 확장을 설치할 수 있습니다:

```bash
pi install npm:pi-mcp-adapter
```

프로젝트 수준의 `.mcp.json` 파일을 추가하세요:

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

`auth`을 `false`로 설정하면 어댑터의 브라우저 인증 핸들러가 Tuist의 무단 응답을 숨기는 것을 방지합니다. 헤드리스 에이전트는 반환된 `auth_md` URL을 읽고 Tuist의 등록, 신원 어설션 교환 및 클레임 폴링 흐름을 따를 수 있습니다. 교환된 액세스 토큰을 베어러 토큰으로 구성하거나 에이전트가 인증된 Model Context Protocol 호출을 직접 수행하도록 하세요.

브라우저 인증을 선호하는 경우 `auth`을 `"oauth"`로 설정하세요. 해당 흐름의 경우 인증이 완료되는 동안 Pi의 [remote procedure call mode](https://pi.dev/docs/latest/rpc)로 하나의 프로세스를 활성화 상태로 유지하세요:

```bash
pi --mode rpc
```

콜백 상태를 소유하는 프로세스가 종료되었으므로 대기 중인 브라우저 인증을 별도의 `pi --print` 호출로 분할하지 마세요.

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

**Command Palette → MCP: Add Server**를 사용한 후 다음과 같이 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 서버를 구성하세요:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Agent panel → Settings → Add Custom Server**를 열고 다음을 설정하세요:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

에이전트가 `auth.md`을 지원하는 경우 브라우저를 열지 않고 익명으로 시작할 수 있습니다. 신뢰할 수 있는 제공자 신원이 이미 연결되어 있는 경우에도 브라우저 없이 완료할 수 있습니다. 서비스 인증 이메일, 익명 클레임 또는 첫 번째 제공자 링크의 경우 에이전트는 Tuist 확인 링크와 6자리 코드를 표시합니다. 링크를 열고 로그인한 후 Tuist 페이지에서 에이전트의 코드를 입력하세요. 코드를 에이전트에 다시 보내지 마세요. Tuist의 인증 서버 메타데이터는 배포 자체의 `/auth.md`를 직접 가리키며, 여기에는 정확한 요청 및 폴링 형식이 포함되어 있습니다.

## 빌드 시스템 통합은 두 가지 자격 증명을 사용합니다

Model Context Protocol 도구에 사용되는 자격 증명은 Gradle 플러그인이나 Bazel의 원격 서비스를 인증하지 않습니다. 에이전트가 Gradle 또는 Bazel 통합을 편집하거나 검증하기 전에 다음을 실행해야 합니다:

```bash
tuist auth whoami --url https://tuist.dev
```

해당 명령이 인증되지 않은 경우 에이전트는 중단하고 사용자에게 다음을 실행하도록 요청해야 합니다:

```bash
tuist auth login --url https://tuist.dev
```

로컬 또는 자체 호스팅 배포의 경우 두 명령과 `tuist.toml`의 URL을 대체하세요. 모든 곳에서 호스트 이름 표기를 동일하게 유지하세요. 예를 들어 `localhost`와 `127.0.0.1`는 별도의 저장된 자격 증명을 사용합니다.


## 기능

### 도구

다음 도구는 Tuist Model Context Protocol 서버를 통해 사용할 수 있습니다:

모든 도구는 사람이 읽을 수 있는 설명과 명시적인 입력 및 출력 스키마를 함께 제공합니다. 성공적인 호출은 광고된 출력 스키마를 준수하는 구조화된 콘텐츠를 반환하며, 아직 구조화된 콘텐츠를 사용하지 않는 클라이언트를 위해 동일한 결과를 텍스트로 직렬화하여 제공합니다.

`build_run_id`, `test_run_id`, `test_case_id`, `bundle_id`, `run_id`, `generation_id` 또는 `cache_run_id`와 같이 단일 레코드의 식별자를 받는 도구는 해당 레코드의 Tuist 대시보드 URL도 허용합니다. 식별자를 추출하지 말고 브라우저에서 URL을 직접 붙여넣으세요.

#### 문서 및 커뮤니티 검색

이 읽기 전용 도구는 문서 웹사이트를 구동하는 것과 동일한 검색 엔진을 통해 Tuist의 문서, [application programming interface](https://en.wikipedia.org/wiki/API) 참조, GitHub 릴리스, 커뮤니티 포럼 및 GitHub 이슈를 검색합니다. 릴리스 결과에는 제품, 버전, 게시 날짜 및 프리릴리스 상태가 포함됩니다. 기본적으로 안정 릴리스가 검색되며, `include_prereleases`를 사용하여 프리릴리스를 포함할 수 있습니다. 이 도구는 `https://tuist.dev/mcp`의 Tuist 호스팅 서버에서만 사용할 수 있습니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `search_tuist` | 공개 Tuist 문서, application programming interface 참조, GitHub 릴리스, 커뮤니티 토론 및 GitHub 이슈를 검색합니다. 선택적으로 하나의 `source` (`docs`, `api_reference`, `releases`, `forum`, `issues`)로 제한할 수 있습니다. | `query` |

#### 소스 기반 답변

이러한 읽기 전용 도구를 사용하면 에이전트가 현재 동작에 의존하는 답변의 신뢰할 수 있는 출처로서 호스팅 서버와 함께 배포된 정확한 공개 Tuist 소스 리비전을 사용할 수 있습니다. 이 도구들은 `https://tuist.dev/mcp`에서만 사용할 수 있습니다.

호환되는 클라이언트는 인라인 OAuth 인증 정보와 함께 초기화 중에 도구의 소스 리비션, 링크 및 결과 제한에 대한 사실적 설명을 받습니다. 이러한 설명은 답변 스타일이나 검증 워크플로를 규정하지 않습니다. 사용자는 `ask_tuist` 프롬프트를 먼저 호출하지 않고도 직접 질문할 수 있으며, 명시적인 소스 기반 워크플로를 위해 프롬프트는 계속 사용할 수 있습니다.

모든 작업에는 동시성, 지속 시간, 탐색, 읽은 바이트 수 및 응답 크기에 대한 고정 제한이 있습니다. 검색 및 목록 결과에는 `truncated` 및 `truncation_reason` 필드가 포함됩니다. 결과가截断되면 결과를 완전한 것으로 취급하지 말고 경로, 파일 패턴 또는 검색어를 좁히세요.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `search_tuist_code` | 소스 파일을 검색하여 현재 동작, 기본값, 구성, 기능 게이트, 오류 처리 또는 문서화되지 않은 세부 사항에 대한 질문에 답합니다. 결과에는 주변 줄, 리비전 고정 소스 링크 및 스캔 통계가 포함됩니다. | `pattern` |
| `list_tuist_files` | 관련 경로를 알 수 없을 때 소스 하위 시스템 또는 nearby 테스트를 발견합니다. 목록은 깊이와 결과 수가 제한되어 있습니다. | 없음 |
| `read_tuist_file` | 관련 경로를 찾은 후 구현 파일, 호출 사이트 또는 테스트에서 특정 줄 범위를 검사합니다. 截断된 응답은 계속하기 위해 `next_start_line`를 제공합니다. | `path` |

#### 프로젝트

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_accounts` | 인증된 사용자가 사용할 수 있는 개인 및 조직 계정 핸들을 나열하며, 각 계정이 프로젝트를 생성할 수 있는지 여부도 포함합니다. | 없음 |
| `get_organization` | 조직의 멤버 디렉터리를 가져옵니다. 대기 중인 초대는 대시보드와 동일한 관리자 권한이 필요하며, 초대 수락 토큰은 절대 반환되지 않습니다. | `account_handle` |
| `create_organization` | 인증된 사용자를 위한 Tuist 조직을 생성합니다. | `handle` |
| `create_project` | 인증된 사용자가 접근할 수 있는 계정 아래에 Tuist 프로젝트를 생성합니다. | `account_handle`, `project_handle` |
| `add_organization_member` | 기존 Tuist 사용자를 조직에 추가하거나 기존 멤버의 역할을 업데이트합니다. `user`(기본값), `admin` 또는 `viewer`를 허용하며, 뷰어는 대시보드와 실행을 읽을 수 있지만 아무 것도 변경할 수 없습니다. | `organization_handle`, `email` |
| `invite_organization_member` | 기존 Tuist 사용자에게 속해 있는지 여부와 상관없이 이메일 주소를 조직에 초대합니다. Tuist는 14일 후에 만료되는 수락 링크를 이메일로 보냅니다. 서버가 이메일을 보낼 수 없는 경우 `email_sent`는 `false`이며 링크는 대시보드에서 복사해야 합니다. `user`(기본값), `admin` 또는 `viewer`를 허용합니다. 조직 관리자 권한이 필요합니다. | `organization_handle`, `email` |
| `cancel_organization_invitation` | 대기 중인 조직 초대를 취소하여 해당 링크를 더 이상 수락할 수 없게 합니다. 조직 관리자 권한이 필요합니다. | `organization_handle`, `email` |
| `list_projects` | 인증된 사용자가 접근할 수 있는 모든 프로젝트를 나열합니다. | 없음 |
| `get_project` | 프로젝트의 구성과 연결된 저장소 URL을 가져옵니다. | `account_handle`, `project_handle` |
| `connect_project_repository` | 계정의 GitHub App 설치가 접근할 수 있는 GitHub 저장소에 프로젝트를 연결합니다. 프로젝트는 저장소의 기본 브랜치를 채택합니다. 프로젝트 관리자 권한이 필요합니다. | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 프로젝트의 GitHub 저장소 링크를 제거합니다. 프로젝트 관리자 권한이 필요합니다. | `account_handle`, `project_handle` |

#### 계정 토큰

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_account_tokens` | 토큰 값을 노출하지 않고 계정 토큰 메타데이터를 나열합니다. | `account_handle` |
| `get_account_token` | 값을 노출하지 않고 계정 토큰 메타데이터를 가져옵니다. | `account_handle`, `token_id` |
| `list_project_tokens` | 토큰 값을 노출하지 않고 프로젝트 토큰 메타데이터를 나열합니다. | `account_handle`, `project_handle` |

#### CI 러너

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_runner_jobs` | 계정의 CI 러너 작업을 나열합니다. | `account_handle` |
| `get_runner_job` | CI 러너 작업을 가져옵니다. | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | CI 러너 작업에 대해 기록된 단계를 나열합니다. | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | CI 러너 작업에 대해 기록된 머신 메트릭을 나열합니다. | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | CI 러너 작업에 대해 캡처된 최대 500개의 로그 줄을 나열합니다. | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 계정의 CI 워크플로 요약 정보를 나열합니다. | `account_handle` |
| `list_runner_profiles` | 각 러너 프로파일의 `runs-on` 라벨과 함께 계정의 CI 러너 프로파일을 나열합니다. | `account_handle` |
| `get_runner_catalog` | 러너 프로파일이 사용할 수 있는 머신 셰이프와 Xcode 버전을 나열합니다. | `account_handle` |
| `create_runner_profile` | 플랫폼, 머신 셰이프 및 macOS의 경우 Xcode 버전으로 러너 프로파일을 생성합니다. 선택적으로 캐시 볼륨을 저장할 브랜치를 설정할 수 있습니다. 계정 관리 권한 또는 `account:runners:write` 범위가 필요합니다. | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 러너 프로파일의 머신 셰이프, Xcode 버전 또는 사용자 정의 캐시 볼륨 변경 사항을 저장할 브랜치를 변경합니다. 누락된 필드는 기존 값을 유지합니다. 계정 관리 권한 또는 `account:runners:write` 범위가 필요합니다. | `account_handle`, `profile_name` |
| `delete_runner_profile` | 사용자 확인 후 러너 프로파일을 삭제합니다. 기본 프로파일은 삭제할 수 없습니다. 계정 관리 권한 또는 `account:runners:write` 범위가 필요합니다. | `account_handle`, `profile_name` |

러너 볼륨 도구는 볼륨 대시보드와 동일한 데이터를 노출합니다. 읽기 도구에는 러너 접근 권한이 필요하며, 지우기 작업에는 계정 관리 권한 또는 `account:runners:write` 범위와 사용자 확인이 필요합니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_runner_volumes` | 이름과 저장소로 필터링하고, 볼륨을 정렬 및 페이지네이션합니다. | `account_handle` |
| `get_runner_volume` | 저장소, 플랫폼, 용량, 사용 공간 및 마지막 사용 시간입니다. | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 페이지네이션된 작업 및 워크플로 참조, 캐시 상태, 히트 결과 및 마운트 시간입니다. | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 작업에서 마운트된 볼륨입니다. | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 스토리지 시계열, 작업 실행, 히트율 및 추세입니다. 선택적 `volume_id`, `start` 및 `end`(ISO 8601); 기본값은 7일이며 최대 90일입니다. | `account_handle` |
| `clear_runner_volume` | 저장된 내용을 지웁니다. 실행 중인 작업은 개인 복사본을 유지하지만 저장할 수 없으며, 이후 작업은 빈 상태로 시작합니다. | `account_handle`, `volume_id` |

목록은 `page` 및 `page_size`(최대 100)를 허용합니다. 볼륨 인벤토리는 또한 `name` 및 `repository`(정확히 일치, AND 조합), `sort_by`(`volume`, `repository`, `used_space`, `capacity`, `last_used`) 및 `sort_order`(`asc`, `desc`)를 허용합니다. 알 수 없는 측정값과 히트 결과는 `null`로 남습니다. 캐시 상태는 작업 성공 여부가 아닌 볼륨 변경 사항이 저장되었는지 여부를 설명합니다.

#### 웹훅

웹훅 도구는 대시보드와 동일한 관리자 전용 권한을 사용합니다. 전달 시도에는 엔드포인트에 대해 기록된 요청 및 응답 데이터가 포함되지만 엔드포인트 서명 비밀은 절대 포함되지 않습니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 계정의 웹훅 엔드포인트를 나열합니다. | `account_handle` |
| `get_webhook_endpoint` | 웹훅 엔드포인트를 가져옵니다. | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 엔드포인트의 전달 시도를 나열합니다. | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 전달 시도를 가져옵니다. | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 빌드

Xcode, Gradle, Bazel, Mix 및 Cargo용 빌드 상세 도구는 기존 `custom_metadata: {tags, values}` 구조를 노출하며, 보고된 경우 인프라 관찰 데이터도 포함합니다. 값은 문자열로 유지되며 익숙하지 않은 키는 보존됩니다. 예를 들어, `tuist.cpu.available_processors`는 런타임에 사용 가능한 논리 프로세서를 설명하고, `tuist.gradle.max_workers`는 Gradle 작업자 제한이며, `tuist.jvm.max_heap_bytes`는 호스트 메모리가 아닌 JVM 힙 제한입니다. 이들은 신뢰할 수 없는 클라이언트 관찰 데이터이며, 검증된 러너 신원이 아닙니다. 관찰 데이터가 없으면 그대로 누락되며, 가져온 로그와 이전 클라이언트에는 인프라 메타데이터가 없을 수 있습니다. Once 메타데이터는 조정된 클라이언트/프로토콜 업데이트를 기다리고 있습니다.

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_xcode_builds` | 프로젝트의 Xcode 빌드 실행을 나열합니다. | `account_handle`, `project_handle` |
| `get_xcode_build` | 특정 Xcode 빌드 실행에 대한 자세한 정보를 가져옵니다. 여기에는 원본 `.xcactivitylog`을 포함하는 아카이브의 임시 다운로드 URL이 포함됩니다. | `build_run_id` |
| `list_xcode_build_targets` | 특정 Xcode 빌드 실행의 빌드 타겟을 나열합니다. | `build_run_id` |
| `list_xcode_build_files` | 특정 Xcode 빌드 실행의 컴파일된 파일을 나열합니다. | `build_run_id` |
| `list_xcode_build_steps` | 로그 텍스트 없이 타이밍과 결과가 포함된 기록된 빌드 단계를 나열합니다. | `build_run_id` |
| `get_xcode_build_step` | 로그 및 truncation 플래그를 포함한 기록된 빌드 단계 하나를 가져옵니다. | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 특정 빌드 실행의 빌드 문제(경고 및 오류)를 나열합니다. | `build_run_id` |
| `list_xcode_build_cache_tasks` | 특정 Xcode 빌드 실행의 캐시 가능 작업(캐시 히트/미스)을 나열합니다. | `build_run_id` |
| `list_xcode_build_cas_outputs` | 특정 Xcode 빌드 실행의 [콘텐츠 주소 지정 스토리지](https://en.wikipedia.org/wiki/Content-addressable_storage) 출력을 나열합니다. | `build_run_id` |

`list_xcode_build_steps`는 기본적으로 20개의 단계 페이지를 반환하며(`page_size`를 통해 최대 100개), 탐색을 위해 `page` 및 `pagination_metadata`를 제공합니다. `search`를 사용하여 제목, 프로젝트 또는 타겟을 일치시키거나, 정확한 `project`, `target`, `category`(예: `swiftCompilation`) 및 `status`(`success` 또는 `failure`)로 필터링합니다. 가장 느린 순서(기본값)로 정렬하려면 `duration_ms`를, 시간순으로 정렬하려면 `start_ms`를 사용하세요. 단계 ID는 동점 처리를 위해 사용되며 전체 64비트 정밀도를 유지하기 위해 10진수 문자열로 반환됩니다. ID는 빌드 범위 내에서 고유하므로 빌드 간에 일치시켜서는 안 됩니다.

선택적 `start_ms` 및 `end_ms`는 빌드 시작부터 밀리초 단위의 시간 범위와 겹치는 단계를 선택합니다(끝 시간은 제외). 두 도구 모두 빌드 UUID 또는 대시보드 URL을 `build_run_id`로 허용합니다. 반환된 단계 `id`를 `step_id`로 변경 없이 전달하여 로그를 검색하세요. 로그는 단계당 최대 64 KiB까지 유지되며, `log_truncated`는 생략된 출력을 나타냅니다.

단계는 Xcode 빌드가 처리될 때 기본적으로 수집됩니다. 기록된 단계 데이터는 90일 동안 보관됩니다. 목록 응답에는 `availability`이 포함됩니다: 기록된 단계가 존재하면 필터와 일치하는 항목이 없어도 `available`; 빌드가 아직 처리 중이고 단계가 없으면 `processing`; 단계가 기록되지 않았거나 만료되면 `unavailable`.

동일한 작업은 HTTP API의 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 및 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}`에서 동일한 필터와 페이지네이션으로 사용할 수 있습니다. 둘 다 빌드 프로젝트에 대한 읽기 접근 권한이 필요합니다.

#### Gradle 빌드

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 완전한 인증, 프로젝트 설정, Gradle 플러그인, 캐시 정책 및 2회 빌드 검증 워크플로를 반환합니다. 에이전트는 기존 Android 또는 Gradle 프로젝트를 편집하기 전에 이를 호출해야 합니다. | 없음 |
| `list_gradle_builds` | 프로젝트의 Gradle 빌드 실행을 커스텀 메타데이터와 함께 나열합니다. 선택적 `tag` 매개변수를 사용하여 커스텀 태그로 필터링합니다. | `account_handle`, `project_handle` |
| `get_gradle_build` | 빌드 메타데이터와 작업/캐시 개수를 가져옵니다. | `build_run_id` |
| `list_gradle_build_tasks` | 작업 결과, 복합 빌드 식별자, 캐시 가능성 및 증분 상태를 나열합니다. | `build_run_id` |
| `list_gradle_build_steps` | 검색, 메타데이터 및 중복 시간 필터를 사용하여 시간이 측정된 작업, 구성 및 변환을 나열합니다. | `build_run_id` |
| `get_gradle_build_step` | 불투명 ID로 기록된 단계 메타데이터를 검사합니다. 단계별 로그는 사용할 수 없습니다. | `build_run_id`, `step_id` |

Gradle 및 Bazel 단계 목록은 기본적으로 20개 결과(최대 100개)를 반환하며, `search`, 정확한 `project`, `target`, `category` 및 `status`, 중복 `start_ms` / `end_ms` 필터(끝 제외), 그리고 `duration_ms` 또는 `start_ms` 정렬을 지원합니다. 반환된 ID를 변경 없이 전달하세요. 이는 해당 빌드 범위에 속합니다. 목록은 `time_origin` 및 `coverage`을 노출합니다. 이전 Gradle 보고서는 빌드 시작 시간이 업로드되지 않았으므로 `first_recorded_timestamp`를 사용합니다. Bazel 프로파일은 `trace_profile` 커버리지와 시간 원점으로 `profile_start`를 사용하여 모든 기록된 간격을 노출합니다. 이전 빌드는 보존된 BEP 요약으로 대체됩니다. 소스 기록은 90일 후에 만료됩니다. Bazel 세부 정보에는 게시된 경우 sanitize된 작업 로그가 포함되며, Gradle 세부 정보 `log`는 null입니다. `compare_builds` 프롬프트는 이 커버리지를 사용하여 전체 Bazel 추적과 보존된 요약을 구분하고, 더 넓은 호출 출력을 확인하기 전에 작업 결과 및 로그를 위한 단계 세부 정보로 에이전트를 안내합니다.

목록 조회와 단계 가져오기 사이에 전체 프로파일이 도착하면, 보존된 요약에서 반환된 Bazel 단계 ID는 여전히 읽을 수 있습니다. 단계 데이터가 만료된 인덱싱된 프로파일은 사용 불가로 보고됩니다. Gradle 단계 목록에는 지속 시간이 0인 캐시된 작업과 건너뛴 작업이 포함됩니다.

#### Bazel 호출

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 인증, 프로젝트 설정, Bazel 구성 및 검증 워크플로를 반환합니다. | 없음 |
| `list_bazel_invocations` | 프로젝트의 빌드 지표, 제한된 실행 타임라인, 임계 경로 진단 및 상관관계가 있는 원격 캐시 합계가 포함된 완료된 [Bazel Build Event Protocol](https://bazel.build/remote/bep) 호출을 나열합니다. | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 빌드 지표, 제한된 실행 타임라인, 임계 경로 진단 및 상관관계가 있는 원격 캐시 합계가 포함된 완료된 Bazel 호출 하나를 가져옵니다. | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 필터와 명시적 커버리지가 포함된 기록된 Bazel 프로파일 간격을 나열합니다. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 기록된 Bazel 단계와 게시된 작업 결과 및 sanitize된 로그를 검사합니다. | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | Bazel 호출에 대해 캡처된 sanitize된 테스트 로그를 실행 순서대로 나열합니다. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bazel 호출에 대해 캡처된 sanitize된 테스트 로그 하나를 가져옵니다. | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 작업, 엔드포인트 및 관찰 시간이 포함된 원시 Bazel 원격 캐시 관찰 결과를 나열하며, 선택적으로 호출, 결과 또는 작업으로 범위를 좁힐 수 있습니다. | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 원시 Bazel 원격 캐시 관찰 결과 하나를 가져옵니다. | `account_handle`, `project_handle`, `cache_event_id` |

#### Cargo 빌드

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_cargo_builds` | 프로젝트의 Cargo 빌드를 최신 순으로 나열합니다. `git_branch`, `status`, `is_ci` 또는 `command`로 필터링할 수 있습니다. Cargo 테스트 실행 결과는 이 빌드 목록이 아닌 테스트 도구를 통해 사용할 수 있습니다. | `account_handle`, `project_handle` |
| `get_cargo_build` | 빌드 메타데이터와 히트, 작업 미스 및 히트율을 포함한 집계 캐시 카운터를 가져옵니다. | `account_handle`, `project_handle`, `build_id` |

#### Mix 빌드

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_mix_builds` | 프로젝트의 Mix(Elixir) 컴파일 빌드를 최신 순으로 나열하며, custom metadata를 포함합니다. `git_branch`, `status`, `is_ci` 또는 `mix_env`로 필터링할 수 있습니다. | `account_handle`, `project_handle` |
| `get_mix_build` | 빌드 메타데이터, 진단 카운트 및 의존성 캐시 요약을 가져옵니다. | `account_handle`, `project_handle`, `build_id` |

#### Once 실행

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_once_runs` | 프로젝트의 Once 실행을 최신 순으로 나열합니다. `kind`(`build`, `test` 또는 `generic`), `status`, `is_ci` 또는 `git_branch`로 필터링할 수 있습니다. 완료되지 않은 실행의 상태는 `in_progress`입니다. | `account_handle`, `project_handle` |
| `get_once_run` | 실행과 해당 작업 합계, 캐시 요약, 그리고 테스트 실행의 경우 테스트 합계를 가져옵니다. | `account_handle`, `project_handle`, `run_id` |

Cargo 빌드, Mix 빌드 및 Once 실행 ID는 프로젝트 내에서 고유합니다. 동일한 읽기 작업은 HTTP API를 통해 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, `.../mix/builds` 및 `.../once/runs`에서 사용할 수 있으며, 각각 하나의 ID에 대한 세부 정보 엔드포인트가 있습니다.

#### 작업, 액션, 모듈 및 파일

이 프로젝트 범위 도구는 실행 간에 지속적인 빌드 식별자를 검사합니다. `list_build_entities`로 시작한 다음, 반환된 안정적인 `id`를 동일한 `kind`와 함께 `get_build_entity` 또는 `list_build_entity_history`에 전달하고, `account_handle` 및 `project_handle`도 함께 전달합니다. 빌드 또는 호출 식별자는 필요하지 않습니다.

| 도구 | 설명 | 필수 매개변수 |
| --- | --- | --- |
| `list_build_entities` | 프로젝트의 빌드 전체에서 확인된 한 종류의 작업, 모듈, 액션 또는 파일을 나열합니다. | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 선택한 기간에 대한 네이티브 식별자 및 분석 정보가 포함된 빌드 엔티티 하나를 가져옵니다. | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 하나의 빌드 엔티티에 대해 기록된 실행, 컴파일 또는 캐시 이벤트를 최신 순으로 나열합니다. | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 툴체인 | 히스토리 목록 |
| --- | --- | --- |
| `bazel_actions` | Bazel 액션 | BEP 보고된 작업 실행 |
| `gradle_tasks` | Gradle 작업 | 작업 실행 |
| `xcode_modules` | Xcode 모듈 | 컴파일 및 모듈 캐시 이벤트 |
| `once_actions` | Once 액션 | 실행 |
| `mix_files` | Mix 컴파일 파일 | 컴파일 |
| `mix_modules` | Mix 컴파일 모듈 | 컴파일 |

이 도구들은 점진적으로 출시되며, 활성화된 프로젝트에 대해서만 데이터를 반환합니다. 다른 프로젝트의 경우 빈 결과 대신 오류를 반환합니다. 종류(kind)는 해당 빌드 툴체인을 사용하는 프로젝트에서만 사용할 수 있습니다. 이 도구들은 제한된 `start_at`/`end_at` 필터, `environment`(`any`, `ci` 또는 `local`) 및 정확한 `branch`를 허용합니다. `list_build_entities`는 `q`를 허용하며, `list_build_entity_history`는 불투명한 `after`/`before` 커서를 지원합니다. 알 수 없는 타이밍 또는 캐시 관찰 데이터는 0이나 미스로 처리되지 않고 사용 불가 상태로 유지됩니다. 히스토리는 기존 실행 도구를 사용한 드릴다운을 위해 기록된 부모 및 네이티브 실행을 참조합니다.

`get_build_entity` 메트릭에는 기록된 타이밍이 있는 관찰 횟수인 `duration_samples`가 포함됩니다. 실제 0 지속 시간은 카운트되지만, 누락된 타이밍은 카운트되지 않습니다. 이 카운트는 관찰 횟수보다 낮을 수 있으며, 사용 불가능한 지속 시간 통계는 null로 유지됩니다.

Xcode 모듈 지속 시간은 빌드 로그에서 측정된 타겟 컴파일에서 가져옵니다. 모듈 캐시 해결 및 컴파일 작업이 없는 타겟은 지속 시간 샘플에 기여하지 않습니다. 컴파일 관찰 데이터는 Xcode 빌드를 참조하며, 캐시 이벤트는 생성 또는 캐시 명령을 참조합니다.

Bazel 액션은 타겟 라벨, 니모닉 및 구성된 기본 출력으로 식별되며, 입력 종속 캐시 다이제스트에 의존하지 않고 별도의 액션과 구성을 명확하게 구분합니다. 히스토리는 캐시 조회나 트레이스 프로파일 단계가 아닌 BEP 보고 실행을 기록합니다. 완전한 실행 커버리지를 위해서는 `--build_event_publish_all_actions`가 필요합니다. 아티팩트 전달은 최선의 노력을 기반으로 하므로, 누락된 관찰 데이터가 작업이 실행되지 않았다는 증거가 되지는 않습니다. 안정적인 식별자 또는 실행 시작 정보가 없는 이전 Kura 페이로드는 여전히 허용되지만 인덱싱되지 않습니다. 종료 시간 측정이 없는 경우 사용 불가 상태로 유지되며, 실제 0 지속 시간은 카운트됩니다.

Mix 모듈 지속 시간은 독립적으로 측정된 모듈 작업이 아닌 포함하는 파일의 컴파일을 측정합니다. Once 액션은 클라이언트가 타겟 매핑을 보고할 때 선언된 타겟/기능/인덱스 슬롯을 사용합니다. 진단 레이블만으로는 안정적인 식별자가 되지 않습니다. 기존 클라이언트 및 실행 수준 도구는 변경 없이 계속 지원됩니다.

분석 읽기 작업은 메모리와 실행 시간이 제한되어 있습니다. 쿼리가 이러한 제한을 초과하면 도구는 빈 결과를 생성하는 대신 오류를 반환합니다.

새로운 관찰 데이터는 배포 후 인덱싱됩니다. 이 기능은 기존 실행 텔레메트리를 백필하지 않습니다. 식별자 메타데이터는 <.localized_link href="/guides/server/data-retention">데이터 보존 정책</.localized_link>에 따라 개별 관찰 데이터보다 오래 유지됩니다.

#### 테스트

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_test_runs` | 프로젝트의 테스트 실행을 나열합니다. `query` 필드는 `git_branch`, `scheme` 및 `status`입니다. `field:"value"`는 정확히 일치하며, `field~"value"`는 대소문자를 구분하지 않는 부분 문자열과 일치하고, 선행 `-`는 두 연산자 중 하나를 부정합니다. 예를 들어, `-git_branch~"gh-readonly-queue"`는 병합 큐 브랜치를 제외합니다. 공백으로 구분된 쿼리 필터와 명시적 인수는 AND 의미론으로 결합됩니다. | `account_handle`, `project_handle` |
| `get_test_run` | 테스트 실행에 대한 상세 메트릭을 가져오며, 결과 번들(`.xcresult`) 및 세션 아카이브에 대한 임시 다운로드 URL을 포함합니다. | `test_run_id` |
| `list_test_module_runs` | 특정 테스트 실행에 대한 테스트 모듈 실행을 나열합니다. | `test_run_id` |
| `list_test_suite_runs` | 특정 테스트 실행에 대한 테스트 스위트 실행을 나열하며, 선택적으로 모듈로 필터링할 수 있습니다. | `test_run_id` |
| `list_test_cases` | 프로젝트의 테스트 케이스를 나열합니다(`flaky`와 같은 필터를 지원합니다). | `account_handle`, `project_handle` |
| `get_test_case` | 신뢰성 비율, 불안정성 비율 및 실행 횟수를 포함한 테스트 케이스에 대한 상세 메트릭을 가져옵니다. | `test_case_id` 또는 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 테스트 케이스 실행을 나열하며, 선택적으로 테스트 케이스 또는 테스트 실행으로 필터링할 수 있습니다. | `account_handle`, `project_handle` |
| `get_test_case_run` | 특정 테스트 케이스 실행에 대한 실패 세부 정보 및 반복 횟수를 가져옵니다. | `test_case_run_id` |
| `list_test_case_run_attachments` | 테스트 케이스 실행에 대한 첨부 파일을 나열합니다. 각 첨부 파일에는 임시 다운로드 URL이 포함됩니다. | `test_case_run_id` |
| `list_test_case_events` | 음소거 또는 건너뛰기와 같은 테스트 케이스의 상태 변경 사항을 나열합니다. | `test_case_id` |
| `update_test_case` | 테스트 케이스의 상태 또는 불안정성 분류를 업데이트합니다. 변경 사항은 외부 서비스를 포함한 구성된 웹훅 엔드포인트로 이벤트를 전송할 수 있습니다. | `test_case_id` 또는 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 테스트 실행에 대한 선택적 테스트 타겟 결과를 나열합니다. | `test_run_id` |
| `get_coverage` | 커밋 또는 브랜치의 최신 완료 커밋에서 타겟과 함께 프로젝트의 코드 커버리지를 가져옵니다. `git_commit_sha` 또는 `branch`가 없으면 기본 브랜치를 읽습니다. | `account_handle`, `project_handle` |
| `list_coverage_files` | 커밋 또는 브랜치의 최신 완료 커밋에서 라인 커버리지와 함께 커밋의 코드 커버리지가 측정한 파일을 나열합니다. `search`, 정렬 및 페이지네이션을 지원합니다. | `account_handle`, `project_handle` |
| `get_coverage_file` | 커밋 또는 브랜치의 최신 완료 커밋에서 파일의 코드 커버리지와 해당 함수를 가져옵니다. 각 라인의 실행 횟수를 얻으려면 `include_lines`를 설정하세요. | `account_handle`, `project_handle`, `path` |

코드 커버리지 도구는 코드 커버리지가 활성화된 계정에서 사용할 수 있습니다.

#### 번들

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_bundles` | 프로젝트의 번들(앱 바이너리)을 나열합니다. 선택적으로 `git_branch` 및 `tags`로 필터링할 수 있습니다(모든 태그는 정확히 일치해야 함). | `account_handle`, `project_handle` |
| `get_bundle` | 특정 번들에 대한 상세 정보를 가져오며, 여기에는 사용자 정의 태그가 포함됩니다. | `bundle_id` |
| `get_bundle_artifact_tree` | 번들의 전체 아티팩트 트리를 경로별로 정렬된 평면 목록으로 가져옵니다. | `bundle_id` |

`list_bundles`는 빌드 변형이나 환경을 구분하기 위해 `tags: ["paid", "production"]`를 허용합니다. 태그는 대소문자를 구분하는 라벨로, 문자, 숫자, 하이픈 또는 밑줄을 포함하며 태그당 최대 10개와 50자의 제한이 있습니다. 목록 및 상세 결과에는 `custom_metadata.tags`가 포함됩니다. 페이지네이션 카운트와 브랜치 필터는 태그가 지정된 결과에 적용되며, `tags`를 생략하면 필터링되지 않은 동작이 유지됩니다. 잘못된 태그 필터는 쿼리를 확장하는 대신 오류를 반환합니다.

#### 제네레이션

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_generations` | 프로젝트의 제네레이션 실행을 나열합니다. | `account_handle`, `project_handle` |
| `get_generation` | 특정 제네레이션 실행에 대한 상세 정보를 가져옵니다. | `generation_id` |

#### 캐시 실행

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_cache_runs` | 프로젝트의 캐시 실행을 나열합니다. | `account_handle`, `project_handle` |
| `get_cache_run` | 특정 캐시 실행에 대한 상세 정보를 가져옵니다. | `cache_run_id` |
| `list_xcode_module_cache_targets` | 제네레이션 또는 캐시 실행에 대한 모듈 캐시 타겟을 나열하며, 추가 해싱 입력을 포함한 타겟별 캐시 히트/미스 상태와 진단 컴포넌트 해시를 표시합니다. | `run_id` |

#### 프리뷰

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_previews` | 프로젝트의 공유 가능한 앱 프리뷰를 나열합니다. | `account_handle`, `project_handle` |
| `get_preview` | 프리뷰와 해당 빌드에 대한 임시 다운로드 URL을 가져옵니다. | `preview_id` |
| `get_latest_preview` | 실행 중인 앱 바이너리에 대한 최신 프리뷰를 찾습니다. | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 자동화

| 도구 | 설명 | 필수 매개변수 |
|------|-------------|---------------------|
| `list_automation_alerts` | 프로젝트의 자동화 알림을 나열합니다. | `account_handle`, `project_handle` |
| `get_automation_alert` | 자동화 알림을 가져옵니다. | `alert_id` |
| `list_automation_alert_revisions` | 자동화 알림의 수정 기록을 나열합니다. 작업 자격 증명은 삭제됩니다. | `alert_id` |
| `list_project_notification_alerts` | 프로젝트 알림 알림 규칙을 나열합니다. 대시보드 설정 페이지와 동일한 관리자 권한이 필요합니다. 웹훅 주소는 삭제됩니다. | `account_handle`, `project_handle` |

### 이벤트

상태 비저장 `2026-07-28` 모델 컨텍스트 프로토콜 라이프사이클을 사용하는 클라이언트는 `events/list`를 호출하여 이벤트와 해당 페이로드 스키마를 발견할 수 있습니다:

| 이벤트 | 전송 시기 | 구독 필터 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 테스트 케이스가 불안정하지 않음에서 불안정함으로 변경됩니다. | `account_handle`, `project_handle` |
| `build.failed` | 로컬 또는 지속적 통합 Xcode, Gradle 또는 Bazel 빌드가 실패로 종료됩니다. | `account_handle`, `project_handle` |
| `test_run.failed` | 로컬 또는 지속적 통합 테스트 실행이 실패로 종료되며, 병합된 샤딩 실행 또는 중단된 실행이 포함됩니다. | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist 러너 작업이 실패로 완료됩니다. | `account_handle` |

구독하려면 클라이언트는 이벤트 이름, 위에 나열된 핸들을 `arguments`에 포함하고, `https://` 콜백 URL과 `whsec_` 서명 비밀을 포함한 `webhook` 전달 방식으로 `events/subscribe`를 호출합니다. 프로젝트 이벤트는 계정 멤버십과 해당 테스트 또는 빌드 데이터에 대한 읽기 권한이 필요하며, 러너 작업 이벤트는 계정 멤버십과 러너 읽기 권한이 필요합니다. 인증된 [`auth.md`](https://workos.com/auth-md) 액세스 토큰, 인증된 계정 토큰 및 브라우저 승인 부여로 구독을 생성할 수 있으며, 관련 자격 증명이 더 이상 활성화되지 않으면 전달이 중단됩니다. 각 사용자는 최대 25개의 활성 구독을 유지할 수 있습니다. Tuist는 구독을 저장하기 전에 콜백으로 확인 챌린지를 보냅니다. 콜백은 동일한 `challenge` 값을 포함하는 객체를 반환해야 합니다. 구독은 기본적으로 7일 동안 지속되며, 다시 구독하여 갱신할 수 있고, 사용자의 액세스 또는 자격 증명이 제거되면 전달이 중단됩니다. 선택적 `ttlMs`는 1시간에서 30일 사이로 제한됩니다. Tuist는 시간 초과된 콜백을 재시도하며, 5분에 걸쳐 최소 세 번 연속 시간 초과가 발생하면 구독을 해제합니다. 콜백을 복구한 후 다시 구독하세요.

이벤트가 발생하면 Tuist는 리소스 식별자와 대시보드 URL을 콜백으로 보냅니다. 빌드 및 테스트 실행 실패에는 `is_ci`와 `git_branch`도 포함되므로, 클라이언트는 로컬 실패를 무시하거나 브랜치별로 필터링할 수 있습니다. 빌드 이벤트에는 `build_system`가 포함되며, 러너 작업 이벤트에는 `workflow_job_id`와 `workflow_run_id`가 모두 포함됩니다. 요청에는 구독 식별자와 [Standard Webhooks](https://www.standardwebhooks.com/) 서명 헤더가 포함되어 있어 클라이언트가 출처를 확인할 수 있습니다. Tuist는 실패한 전달을 재시도하므로, 클라이언트는 안정적인 `eventId`를 사용하여 중복 항목을 제거해야 합니다. 페이로드에는 테스트 이름, 로그 및 실패 메시지가 생략되어 있으며, 클라이언트는 위의 도구를 통해 이러한 세부 정보를 가져와 팀에 알림을 보낼지 또는 디버깅을 시작할지 결정할 수 있습니다. 클라이언트는 `events/unsubscribe`로 전달을 중단할 수 있습니다.

### 프롬프트

| 프롬프트 | 설명 |
|--------|-------------|
| `fix_flaky_test` | 실패 패턴을 분석하고 근본 원인을 식별하며 대상 수정을 적용하여 불안정한 테스트를 해결하는 과정을 안내합니다. |
| `compare_builds` | 두 빌드 실행을 비교하여 성능 저하, 캐시 변경 사항 및 빌드 문제를 식별하는 과정을 안내합니다. Xcode 및 Gradle 프로젝트 모두에서 작동합니다. |
| `compare_test_runs` | 두 테스트 실행을 비교하여 회귀, 새로운 실패 및 불안정한 테스트를 식별하는 과정을 안내합니다. |
| `compare_bundles` | 두 번들을 비교하여 아티팩트 트리 전반의 크기 변경 사항을 식별하는 과정을 안내합니다. |
| `compare_test_case` | 두 브랜치 또는 시간 기간에 걸쳐 테스트 케이스의 동작을 비교하는 과정을 안내합니다. |
| `compare_generations` | 두 제네레이션 실행을 비교하여 성능 저하 및 모듈 캐시 변경 사항을 식별하는 과정을 안내합니다. |
| `compare_cache_runs` | 두 캐시 실행을 비교하여 캐시 효율성 변경 사항 및 타겟 수준 회귀를 식별하는 과정을 안내합니다. |
| `integrate_gradle_project` | 기존 Gradle 프로젝트에 Tuist를 통합하는 과정을 안내합니다. 별도의 도구 및 Gradle 인증, 계정 검색, 프로젝트 생성, 원격 캐시 정책, 빌드 인사이트 및 읽기back 검증이 포함됩니다. |
| `integrate_bazel_project` | Bazel 프로젝트를 생성하거나 선택하고, 명령줄을 인증하며, 원격 캐시 및 빌드 인사이트를 구성하고, Tuist 빌드 데이터를 통해 통합을 검증하는 과정을 안내합니다. |
| `integrate_xcode_project` | 기존 Xcode 프로젝트에 Tuist를 통합하는 과정을 안내합니다. Xcode 캐시, 빌드 인사이트, 테스트 인사이트 및 테스트 샤딩을 지원합니다. |
| `ask_tuist` | 공개 자료를 컨텍스트로 사용하고 현재 동작의 사실 소스로 집중된 구현 및 테스트 증거를 인용하여 Tuist 질문에 답변합니다. `question`가 필요하며 개정 고정 증거를 인용합니다. |

프로젝트 데이터 프롬프트는 조사를 특정 프로젝트로 한정하기 위해 `account_handle`와 `project_handle`를 허용합니다. 비교 프롬프트는 비교할 두 항목(ID, 대시보드 URL 또는 브랜치 이름으로 지정)을 지정하기 위해 `base`와 `head` 인수 또한 허용합니다. `ask_tuist`는 프로젝트 매개변수 대신 `question`를 허용합니다. `integrate_gradle_project`는 적용할 Gradle 통합의 쉼표로 구분된 목록인 `features`도 허용합니다: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests` 및 `test_sharding`. `integrate_bazel_project`는 자체 호스팅 또는 로컬 설치를 위한 선택적 `server_url`를 허용합니다. `integrate_xcode_project`는 `xcode_cache`, `build_insights`, `test_insights` 및 `test_sharding`를 포함한 `features`를 허용합니다.

#### Gradle 통합 프롬프트 기능

`integrate_gradle_project` 프롬프트와 `get_gradle_integration_guide` 도구는 전체 설정 워크플로를 문서화합니다. 이 도구는 서버의 초기화 지침에서도 참조되므로, 프롬프트를 열거하지 않는 에이전트도 발견할 수 있습니다.

| 기능 | 에이전트가 구성하는 내용 |
|---------|---------------------------|
| `remote_cache` | Gradle의 빌드 캐시를 활성화하고, Tuist 원격 캐시 업로드 정책을 구성하며, 로컬 읽기 전용 사용과 함께 지속적 통합 러너에서만 업로드하도록 권장합니다. |
| `build_insights` | Tuist Gradle 플러그인을 적용하고 필요시 빌드 분석 업로드 동작을 구성합니다. |
| `test_insights` | Tuist Gradle 플러그인을 적용하여 Gradle `Test` 작업 결과가 자동으로 업로드되도록 합니다. |
| `flaky_tests` | 불안정한 테스트 감지, 선택적 Gradle Test Retry 플러그인 사용 및 테스트 격리 구성을 위한 설정을 안내합니다. |
| `test_sharding` | `tuistPrepareTestShards`용 지속적 통합 워크플로, 샤드 매트릭스 생성 및 `TUIST_SHARD_INDEX` 기반 테스트 실행을 추가합니다. |

`features`가 생략되면, 프롬프트는 에이전트에게 사용자가 원하는 통합을 명확히 하거나 Gradle 프로젝트를 편집하기 전에 요청에서 가장 작은 유용한 집합을 추론하도록 요청합니다.

#### Xcode 통합 프롬프트 기능

`integrate_xcode_project` 프롬프트는 Tuist가 지원하는 모든 Xcode 통합을 문서화합니다:

| 기능 | 에이전트가 구성하는 내용 |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`, 생성된 프로젝트 캐시 설정, 수동 Xcode 캐시 빌드 설정 및 지속적 통합 러너로 제한된 업로드 정책을 구성합니다. |
| `build_insights` | `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath` 및 `tuist setup insights`를 통한 선택적 머신 메트릭을 구성합니다. |
| `test_insights` | `tuist inspect test`, 스킴 테스트 사후 액션 및 지속적 통합 테스트 실행을 위한 결과 번들 생성을 구성합니다. |
| `test_sharding` | `TUIST_SHARD_INDEX`와 함께 Xcode 또는 생성된 프로젝트 샤드 계획 및 샤드 실행 워크플로를 추가합니다. |

`features`가 생략되면, 프롬프트는 에이전트에게 사용자가 원하는 통합을 명확히 하거나 Xcode 프로젝트를 편집하기 전에 요청에서 가장 작은 유용한 집합을 추론하도록 요청합니다.
