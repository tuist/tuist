---
{
  "title": "샌드박스",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 샌드박스는 Amp와 Claude 같은 코딩 에이전트를 위한 영구적인 Linux 및 macOS 가상 머신입니다. 각 에이전트 세션은 고유한 머신을 할당받으며, 에이전트가 대기 상태일 때 일시 중지되고 파일이 그대로 유지된 상태로 다시 시작됩니다."
}
---
# 샌드박스 {#sandboxes}

> [!IMPORTANT]
> **초대 전용**
>
> Tuist 샌드박스(Linux 및 macOS)는 현재 용량을 확장하는 동안 초대 전용으로 제공됩니다. 계정에 대한 액세스를 요청하려면 [문의하기](mailto:contact@tuist.dev) 또는 [커뮤니티 Slack](https://slack.tuist.dev)에서 메시지를 보내주세요. 샌드박스가 일반 공개될 때 가격이 발표될 예정입니다.

샌드박스는 코딩 에이전트가 명령을 실행하고 파일을 편집하는 가상 머신입니다. 각 에이전트 세션은 자체 샌드박스를 가지며, 세션이 지속되는 동안 체크아웃, 빌드 산출물 및 설치된 도구를 유지합니다. 에이전트가 대기 상태가 되면 샌드박스가 일시 중지되며, 다음 메시지가 도착하면 중단된 지점부터 다시 시작됩니다.

샌드박스는 팀의 <.localized_link href="/guides/features/cache">캐시</.localized_link> 옆에 있는 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>와 동일한 플릿에서 실행되므로, 에이전트의 빌드는 CI 및 로컬 머신과 동일한 캐시된 아티팩트를 사용할 수 있습니다.

다음에서 샌드박스를 사용할 수 있습니다:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Tuist에서 Amp 워크스페이스의 orbs를 실행합니다.
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

Linux의 경우 `--platform`를 생략하세요. 더 큰 [셰이프](#platforms)를 위해 `--vcpus`와 함께 `--memory-gb`를 전달하고, 더 큰 디스크를 위해 `--workspace-gb`를 전달하세요. 명령은 샌드박스가 실행되면 반환되며 ID를 포함한 세부 정보를 출력합니다. 현재 디렉터리의 Tuist 프로젝트 계정을 사용하며, 다른 계정을 선택하려면 `--account`를 전달하세요.

### 3. 명령 실행 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

명령은 샌드박스에서 `bash -lc`로 실행되며, 일시 중지된 경우 먼저 재개되고 `tuist`는 명령의 상태로 종료됩니다.

### 일반 작업 {#cli-tasks}

| 작업 | 명령 |
| --- | --- |
| 샌드박스 목록 | `tuist sandbox list` |
| 하나 보기 | `tuist sandbox show <id>` |
| 일시 중지 또는 재개 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 삭제 | `tuist sandbox delete <id> --yes` |
| 사용량 보기 | `tuist sandbox analytics` |

기계 판독 가능한 출력을 위해 `--json`를 추가하세요. 모든 옵션은 <.localized_link href="/cli/sandbox">CLI 참조</.localized_link>를 확인하세요. 코드에서 샌드박스를 제어하려면 `/api/accounts/{account_handle}/sandboxes` 아래의 [Tuist API](https://tuist.dev/api/docs)를 통해 동일한 작업을 사용하거나, 에이전트가 <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>를 통해 사용하도록 하세요.

## Linux 및 macOS {#platforms}

**Linux** 샌드박스는 Ubuntu 24.04를 실행합니다:

- 2 vCPU, 4 GiB RAM(기본)
- 4 vCPU, 8 GiB RAM
- 8 vCPU, 16 GiB RAM

**macOS** 샌드박스는 Apple 실리콘에서 Xcode와 함께 실행됩니다:

- 8 vCPU, 8 GiB RAM(기본)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

## 보안 {#security}

- 각 샌드박스는 자체 가상 머신입니다. 샌드박스는 서로 또는 CI 작업과 파일 시스템, 메모리 또는 프로세스를 공유하지 않습니다.
- 샌드박스는 계정에 속하며 해당 계정의 관리자만 관리할 수 있습니다. 통합에서의 세션은 통합이 연결된 계정의 샌드박스에만 접근할 수 있습니다.
- 통합 연결을 위해 Tuist에 제공하는 자격 증명(Amp 제공자 토큰 또는 Claude 환경 키 등)은 암호화되어 저장되며 다시 표시되지 않습니다.
- 샌드박스는 인터넷에 접근할 수 있습니다. 에이전트가 샌드박스에서 접근할 수 있는 내용은 CI 작업과 동일하게 취급하세요.
