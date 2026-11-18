---
{
  "title": "샌드박스",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 샌드박스는 Amp와 Claude 같은 코딩 에이전트를 위한 영구적인 Linux 및 macOS 가상 머신입니다. 각 에이전트 세션은 자체 머신을 할당받으며, 에이전트가 대기 상태일 때 일시 중지되고 파일이 그대로 유지된 채로 재개됩니다."
}
---
# 샌드박스 {#sandboxes}

> [!IMPORTANT]
> **초대 전용**
>
> Tuist 샌드박스(Linux 및 macOS)는 현재 용량을 확장 중이므로 초대 전용으로 제공됩니다. 계정에 대한 액세스를 요청하려면 [문의](mailto:contact@tuist.dev)하거나 [커뮤니티 Slack](https://slack.tuist.dev)에서 메시지를 보내세요. 샌드박스가 일반 공개될 때 가격 정책이 발표됩니다.

샌드박스는 코딩 에이전트가 명령을 실행하고 파일을 편집하는 가상 머신입니다. 각 에이전트 세션은 고유한 샌드박스를 할당받으며, 세션이 지속되는 동안 체크아웃 상태, 빌드 산출물 및 설치된 도구를 유지합니다. 에이전트가 대기 상태가 되면 샌드박스가 일시 중지되며, 다음 메시지가 도착하면 중단된 지점부터 다시 시작됩니다.

샌드박스는 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>와 동일한 플릿에서 실행되며 팀의 <.localized_link href="/guides/features/cache">캐시</.localized_link> 옆에 위치하므로, 에이전트의 빌드는 CI 및 로컬 머신과 동일한 캐시된 아티팩트를 사용할 수 있습니다.

다음 경로에서 샌드박스를 사용할 수 있습니다:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Tuist에서 Amp 워크스페이스의 Orb를 실행하거나, <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 플러그인</.localized_link>을 사용하여 모든 Amp 스레드에 Xcode 빌드를 위한 Mac을 제공합니다.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Tuist에서 Claude Managed Agents 세션과 Claude Code 클라우드 세션(claude.ai, 데스크톱 및 모바일 앱, 그리고 `claude --cloud`)을 실행합니다.
- **[Tuist CLI](#cli)**: 터미널에서 샌드박스를 생성하고 명령을 실행하거나, API를 통해 자체 도구에서 샌드박스를 사용합니다.

## CLI로 시작하기 {#cli}

터미널에서 `tuist sandbox`를 사용하여 샌드박스를 생성하고 그 안에서 명령을 실행하세요.

### 1. 로그인 {#cli-log-in}

계정의 모든 구성원은 샌드박스를 생성하고 관리할 수 있습니다:

```bash
tuist auth login
```

### 2. 샌드박스 생성 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux의 경우 `--platform`를 생략하세요. 해당 [Xcode](#xcode)가 설치된 Mac을 위해 `--xcode 26.1.1`와 같은 버전을 지정하여 `--xcode`를 전달하면 `--platform macos`가 암시됩니다. 더 큰 [셰이프](#platforms)를 위해 `--memory-gb`와 함께 `--vcpus`를 전달하고, 더 큰 디스크를 위해 `--workspace-gb`를 전달하세요. 명령은 샌드박스가 실행되면 반환되며 ID를 포함한 세부 정보를 출력합니다. 현재 디렉터리의 Tuist 프로젝트 계정을 사용하며, 다른 계정을 선택하려면 `--account`를 전달하세요.

### 3. 명령 실행 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

명령은 샌드박스 내에서 `bash -l`로 실행되며, 일시 중지된 경우 먼저 재개됩니다. `tuist`는 실행 시간과 상관없이 출력을 스트리밍하고 명령의 상태로 종료되며, Ctrl-C를 누르면 샌드박스 내에서 취소됩니다. 필요에 따라 `--cwd`, `--env NAME=VALUE` 및 `--timeout`(최대 6시간)를 전달하세요.

### 일반 작업 {#cli-tasks}

| 작업 | 명령 |
| --- | --- |
| 샌드박스 목록 조회 | `tuist sandbox list` |
| 하나 보기 | `tuist sandbox show <id>` |
| 일시 중지 또는 재개 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 로컬 Git 작업 트리의 파일을 미러링 | `tuist sandbox sync <id>` |
| 파일 복사(내보내기 또는 가져오기) | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 삭제 | `tuist sandbox delete <id> --yes` |
| 사용량 확인 | `tuist sandbox analytics` |

기계 판독 가능한 출력을 위해 `--json`를 추가하세요. 모든 옵션은 <.localized_link href="/cli/sandbox">CLI 참조</.localized_link>를 확인하세요. 코드에서 샌드박스를 제어하려면 `/api/accounts/{account_handle}/sandboxes` 아래의 [Tuist API](https://tuist.dev/api/docs)를 통해 동일한 작업을 수행하거나, 에이전트가 <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>를 통해 사용하도록 하세요.

macOS 샌드박스에서 빌드하는 에이전트 플러그인과 같이 상호작용적으로 로그인할 수 없는 도구는 대신 `account:sandboxes:write` 스코프가 포함된 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>으로 인증할 수 있습니다. 이는 계정 구성원이 할 수 있는 작업(샌드박스 생성, 명령 실행, 일시 중지, 재개, 아카이브 및 삭제)을 수행할 수 있습니다. 통합 설정은 계정 관리자가 담당합니다.

### 샌드박스 내부의 Tuist {#tuist-in-sandbox}

샌드박스 이미지에는 Tuist CLI가 포함되지 않으므로 프로젝트에서 고정(pinned)한 버전이 실행됩니다. 첫 번째 `tuist sandbox sync` 후에 샌드박스의 리포지토리 루트에서 `mise install`를 실행하세요(`mise` 및 `brew`가 설치되어 있음). `tuist sandbox exec`로 시작하는 모든 명령은 mise의 shim(`$HOME/.local/share/mise/shims`)이 `PATH`의 맨 앞에 오도록 하므로, `tuist` 및 기타 mise 도구가 명령과 Xcode 빌드 단계(예: 스킴의 post-actions)에서 실행됩니다.

`tuist sandbox exec`로 시작하는 모든 명령은 Tuist 러너가 받는 것과 동일한 환경을 받으므로, 샌드박스 내의 빌드는 자격 증명을 전달하지 않아도 계정의 <.localized_link href="/guides/features/cache">캐시</.localized_link>를 사용합니다:

- `TUIST_URL` 및 샌드박스 호스트가 접근 가능한 경우(macOS 등), 동일 랙에 있는 캐시의 `TUIST_CACHE_ENDPOINT`.
- 해당 명령을 위한 단기 식별 토큰인 `TUIST_OIDC_TOKEN`. Tuist CLI 4.218.0 이상은 자동으로 이를 사용하여 로그인하며, 4.215.0~4.217.x 버전에서는 동일한 명령 내에서 먼저 `tuist auth login`를 실행하세요.

토큰은 각 명령마다 발행되며 해당 명령이 실행되는 동안만 Tuist 토큰으로 교환할 수 있으므로, 샌드박스는 장기 자격 증명을 보유하지 않습니다. 이 토큰은 명령을 시작한 사람이나 토큰이 캐시에 대해 수행할 수 있는 권한 이상을 부여하지 않습니다. 캐시 쓰기 토큰만 있는 계정 구성원은 읽기 액세스 권한을 얻으며, 샌드박스가 캐시를 사용하려면 `account:sandboxes:write`와 함께 `ci`과 같은 캐시 스코프가 포함된 계정 토큰이 필요합니다. `--env`로 전달한 변수는 우선순위를 가집니다.

## 코딩 에이전트에서 Mac으로 빌드하기 {#coding-agents}

클라우드 에이전트 세션과 같이 Linux에서 실행되는 코딩 에이전트는 파일 편집을 계속하면서 macOS 샌드박스에서 Apple 플랫폼 코드를 빌드, 테스트 및 실행할 수 있습니다. Amp에서는 <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 플러그인</.localized_link>을 설치하세요. Claude Code 또는 Cursor와 같은 다른 에이전트의 경우:

1. 에이전트를 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 서버</.localized_link>에 연결하세요. `create_sandbox` 도구가 에이전트에게 Mac을 제어하는 방법을 알려줍니다.
2. 에이전트가 실행되는 환경(예: 환경 설정 스크립트)에 Tuist CLI를 설치하세요: `mise use -g tuist@latest` 또는 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`(ARM의 경우 `tuist-linux-aarch64`).
3. CLI를 인증하세요. MCP 서버의 로그인은 연동되지 않으므로, 계정 구성원으로 `tuist auth login`를 실행하거나 `account:sandboxes:write` 스코프가 포함된 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>으로 `TUIST_TOKEN`를 설정하세요.
4. 환경에서 네트워크 액세스를 제한하는 경우 `tuist.dev`을 허용하세요. CLI는 이를 통해 Mac으로 파일을 업로드하므로 다른 도메인은 필요하지 않습니다.

에이전트는 작업당 하나의 Mac을 생성하며, 프로젝트가 지정한 [Xcode](#xcode)을 사용합니다. `create_sandbox`는 선택 가능한 Xcode 목록을 표시하고 에이전트에게 `.xcode-version`와 같은 프로젝트의 지정 버전을 읽으라고指示합니다. 각 명령 실행 전에 `tuist sandbox sync`를 실행합니다. Git이 무시하지 않는 파일(커밋 여부 무관)을 복사하며, 이후에는 변경된 파일만 복사합니다. 첫 번째 동기화 후 Mac의 리포지토리 루트에서 `mise install`를 실행하여 [프로젝트에 지정된 Tuist](#tuist-in-sandbox)가 계정의 캐시에 로그인된 상태로 준비됩니다. 이후 에이전트는 `tuist sandbox exec`로 `xcodebuild`와 같은 명령을 실행하고, `tuist sandbox cp`로 스크린샷이나 빌드된 앱과 같은 결과를 다시 복사한 후 작업이 완료되면 Mac을 삭제합니다. Mac은 마지막 명령 실행 후 10분 동안 실행 상태를 유지하므로 다음 명령은 즉시 시작됩니다. `tuist sandbox pause`를 사용하면 더 빨리 반환할 수 있습니다. 방치된 Mac은 일시 중지되며, 14일 동안 일시 중지된 후 삭제됩니다.

## Linux 및 macOS {#platforms}

**Linux** 샌드박스는 Ubuntu 24.04를 실행합니다:

- 2 vCPU, 4 GiB RAM (기본값)
- 4 vCPU, 8 GiB RAM
- 8 vCPU, 16 GiB RAM

**macOS** 샌드박스는 Apple 실리콘에서 Xcode와 함께 실행됩니다:

- 8 vCPU, 8 GiB RAM (기본값)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

### Xcode 선택하기 {#xcode}

각 macOS 샌드박스는 생성 시 선택한 하나의 Xcode를 실행합니다. 해당 Xcode용 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 프로필과 동일한 이미지를 부팅하므로, 에이전트는 CI와 동일한 툴체인 및 시뮬레이터로 빌드합니다. tuist.dev에서는 현재 다음과 같은 macOS 샌드박스 옵션을 제공합니다:

- `26.6` (기본값)
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

러너 프로필과 마찬가지로 정확한 버전을 사용하여 `xcode_version`(CLI에서는 `--xcode`)로 하나를 선택하세요:

| 위치 | 방법 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API 및 MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp용 Tuist Mac 플러그인 | `xcode`와 함께 `tuist_mac_start` |
| Amp orbs | Orb 타입 `macos-xcode-26-1-1` (<.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link> 참조) |
| Claude Code 및 Claude Managed Agents | 환경별 `xcode_version` 또는 Managed Agents 세션별 (참조: <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **버전을 지정하지 않으면** Mac은 기본값을 사용합니다.
- **Tuist가 제공하지 않는 버전은 거부되며**, 오류 메시지에 선택 가능한 버전 목록이 표시되어 현재 사용 가능한 버전을 확인할 수 있습니다.
- **Tuist는 리포지토리의 `.xcode-version`를 읽지 않습니다.** 사용자 또는 Mac을 요청하는 에이전트가 버전을 선택합니다. MCP 도구와 Tuist Mac 플러그인은 에이전트에게 프로젝트가 지정한 버전과 일치하도록 안내합니다.
- **샌드박스는 수명 동안 Xcode를 유지합니다.** 다른 Xcode로 빌드하려면 새 샌드박스를 생성하세요. `xcodebuild -version`는 Mac이 실행 중인 Xcode 버전을 보여줍니다.

## 보안 {#security}

- 각 샌드박스는 자체 가상 머신입니다. 샌드박스는 서로 간 또는 CI 작업과 파일 시스템, 메모리 또는 프로세스를 공유하지 않습니다.
- 샌드박스는 계정에 속하며, 통합 서비스를 제공하는 샌드박스를 포함하여 계정 구성원 누구나 사용하고 관리할 수 있습니다. 통합 연결은 관리자만 수행할 수 있습니다. 통합에서의 세션은 해당 통합이 연결된 계정의 샌드박스에만 접근합니다.
- Amp 제공자 토큰이나 Claude 환경 키와 같이 통합 연결을 위해 Tuist에 제공하는 자격 증명은 암호화되어 저장되며 다시 표시되지 않습니다.
- 샌드박스는 인터넷에 접근할 수 있습니다. 에이전트가 샌드박스에서 접근할 수 있는 내용은 CI 작업과 동일하게 취급하세요.
