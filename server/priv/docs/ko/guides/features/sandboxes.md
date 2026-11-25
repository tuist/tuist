---
{
  "title": "샌드박스",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 샌드박스는 Amp와 Claude 같은 코딩 에이전트를 위한 영구적인 Linux 및 macOS 가상 머신입니다. 각 에이전트 세션은 자체 머신을 할당받으며, 에이전트가 대기 상태일 때 일시 중지되고 파일이 그대로 유지된 상태로 다시 실행됩니다."
}
---
# 샌드박스 {#sandboxes}

> [!IMPORTANT]
> **초대 전용**
>
> Tuist 샌드박스(Linux 및 macOS)는 현재 용량 확장 단계로 초대 전용입니다. 계정 액세스를 요청하려면 [문의](mailto:contact@tuist.dev)하거나 [커뮤니티 Slack](https://slack.tuist.dev)에서 알려주세요. 샌드박스가 정식 출시되면 가격이 공개될 예정입니다.

샌드박스는 코딩 에이전트가 명령을 실행하고 파일을 편집하는 가상 머신입니다. 각 에이전트 세션은 자체 샌드박스를 사용하며, 세션 동안 체크아웃 상태, 빌드 산출물 및 설치된 도구를 유지합니다. 에이전트가 대기 상태가 되면 샌드박스가 일시 중지되고, 다음 메시지가 오면 중단된 지점부터 다시 시작됩니다.

샌드박스는 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>와 동일한 플릿에서 팀의 <.localized_link href="/guides/features/cache">캐시</.localized_link> 옆에 실행되므로, 에이전트의 빌드는 CI 및 로컬 머신과 동일한 캐시된 아티팩트를 사용할 수 있습니다.

다음 환경에서 샌드박스를 사용할 수 있습니다:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Tuist에서 Amp 워크스페이스의 orbs를 실행하거나, <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 플러그인</.localized_link>을 사용하여 모든 Amp 스레드에 Xcode 빌드를 위한 Mac을 제공합니다.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Tuist에서 Claude Managed Agents 세션과 Claude Code 클라우드 세션(claude.ai, 데스크톱 및 모바일 앱, 그리고 `claude --cloud`)을 실행합니다.
- **[Tuist CLI](#cli)**: 터미널에서 샌드박스를 생성하고 명령을 실행하거나, API를 통해 자체 도구에서 사용합니다.

## CLI로 시작하기 {#cli}

터미널에서 `tuist sandbox`를 사용하여 샌드박스를 생성하고 그 안에서 명령을 실행하세요.

### 1. 로그인 {#cli-log-in}

계정의 모든 구성원이 샌드박스를 생성하고 관리할 수 있습니다:

```bash
tuist auth login
```

### 2. 샌드박스 생성 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux의 경우 `--platform`를 생략하세요. 해당 [Xcode](#xcode)가 설치된 Mac을 위해 버전(예: `--xcode 26.1.1`)과 함께 `--xcode`를 전달하면 `--platform macos`가 자동으로 적용됩니다. 더 큰 [shape](#platforms)을 위해 `--vcpus`와 `--memory-gb`를 전달하고, Linux 샌드박스에 더 많은 [CPU](#guaranteed-cpu)를 보장받으려면 `--guaranteed-vcpus`를, 더 큰 디스크를 위해 `--workspace-gb`를 전달하세요. 샌드박스는 생성 시점과 각 재개 시점부터 2시간 동안 실행되며, 5분에서 하루 사이의 시간을 설정하려면 `--lifetime-minutes`를 전달하세요. 수명이 종료되면 실행 중인 명령이 취소되고 샌드박스는 일시 중지 및 아카이브되어 파일을 보존하므로, 잊혀진 샌드박스가 계정의 용량을 사용하지 않도록 합니다. 명령은 샌드박스가 실행되면 반환되며 ID를 포함한 세부 정보를 출력합니다. 현재 디렉토리의 Tuist 프로젝트 계정을 사용하며, 다른 계정을 선택하려면 `--account`를 전달하세요.

### 3. 명령 실행 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

명령은 샌드박스 내에서 `bash -l`로 실행되며, 일시 중지된 경우 먼저 재개됩니다. `tuist`는 실행 시간과 관계없이 출력을 스트리밍하고 명령의 상태로 종료되며, Ctrl-C를 누르면 샌드박스 내의 명령이 취소됩니다. 필요에 따라 `--cwd`, `--env NAME=VALUE` 및 `--timeout`(최대 6시간)를 전달하세요.

명령은 `tuist`와 분리되어 실행되므로 연결이 끊겨도 유지됩니다. 에이전트와 같이 시간 제한이 있는 도구 호출에 긴 빌드를 맞추려면 `--wait <seconds>`를 전달하세요. 시간 제한이 먼저 도달하면 `tuist`는 명령을 실행 상태로 둔 채 종료 코드 75로 종료하고, 중단된 지점에서 출력을 이어가고 명령의 상태로 종료하는 `tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …` 명령을 출력합니다.

### 일반 작업 {#cli-tasks}

| 작업 | 명령 |
| --- | --- |
| 샌드박스 목록 보기 | `tuist sandbox list` |
| 하나 보기 | `tuist sandbox show <id>` |
| 일시 중지 또는 재개 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 만료 후에도 계속 실행 | `tuist sandbox extend <id> --lifetime-minutes 240` |
| 로컬 Git 작업 트리의 파일을 미러링 | `tuist sandbox sync <id>` |
| 파일 복사(내보내기 또는 가져오기) | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 삭제 | `tuist sandbox delete <id> --yes` |
| 사용량 확인 | `tuist sandbox analytics` |

기계 판독 가능한 출력을 위해 `--json`를 추가하세요. 모든 옵션은 <.localized_link href="/cli/sandbox">CLI 참조</.localized_link>를 확인하세요. 코드에서 샌드박스를 제어하려면 `/api/accounts/{account_handle}/sandboxes` 아래의 [Tuist API](https://tuist.dev/api/docs)를 통해 동일한 작업을 수행하거나, 에이전트가 <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>를 통해 사용하도록 하세요.

대화형 로그인이 불가능한 도구(예: macOS 샌드박스에서 빌드하는 에이전트 플러그인)는 대신 `account:sandboxes:write` 범위를 가진 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>으로 인증할 수 있습니다. 이는 계정 구성원이 할 수 있는 작업(샌드박스 생성, 명령 실행, 일시 중지, 재개, 아카이브 및 삭제)을 수행할 수 있습니다. 통합 설정 및 통합을 제공하는 샌드박스에서의 명령 실행 권한은 계정 관리자에게만 남아 있습니다.

### 샌드박스 내부의 Tuist {#tuist-in-sandbox}

macOS 샌드박스에는 Tuist CLI가 포함되어 있습니다. 프로젝트가 mise(`mise.toml` 또는 `.tool-versions`)를 통해 Tuist 버전을 고정하면, `tuist`는 명령이 처음 필요할 때 설치된 해당 버전을 대신 실행합니다. `tuist sandbox exec`로 시작하는 모든 명령은 `PATH`의 맨 앞에 mise의 shim(`$HOME/.local/share/mise/shims`)이 위치하고 이미지의 Tuist가 마지막에 배치되므로, `tuist` 및 기타 mise 도구가 명령과 Xcode 빌드 단계(예: 스킴의 post-actions)에서 실행됩니다. 각 Mac에는 `/opt/tuist/agent-guide.md`에 코딩 에이전트를 위한 가이드가 포함되어 있으며, 이는 이미지(Xcode 및 시뮬레이터), 저장소 위치, 준비된 스냅샷 내용)에서 생성됩니다. Mac에서 실행되는 Claude Code, Codex 및 Amp는 지침 파일에서 이를 찾습니다.

`tuist sandbox exec`로 시작하는 모든 명령은 Tuist runner와 동일한 환경을 얻으므로, 샌드박스 내의 빌드는 자격 증명을 전달하지 않아도 계정의 <.localized_link href="/guides/features/cache">캐시</.localized_link>를 사용합니다:

- `TUIST_URL` 및 macOS와 같이 샌드박스 호스트가 접근할 수 있는 경우 같은 랙의 캐시에 대한 `TUIST_CACHE_ENDPOINT`.
- 해당 명령을 위한 단기 신원 토큰인 `TUIST_OIDC_TOKEN`. Tuist CLI 4.218.0 이상은 자동으로 이를 사용하여 로그인하며, 4.215.0~4.217.x 버전에서는 동일한 명령 내에서 먼저 `tuist auth login`를 실행하세요.

토큰은 각 명령마다 발급되며 해당 명령이 실행되는 동안에만 Tuist 토큰으로 교환할 수 있으므로, 샌드박스는 장기 자격 증명을 보유하지 않습니다. 이 토큰은 명령을 시작한 사람이나 토큰이 캐시로 수행할 수 있는 작업 이상의 권한을 부여하지 않습니다. 캐시 토큰으로 쓰기만 가능한 계정 구성원은 읽기 액세스를 얻으며, 샌드박스가 캐시를 사용하려면 계정 토큰에 `ci`과 같은 캐시 범위가 `account:sandboxes:write`와 함께 필요합니다. `--env`로 전달한 변수는 우선순위를 가집니다.

## 코딩 에이전트에서 Mac으로 빌드하기 {#coding-agents}

Linux에서 실행되는 코딩 에이전트(예: 클라우드 에이전트 세션)는 파일을 편집하는 동안 macOS 샌드박스에서 Apple 플랫폼 코드를 빌드, 테스트 및 실행할 수 있습니다. Amp에서는 <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 플러그인</.localized_link>을 설치하세요. Claude Code 또는 Cursor와 같은 다른 에이전트의 경우:

1. 에이전트를 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 서버</.localized_link>에 연결하세요. `create_sandbox` 도구는 에이전트에게 Mac을 제어하는 방법을 알려줍니다.
2. 에이전트가 실행되는 환경에 Tuist CLI를 설치하세요. 예를 들어 환경 설정 스크립트에서 `mise use -g tuist@latest` 또는 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`(ARM의 경우 `tuist-linux-aarch64`)를 사용합니다.
3. CLI를 인증하세요. MCP 서버의 로그인 상태는 CLI로 이어지지 않으므로, 계정 구성원으로 `tuist auth login`를 실행하거나 `TUIST_TOKEN`를 `account:sandboxes:write` 범위를 가진 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>으로 설정하세요.
4. 환경에서 네트워크 접근을 제한하는 경우 `tuist.dev`를 허용하세요. CLI는 이를 통해 Mac으로 파일을 업로드하므로 다른 도메인은 필요하지 않습니다.
5. 선택적으로 에이전트가 매번 묻지 않고 Mac을 생성하고 삭제하도록 허용할 수 있습니다. 에이전트는 Mac이 계정 한도에 포함되므로 `create_sandbox` 호출 전에, 그리고 작업이 취소될 수 없으므로 `delete_sandbox` 전에 확인을 요청합니다. Claude Code에서는 MCP 서버를 등록한 이름(여기서는 `tuist`)을 사용하여 `.claude/settings.json`에서 둘 다 허용하세요:

   ```json
   {
     "permissions": {
       "allow": ["mcp__tuist__create_sandbox", "mcp__tuist__delete_sandbox"]
     }
   }
   ```

에이전트가 설정을 수행하도록 하려면 다음 프롬프트를 제공하세요:

```text
Set up this environment so you can build and test this project on a Tuist macOS sandbox.

Read https://tuist.dev/en/docs/guides/features/sandboxes#coding-agents and follow its "Build on a Mac from a coding agent" section. It's the current Tuist guide for this, so prefer it over anything you remember about Tuist.

You're done when you have created a Mac with create_sandbox, synced this repository to it with tuist sandbox sync, run the project's build there with tuist sandbox exec, and deleted the Mac.

Ask me before anything that needs my login or approval, such as tuist auth login. If a step fails or is blocked, stop and tell me which step you reached and the exact error, without secrets.
```

에이전트는 프로젝트가 지정한 [Xcode](#xcode)로 작업당 하나의 Mac을 생성합니다. `create_sandbox`는 선택 가능한 Xcode 목록을 제공하고 에이전트에게 `.xcode-version`와 같은 프로젝트의 지정 버전을 읽으라고 지시합니다. 각 명령 전에 `tuist sandbox sync`를 실행합니다. Git이 무시하지 않는 파일(커밋 여부 무관)을 복사하며, 이후에는 변경된 파일만 복사합니다. Mac에는 이미 [Tuist](#tuist-in-sandbox)(프로젝트가 버전을 지정한 경우 해당 버전)가 설치되어 있고 계정의 캐시에 로그인되어 있으며, 에이전트는 Mac의 가이드를 한 번 읽습니다. 그런 다음 에이전트는 `tuist sandbox exec`을 사용하여 `xcodebuild`과 같은 명령을 실행하고, `tuist sandbox cp`을 사용하여 스크린샷이나 빌드된 앱과 같은 결과를 다시 복사하며, 작업이 완료되면 Mac을 삭제합니다. Mac은 마지막 명령 후 10분 동안 실행 상태를 유지하므로 다음 명령이 즉시 시작됩니다. `tuist sandbox pause`를 사용하면 더 빨리 반환됩니다. 남겨진 Mac은 일시 중지되고, 2시간의 수명이 끝나면 아카이브되며, 14일 후에 삭제됩니다. 에이전트는 긴 빌드 전에 수명을 연장합니다.

## Linux 및 macOS {#platforms}

**Linux** 샌드박스는 Ubuntu 24.04를 실행합니다. 모든 Linux 샌드박스는 16개의 vCPU를 가지며 실행 중인 머신의 유휴 코어로 버스트하므로, 그 형태(shape)가 메모리를 결정합니다:

- 2 GiB RAM (`--vcpus 1 --memory-gb 2`)
- 4 GiB RAM (`--vcpus 2 --memory-gb 4`, 기본값)
- 8 GiB RAM (`--vcpus 4 --memory-gb 8`)
- 16 GiB RAM (`--vcpus 8 --memory-gb 16`)
- 32 GiB RAM (`--vcpus 16 --memory-gb 32`)
- 44 GiB RAM (`--vcpus 16 --memory-gb 44`)

**macOS** 샌드박스는 Apple 실리콘에서 Xcode와 함께 실행됩니다:

- 8 vCPU, 8 GiB RAM (기본값)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

### 보장된 CPU {#guaranteed-cpu}

Linux 샌드박스는 메모리 GiB당 vCPU의 1/4(예: 8 GiB당 2 vCPU)를 보장받으며, 최대 16 vCPU까지 머신의 유휴 코어를 최대한 사용합니다. 이는 주로 대기하다가 버스트로 빌드하는 에이전트에 적합합니다. 바쁜 머신에서도 빌드에 더 안정적인 CPU가 필요한 경우, 샌드박스 생성 시 1, 2, 4 또는 8 vCPU를 보장하도록 설정하세요. 이는 메모리 보장값보다 큰 값을 적용받습니다:

| 위치 | 방법 |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API 및 MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **보장값은 상한이 아닌 하한입니다.** 4개의 vCPU를 보장받는 샌드박스도 코어가 유휴 상태일 때는 16개로 버스트합니다. 경쟁 상태에서는 각 샌드박스가 보장값에 비례하여 CPU를 할당받습니다.
- **최소 사용량으로 청구됩니다.** 실행 중인 샌드박스는 사용한 CPU만큼 청구되지만, 보장값 미만으로는 청구되지 않습니다.
- **샌드박스는 수명 동안 보장값을 유지합니다.** 변경하려면 새 샌드박스를 생성하세요.
- **macOS 샌드박스는 항상 전체 형태(shape)를 가지므로** 별도 보장을 받지 않습니다.

### Xcode 선택하기 {#xcode}

각 macOS 샌드박스는 생성 시 선택한 하나의 Xcode를 실행합니다. 해당 Xcode에 대한 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 프로필과 동일한 이미지를 부팅하므로, 에이전트는 CI와 동일한 툴체인 및 시뮬레이터로 빌드합니다. tuist.dev에서 macOS 샌드박스는 현재 다음을 제공합니다:

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
| Amp orbs | Orb 유형 `macos-xcode-26-1-1` (<.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link> 참조) |
| Claude Code 및 Claude Managed Agents | 환경의 `xcode_version` 또는 Managed Agents 세션별 (참조: <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **버전을 지정하지 않으면** Mac은 기본값을 사용합니다.
- **Tuist에서 제공하지 않는 버전은 거부되며**, 오류 메시지에 선택 가능한 버전 목록이 표시되어 현재 사용 가능한 버전을 확인할 수 있습니다.
- **Tuist는 저장소의 `.xcode-version`를 읽지 않습니다.** 여러분이나 Mac을 요청하는 에이전트가 버전을 선택해야 합니다. MCP 도구와 Tuist Mac 플러그인은 에이전트에게 프로젝트가 고정(pin)한 버전과 일치하도록 안내합니다.
- **샌드박스는 수명 동안 Xcode를 유지합니다.** 다른 Xcode로 빌드하려면 새 샌드박스를 생성하세요. `xcodebuild -version`는 Mac이 실행 중인 Xcode 버전을 보여줍니다.

## 보안 {#security}

- 각 샌드박스는 독립된 가상 머신입니다. 샌드박스 간 또는 CI 작업과 파일 시스템, 메모리 또는 프로세스를 공유하지 않습니다.
- 샌드박스는 계정에 속하며, 계정 구성원은 누구나 이를 사용하고 관리할 수 있습니다. Amp orb나 Claude Code 세션과 같은 통합 서비스를 제공하는 샌드박스는 해당 세션의 작업 내용과 자격 증명을 보유합니다. 구성원은 이를 확인, 일시 중지, 재개, 아카이브 및 삭제할 수 있지만, 명령 실행이나 파일 업로드는 관리자만 가능합니다. 통합 연결은 관리자만 수행할 수 있습니다. 통합 서비스의 세션은 해당 통합이 연결된 계정의 샌드박스에만 접근할 수 있습니다.
- Amp 제공자 토큰이나 Claude 환경 키와 같이 통합 연결을 위해 Tuist에 제공하는 자격 증명은 암호화되어 저장되며 다시 표시되지 않습니다.
- 샌드박스는 인터넷에 접근할 수 있습니다. 에이전트가 샌드박스에서 접근할 수 있는 내용은 CI 작업과 동일한 방식으로 취급하세요.
