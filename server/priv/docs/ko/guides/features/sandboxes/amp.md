---
{
  "title": "Amp",
  "titleTemplate": ":title · 샌드박스 · 기능 · 가이드 · Tuist",
  "description": "Linux 또는 macOS에서 Tuist 샌드박스로 Amp 워크스페이스의 Orb를 실행하거나, Tuist Mac 플러그인을 사용해 모든 Amp 스레드에 Xcode 빌드를 위한 Mac 환경을 제공하세요."
}
---
# Amp {#amp}

> [!IMPORTANT]
> **초대 전용**
>
> Tuist 샌드박스(Linux 및 macOS)는 현재 초대 전용입니다. 계정 액세스를 요청하려면 [문의하기](mailto:contact@tuist.dev) 또는 [커뮤니티 Slack](https://slack.tuist.dev)에서 저희에게 연락하세요.

[Amp](https://ampcode.com)는 각 스레드의 도구를 해당 스레드의 리포지토리가 체크아웃된 머신인 [orb](https://ampcode.com/docs/orbs)에서 실행합니다. Tuist는 Amp 워크스페이스의 [셀프 호스트 orb 제공자](https://ampcode.com/docs/orbs/self-hosted)가 될 수 있습니다. 이를 선택한 모든 스레드는 Linux 또는 macOS에서 자체 Tuist <.localized_link href="/guides/features/sandboxes">샌드박스</.localized_link>에서 실행됩니다. 직접 무언가를 실행하거나 호스팅할 필요가 없습니다.

스레드를 현재 orb에 유지하고 Mac에서 Apple 플랫폼 코드만 빌드, 테스트 및 실행하려면 대신 [Tuist Mac 플러그인](#remote-mac)을 사용하세요.

## Amp 연결 {#connect}

Amp 워크스페이스와 Tuist 계정 모두의 관리자여야 합니다.

1. Amp에서 워크스페이스의 **Settings → Orbs**를 열고 **Add Orb Provider**를 클릭한 후 이름을 지정합니다(예: `tuist`). 멤버는 이 이름으로 제공자를 선택합니다. `aop_live_…` 토큰을 복사하세요. Amp는 이를 한 번만 표시합니다.
2. Amp의 제공자 **Edit** 대화 상자에서 제공하려는 **Orb types**를 추가하고 기본값을 선택하세요. Linux 유형은 [Amp 자체 orbs](https://ampcode.com/docs/orbs/sizes-and-costs)의 메모리와 일치합니다. 각각은 메모리 GiB당 vCPU의 1/4을 보장받으며, 머신에 유휴 코어가 있을 때 최대 16 vCPU로 버스트됩니다(<.localized_link href="/guides/features/sandboxes#guaranteed-cpu">Guaranteed CPU</.localized_link> 참조):

   | 유형 | 구성 |
   | --- | --- |
   | `linux` | Linux, RAM 8 GiB, 보장 vCPU 2개 |
   | `linux-tiny` | Linux, RAM 2 GiB, 보장 vCPU 0.5개 |
   | `linux-small` | Linux, RAM 4 GiB, 보장 vCPU 1개 |
   | `linux-medium` | `linux`와 동일 |
   | `linux-large` | Linux, RAM 16 GiB, 보장 vCPU 4개 |
   | `linux-xxlarge` | Linux, RAM 32 GiB, 보장 vCPU 8개 |
   | `linux-3xlarge` | Linux, RAM 44 GiB, 보장 vCPU 11개 |
   | `macos` | 기본 Xcode가 있는 macOS, vCPU 8개, RAM 8 GiB |
   | `macos-xcode-<version>` | 해당 [Xcode](#xcode)가 있는 macOS, vCPU 8개, RAM 8 GiB |

   Linux 유형은 워크스페이스가 10 GB이고, macOS 유형은 30 GB입니다.

3. Tuist에서 계정의 대시보드에서 **Sandboxes**를 열고 Amp 카드의 **Connect**를 클릭한 후 토큰을 붙여넣으세요.

Tuist가 제공자를 서비스하면 카드에 **Connected**가 표시됩니다. 하나의 Tuist 계정은 하나의 제공자를 서비스합니다. Amp에서 제공자를 사용할 수 있는 사람은 연결된 Tuist 계정에서 orbs를 실행하며 해당 계정에 요금이 청구됩니다. 중지를 원하면 카드에서 **Disconnect**를 클릭하거나 Amp에서 제공자를 비활성화하세요.

## 스레드 시작 {#start-a-thread}

Amp의 새 스레드 작성기에서 **Orb**를 클릭하고 **Self-Hosted** 아래에서 Tuist 제공자를 선택한 후 유형을 선택하세요. 예를 들어 `linux-small`는 `linux`보다 적은 리소스가 필요한 리포지토리에 적합하고, `linux-large`는 더 많은 리소스가 필요한 리포지토리에 적합합니다. Amp CLI에서:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

스레드는 평생 동안 orb 유형을 유지합니다. 유형이 없으면 제공자의 기본값을 사용합니다. 모든 새 스레드에 동일한 유형을 사용하려면 Amp의 **Settings → Orbs**에서 **Default Orb** 아래에서 제공자와 유형을 선택하세요.

### Xcode 선택 {#xcode}

`macos`는 기본 <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>를 실행합니다. 다른 버전을 사용하려면 점 대신 대시를 사용하여 이름이 지정된 orb 유형을 추가하세요. 예를 들어 `macos-xcode-26-1-1`는 Xcode 26.1.1을 실행하고, `macos-xcode-27-0`는 Xcode 27.0을 실행합니다. 리포지토리가 고정하는 각 Xcode에 대해 하나씩 추가하고 다른 유형과 마찬가지로 스레드별로 선택하세요:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos-xcode-26-1-1
```

Tuist가 제공하지 않는 Xcode에 대한 유형은 새 orb가 시작될 때 실패합니다. Tuist가 해당 Xcode 제공을 중단한 후에도 이미 해당 유형으로 시작된 orb는 계속 재개됩니다.

Amp는 모든 orb와 마찬가지로 리포지토리를 복제하고 `.agents/setup` 스크립트를 실행하며 Git 자격 증명을 설정합니다. 각 orb는 계정의 Tuist <.localized_link href="/guides/features/cache">캐시</.localized_link>도 읽을 수 있습니다.

## 일시 중지 및 보존 {#retention}

스레드가 유휴 상태가 되면 Amp는 해당 orb를 일시 중지합니다. 다음 메시지는 파일이 그대로 유지된 상태로 이를 재개합니다.

- **Linux:** 실행 중인 프로세스는 일시 중지를 견딥니다. 오랫동안 일시 중지된 orb는 아카이브 저장소로 이동되며 다음 메시지에서 프로세스 없이 복구됩니다. Linux orb는 Amp가 스레드의 orb를 삭제할 때까지 파일을 유지합니다.
- **macOS:** 7일 동안 일시 중지되거나 오류 상태인 orb는 삭제됩니다. 스레드의 다음 메시지는 새로운 orb를 시작하고 Amp는 `.agents/setup`를 다시 실행합니다. 머신의 첫 번째 macOS orb는 Amp CLI를 설치하므로 시작하는 데 최대 2분이 걸릴 수 있습니다.

Amp가 일시 중지하지 않고 유휴 상태를 유지하는 orb(예: 일시 중지 신호가 도착하지 않은 경우)는 CPU 사용량이 거의 없는 상태에서 10분 후에 일시 중지됩니다.

## 모든 Amp 스레드에서 Mac 사용 {#remote-mac}

Tuist Mac 플러그인은 스레드가 현재 위치(예: Amp의 자체 Linux orb 중 하나)에서 계속 실행되는 동안 Amp 스레드에 Xcode, iOS 시뮬레이터 및 Homebrew가 포함된 macOS 샌드박스를 제공합니다. Amp에 작업을 요청하면 필요할 때 Mac을 시작합니다:

> 설정 화면에 다크 모드 토글을 추가하고, iOS 시뮬레이터에서 앱을 실행한 후 스크린샷을 보여주세요.

Amp는 코드가 실행되는 위치에서 편집을 계속합니다. Mac에서 각 명령을 실행하기 전에 플러그인은 `tuist sandbox sync`를 실행하여 Git이 무시하지 않는 파일(커밋 여부 무관)을 복사한 후 변경된 파일만 복사합니다. Mac이 생성한 빌드 산출물 및 기타 무시된 파일은 그대로 유지되므로 빌드가 증분 상태로 유지됩니다. 플러그인은 이러한 도구와 Amp에게 언제 어떻게 사용할지 알려주는 `remote-mac` 스킬을 추가합니다:

| 도구 | 작동 방식 |
| --- | --- |
| `tuist_mac_start` | 스레드의 Mac을 생성하거나 재사용하고 동기화합니다 |
| `tuist_mac_shell` | 동기화한 후 Mac에서 명령을 실행합니다 |
| `tuist_mac_screenshot` | 스레드에서 시뮬레이터 또는 화면을 표시합니다 |
| `tuist_mac_download` | 빌드된 `.app`과 같은 파일을 다시 복사합니다 |
| `tuist_mac_stop` | 스레드의 Mac을 삭제합니다 |

Mac에는 Tuist CLI가 있으며, mise를 통해 특정 버전을 고정하면 프로젝트의 해당 버전을 실행합니다. `tuist_mac_shell`는 mise의 shim을 `PATH`의 맨 앞에 배치합니다. Mac의 각 명령은 Tuist 4.218.0 이상에서 자체적으로 <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">계정의 캐시에 로그인</.localized_link>됩니다. 4.215.0~4.217.x 버전에서는 Amp가 먼저 `tuist auth login`를 실행합니다.

스레드는 하나의 Mac을 사용합니다. Amp는 `tuist_mac_start`에 리포지토리가 고정한 <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>(예: `.xcode-version`에 지정)를 전달하거나, 직접 요청할 수 있습니다("Xcode 26.1.1 사용"). 지정하지 않으면 Mac은 기본 Xcode를 실행합니다. Mac은 Xcode를 유지하므로 변경하려면 중지하고 다른 것을 시작해야 합니다. Tuist는 유휴 상태일 때 이를 일시 중지하고 다음 명령이 재개합니다. 작업이 완료되면 Amp가 이를 삭제하며, 남겨진 Mac은 14일 동안 일시 중지된 후 삭제됩니다. Mac은 다른 샌드박스와 마찬가지로 Tuist 계정에 포함됩니다.

### 설정하기 {#remote-mac-setup}

1. **플러그인을 설치합니다.** 단일 파일인 [`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts)입니다. Amp 워크스페이스의 모든 사용자가 사용할 수 있도록 하려면 워크스페이스 관리자가 스레드에서 Amp에 요청합니다:

   > https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts을 우리 워크스페이스 플러그인에 추가하세요.

   Amp는 이를 워크스페이스의 [플러그인 리포지토리](https://ampcode.com/docs/customize/global-plugins-and-skills)에 커밋하고 푸시하기 전에 확인을 요청합니다. 본인만 설치하려면 대신 "내 개인 플러그인"을 요청하거나, 리포지토리에서 해당 파일만 사용하도록 `.amp/plugins/tuist-mac.ts`로 저장하세요. 플러그인은 복사본이므로 업데이트하려면 동일한 URL에서 최신 버전으로 교체하도록 Amp에 요청하세요.
2. **Tuist CLI를 설치합니다**. Amp가 실행되는 위치입니다. orb에서는 리포지토리의 [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) 스크립트에 추가합니다(예: `mise use -g tuist@latest` 또는 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`).
3. **CLI가 계정의 샌드박스를 사용하도록 허용합니다.** orb에서는 <.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link>에 설명된 대로 Amp 워크스페이스를 Tuist 계정에 연결합니다. 그러면 orb가 자동으로 로그인하여 샌드박스에 액세스합니다. Linux 머신의 Amp CLI 등 다른 위치에서는 계정 구성원으로서 `tuist auth login`를 실행하거나, `TUIST_MAC_TOKEN`를 `account:sandboxes:write` 범위가 포함된 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>으로 설정하고, Mac이 캐시를 사용하도록 `ci`도 추가합니다. 플러그인은 `TUIST_TOKEN` 대신 `TUIST_MAC_TOKEN`를 CLI에 전달하므로, orb에 해당 범위가 없는 `TUIST_TOKEN`가 이미 있더라도 이를 설정하세요.
4. 리포지토리에 `project = "<account>/<project>"`가 포함된 `tuist.toml`가 없으면 **사용할 계정을 지정합니다**. Linux에서는 CLI가 `Tuist.swift`에서 계정을 읽을 수 없습니다. Amp 프로젝트의 환경 변수에서 `TUIST_MAC_ACCOUNT`를 계정 핸들로 설정하세요. 설정하지 않으면 Amp는 `Tuist.swift`의 `fullHandle`에서 `tuist_mac_start`로 계정을 전달합니다.

CLI는 `tuist.dev`를 통해서만 Mac에 도달하므로 네트워크 액세스를 제한하는 환경에서는 해당 도메인만 허용해야 합니다. `PATH`에 없는 CLI를 사용하려면 `TUIST_MAC_CLI`를 해당 경로로 설정하세요.

Claude Code나 Cursor처럼 Amp 플러그인을 지원하지 않는 에이전트는 <.localized_link href="/guides/features/sandboxes#coding-agents">코딩 에이전트에서 Mac으로 빌드</.localized_link>에 설명된 대로 Tuist MCP 서버와 CLI를 통해 동일한 작업을 수행할 수 있습니다.

### Amp의 macOS Satellites 대신 Tuist Mac 사용 {#remote-mac-satellites}

Amp에는 자체 클라우드 Mac인 [macOS Satellites](https://ampcode.com/docs/orbs/mac)도 있으며, 대기 목록에 가입한 워크스페이스를 위해 베타로 제공됩니다. 스레드가 둘 다 시작할 수 있을 때 Amp의 내장 지침은 macOS 작업을 위성에 보내므로 플러그인을 선택하는 경우는 드뭅니다. 스레드가 Tuist Mac을 사용하도록 하려면 다음 중 하나를 수행하세요:

- **본인의 macOS Satellites를 끕니다.** 각 구성원은 Amp의 [Settings → Experimental Features](https://ampcode.com/settings/experimental-features)에서 **Mac Satellites** 아래에서 이를 끕니다.
- **워크스페이스용으로 끕니다.** 워크스페이스의 orb가 [Tuist에서 실행](#connect)될 때 워크스페이스 관리자는 Amp 워크스페이스 설정의 **Orbs** 아래에서 **Where Orbs Run**을 **Self-Hosted Only**로 설정할 수 있습니다. 그러면 에이전트는 Amp 호스팅 위성을 시작할 수 없지만 구성원도 Amp의 내장 orb를 사용할 수 없으므로 모든 스레드가 자체 orb 제공자에서 실행될 때만 이 작업을 수행하세요.
- **Tuist Mac을 요청합니다.** 프롬프트나 Amp 워크스페이스 설정의 워크스페이스 에이전트 지침에 "macOS 작업에는 macOS Satellites가 아닌 `tuist_mac_*` 도구를 사용하세요."를 추가하여 모든 스레드가 따르도록 합니다.
