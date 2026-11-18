---
{
  "title": "Amp",
  "titleTemplate": ":title · 샌드박스 · 기능 · 가이드 · Tuist",
  "description": "Linux 또는 macOS에서 실행되는 Tuist 샌드박스에서 Amp 워크스페이스의 orbs를 실행하세요."
}
---
# Amp {#amp}

> [!IMPORTANT]
> **초대 전용**
>
> Tuist 샌드박스(Linux 및 macOS)는 현재 초대 전용입니다. 계정 액세스를 요청하려면 [문의하기](mailto:contact@tuist.dev) 또는 [커뮤니티 Slack](https://slack.tuist.dev)에서 저희에게 연락하세요.

[Amp](https://ampcode.com)는 각 스레드의 도구를 해당 스레드의 리포지토리가 체크아웃된 머신인 [orb](https://ampcode.com/docs/orbs)에서 실행합니다. Tuist는 Amp 워크스페이스의 [자체 호스팅 orb 제공자](https://ampcode.com/docs/orbs/self-hosted)가 될 수 있습니다. 이를 선택한 모든 스레드는 Linux 또는 macOS에서 자체 Tuist <.localized_link href="/guides/features/sandboxes">샌드박스</.localized_link> 내에서 실행됩니다. 직접 무언가를 실행하거나 호스팅할 필요는 없습니다.

## Amp 연결 {#connect}

Amp 워크스페이스와 Tuist 계정 모두의 관리자여야 합니다.

1. Amp에서 워크스페이스의 **Settings → Orbs**를 열고, **Add Orb Provider**를 클릭한 후 예를 들어 `tuist`와 같이 이름을 지정하세요. 멤버는 이 이름으로 제공자를 선택합니다. `aop_live_…` 토큰을 복사하세요. Amp는 이 토큰을 한 번만 표시합니다.
2. Amp에서 제공자의 **Edit** 대화 상자에서 다음 **Orb types**을 추가하고 기본값을 선택하세요:

   | 유형 | 플랫폼 | 셰이프 |
   | --- | --- | --- |
   | `linux` | Linux | 2 vCPU, 4 GiB RAM, 10 GB 워크스페이스 |
   | `macos` | Xcode 포함 macOS | 8 vCPU, 8 GiB RAM, 10 GB 워크스페이스 |

3. Tuist에서 계정의 대시보드에 있는 **Sandboxes**를 열고, Amp 카드에서 **Connect**를 클릭한 후 토큰을 붙여넣으세요.

Tuist가 제공자를 서비스하면 카드에 **Connected**로 표시됩니다. 하나의 Tuist 계정은 하나의 제공자를 서비스합니다. Amp에서 해당 제공자를 사용할 수 있는 모든 사용자는 orbs를 실행하며, 이는 연결된 Tuist 계정에 청구됩니다. 중지를 원하면 카드에서 **Disconnect**를 클릭하거나 Amp에서 제공자를 비활성화하세요.

## 스레드 시작 {#start-a-thread}

Amp의 새 스레드 작성기에서 **Orb**를 클릭하고, **Self-Hosted** 아래에서 Tuist 제공자를 선택한 후 `linux` 또는 `macos`를 선택하세요. Amp CLI에서:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

스레드는 수명 동안 orb 유형을 유지합니다. 유형이 없으면 제공자의 기본값을 사용합니다. 모든 새 스레드에 하나의 플랫폼을 사용하려면 Amp의 **Settings → Orbs**에서 **Default Orb** 아래에서 제공자와 해당 유형을 선택하세요.

Amp는 모든 orb에서 수행하는 것처럼 리포지토리를 복제하고, `.agents/setup` 스크립트를 실행하며 Git 자격 증명을 설정합니다. 각 orb는 또한 계정의 Tuist <.localized_link href="/guides/features/cache">캐시</.localized_link>를 읽을 수 있습니다.

## 일시 중지 및 보존 {#retention}

스레드가 유휴 상태가 되면 Amp는 해당 orb를 일시 중지합니다. 다음 메시지는 파일을 그대로 유지하면서 다시 시작합니다.

- **Linux:** 실행 중인 프로세스는 일시 중지를 견딥니다. 오랫동안 일시 중지된 orb는 아카이브 저장소로 이동하며, 다음 메시지에서 프로세스 없이 복원됩니다. Linux orb는 Amp가 스레드의 orb를 삭제할 때까지 파일을 유지합니다.
- **macOS:** 7일 동안 일시 중지되거나 오류 상태인 orb는 삭제됩니다. 스레드의 다음 메시지는 새로운 orb를 시작하고 Amp는 `.agents/setup`를 다시 실행합니다. 머신의 첫 번째 macOS orb는 Amp CLI를 설치하므로 시작하는 데 최대 2분이 걸릴 수 있습니다.

Amp가 일시 중지하지 않은 상태로 유휴 상태를 유지하는 orb(예: 일시 중지 신호가 도착하지 않은 경우)는 거의 CPU를 사용하지 않은 상태에서 10분 후에 일시 중지됩니다.
