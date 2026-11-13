---
{
  "title": "샌드박스",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 샌드박스는 Amp와 Claude 같은 코딩 에이전트를 위한 영구적인 Linux 및 macOS 가상 머신입니다. 각 에이전트 세션은 자체 머신을 할당받으며, 에이전트가 대기 상태일 때 일시 중지되고 파일이 그대로 유지된 상태로 재개됩니다."
}
---
# 샌드박스 {#sandboxes}

> [!IMPORTANT]
> **초대 전용**
>
> Tuist 샌드박스(Linux 및 macOS)는 현재 용량을 확장하는 동안 초대 전용으로 제공됩니다. 계정에 대한 액세스를 요청하려면 [문의](mailto:contact@tuist.dev)하거나 [커뮤니티 Slack](https://slack.tuist.dev)에서 메시지를 보내세요. 샌드박스가 일반 공개되면 가격이 발표될 예정입니다.

샌드박스는 코딩 에이전트가 명령을 실행하고 파일을 편집하는 가상 머신입니다. 각 에이전트 세션은 자체 샌드박스를 가지며, 세션이 지속되는 동안 체크아웃, 빌드 산출물 및 설치된 도구를 유지합니다. 에이전트가 대기 상태가 되면 샌드박스가 일시 중지되며, 다음 메시지가 도착하면 중단된 지점부터 다시 시작됩니다.

샌드박스는 팀의 <.localized_link href="/guides/features/cache">캐시</.localized_link> 옆에 있는 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>와 동일한 플릿에서 실행되므로, 에이전트의 빌드는 CI 및 로컬 머신과 동일한 캐시된 아티팩트를 사용할 수 있습니다.

다음에서 샌드박스를 사용할 수 있습니다:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Tuist에서 Amp 워크스페이스의 orbs를 실행하거나, <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 플러그인</.localized_link>을 사용하여 모든 Amp 스레드에 Xcode 빌드를 위한 Mac을 제공합니다.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Tuist에서 Claude Managed Agents 세션과 Claude Code 클라우드 세션(claude.ai, 데스크톱 및 모바일 앱, 그리고 `claude --cloud`)을 실행합니다.
- **[Tuist CLI](#cli)**: 터미널에서 샌드박스를 생성하고 명령을 실행하거나, API를 통해 자체 도구에서 실행합니다.

## CLI로 시작하기 {#cli}

`tuist sandbox`를 사용하여 터미널에서 샌드박스를 생성하고 그 안에서 명령을 실행하세요.

### 1. 로그인 {#cli-log-in}

샌드박스를 관리하려면 계정 관리자가 필요합니다:

```bash
tuist auth login
```

### 2. 샌드박스 생성 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux의 경우 `--platform`를 생략하세요. 더 큰 [shape](#platforms)를 위해 `--vcpus`와 함께 `--memory-gb`를 전달하고, 더 큰 디스크를 위해 `--workspace-gb`를 전달하세요. 명령은 샌드박스가 실행되면 반환되며 ID를 포함한 세부 정보를 출력합니다. 현재 디렉터리의 Tuist 프로젝트 계정을 사용하며, 다른 계정을 선택하려면 `--account`를 전달하세요.

### 3. 명령 실행 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

명령은 샌드박스에서 `bash -l`로 실행되며, 일시 중지된 경우 먼저 재개됩니다. `tuist`는 실행 시간과 상관없이 출력을 스트리밍하고 명령의 상태로 종료됩니다. Ctrl-C로 샌드박스 내에서 취소할 수 있습니다. 필요에 따라 `--cwd`, `--env NAME=VALUE` 및 `--timeout`(최대 6시간)를 전달하세요.

### 일반 작업 {#cli-tasks}

| 작업 | 명령 |
| --- | --- |
| 샌드박스 목록 | `tuist sandbox list` |
| 하나 보기 | `tuist sandbox show <id>` |
| 일시 중지 또는 재개 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 로컬 Git 작업 트리의 파일을 미러링 | `tuist sandbox sync <id>` |
| 파일 복사(내보내기 또는 가져오기) | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 삭제 | `tuist sandbox delete <id> --yes` |
| 사용량 보기 | `tuist sandbox analytics` |

기계 판독 가능 출력을 위해 `--json`를 추가하세요. 모든 옵션은 <.localized_link href="/cli/sandbox">CLI 참조</.localized_link>를 확인하세요. 코드에서 샌드박스를 제어하려면 `/api/accounts/{account_handle}/sandboxes` 아래의 [Tuist API](https://tuist.dev/api/docs)를 통해 동일한 작업을 수행하거나, 에이전트가 <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>를 통해 사용하도록 하세요.

macOS 샌드박스에서 빌드하는 에이전트 플러그인과 같이 상호작용적으로 로그인할 수 없는 도구는 대신 `account:sandboxes:write` 범위가 포함된 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>으로 인증할 수 있습니다. 이는 계정 멤버처럼 샌드박스를 생성하고, 명령을 실행하며, 일시 중지, 재개 및 삭제할 수 있습니다. Amp 또는 Claude 통합, 분석 및 통합 설정을 제공하는 샌드박스는 계정 관리자와 함께 유지됩니다.

## 코딩 에이전트에서 Mac으로 빌드하기 {#coding-agents}

클라우드 에이전트 세션과 같이 Linux에서 실행되는 코딩 에이전트는 파일을 편집하는 동안 macOS 샌드박스에서 Apple 플랫폼 코드를 빌드, 테스트 및 실행할 수 있습니다. Amp에서는 <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 플러그인</.localized_link>을 설치하세요. Claude Code 또는 Cursor와 같은 다른 에이전트의 경우:

1. 에이전트를 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 서버</.localized_link>에 연결하세요. `create_sandbox` 도구가 에이전트에게 Mac을 제어하는 방법을 알려줍니다.
2. 에이전트가 실행되는 환경에 Tuist CLI를 설치하세요. 예를 들어 환경의 설정 스크립트에서: `mise use -g tuist@latest`, 또는 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`(ARM의 경우 `tuist-linux-aarch64`).
3. CLI를 인증하세요. MCP 서버의 로그인은 여기에 적용되지 않으므로, 계정 멤버로 `tuist auth login`를 실행하거나 `account:sandboxes:write` 범위가 포함된 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>으로 `TUIST_TOKEN`를 설정하세요.
4. 환경이 네트워크 액세스를 제한하는 경우 `tuist.dev`를 허용하세요. CLI는 이를 통해 Mac으로 파일을 업로드하므로 다른 도메인이 필요하지 않습니다.

에이전트는 작업당 하나의 Mac을 생성하며, 각 명령 전에 `tuist sandbox sync`를 실행합니다. Git이 무시하지 않는 파일(커밋 여부 무관)을 복사한 후 변경된 파일만 복사합니다. 이후 에이전트는 `tuist sandbox exec`를 사용하여 `xcodebuild`와 같은 명령을 실행하고, `tuist sandbox cp`를 사용하여 스크린샷이나 빌드된 앱과 같은 결과를 다시 복사한 후 작업이 완료되면 Mac을 삭제합니다. Mac은 마지막 명령 후 10분 동안 실행 상태를 유지하므로 다음 명령이 즉시 시작됩니다. `tuist sandbox pause`를 사용하면 더 빨리 반환할 수 있습니다. 방치된 Mac은 일시 중지되며 14일 동안 일시 중지된 후 삭제됩니다.

## Linux 및 macOS {#platforms}

**Linux** 샌드박스는 Ubuntu 24.04를 실행합니다:

- 2 vCPU, 4 GiB RAM(기본)
- 4 vCPU, 8 GiB RAM
- 8 vCPU, 16 GiB RAM

**macOS** 샌드박스는 Apple silicon에서 Xcode와 함께 실행됩니다:

- 8 vCPU, 8 GiB RAM(기본)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

## 보안 {#security}

- 각 샌드박스는 자체 가상 머신입니다. 샌드박스 간 또는 CI 작업과 파일 시스템, 메모리 또는 프로세스를 공유하지 않습니다.
- 샌드박스는 계정에 속하며 해당 관리자만 관리할 수 있습니다. 통합 세션은 통합이 연결된 계정의 샌드박스에만 접근합니다.
- Amp 제공자 토큰이나 Claude 환경 키와 같이 통합 연결을 위해 Tuist에 제공하는 자격 증명은 암호화되어 저장되며 다시 표시되지 않습니다.
- 샌드박스는 인터넷에 접근할 수 있습니다. 에이전트가 샌드박스에서 접근할 수 있는 내용은 CI 작업과 동일하게 취급하세요.
