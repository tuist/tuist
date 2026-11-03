---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CI 제공업체 · 러너 · 기능 · 가이드 · Tuist",
  "description": "Tuist 러너에서 Bitrise 빌드를 실행하세요: 워크스페이스를 연결하고, 자체 호스팅 러너 풀을 Tuist 프로필과 연동한 후, 워크플로우에서 해당 풀을 선택합니다."
}
---
# Bitrise {#bitrise}

> [!IMPORTANT]
> **초대 전용**
>
> Tuist Runners는 현재 초대 전용입니다. 계정에 대한 액세스를 요청하려면 [문의](mailto:contact@tuist.dev)하거나 [커뮤니티 Slack](https://slack.tuist.dev)에서 저희에게 연락하세요.

> [!WARNING]
> **비공개 저장소 전용**
>
> Tuist는 모든 Bitrise 빌드를 신뢰합니다. 빌드는 계정의 캐시를 공유하고 해당 캐시에 쓸 수 있습니다. 공개 저장소의 포크에서 풀 리퀘스트를 빌드하는 워크플로가 있는 풀은 페어링하지 마세요.

Tuist는 Bitrise 워크스페이스의 자체 호스팅 러너 풀을 제공합니다. 이러한 풀 중 하나를 선택한 빌드는 풀과 페어링한 <.localized_link href="/guides/features/runners/profiles">프로필</.localized_link>에 해당하는 Tuist 머신에서 실행됩니다. 워크플로, 트리거 및 로그는 Bitrise에 유지되며 머신만 변경됩니다.

1. **액세스 요청.** 베타 기간 동안 Runners는 초대 전용입니다. 활성화하려는 계정으로 [문의](mailto:contact@tuist.dev)하세요.
2. **워크스페이스 연결.** Bitrise에서 **Workspace settings → Security → Workspace API tokens**을 열고 모든 프로젝트에 대해 Bitrise CI에 대한 **Viewer** 워크스페이스 역할과 **Tester/QA** 액세스 권한이 있는 토큰을 생성하세요. Tuist 대시보드에서 **Settings → Integrations**로 이동하고, Bitrise 카드에서 **Connect**를 선택한 후 토큰을 붙여넣으세요. Tuist는 토큰에서 워크스페이스를 읽고, 토큰을 암호화하여 저장하며 다시 표시하지 않습니다.
3. **러너 풀 생성.** Bitrise에서 **Workspace settings → Infrastructure**을 열고, **Add Runner pool**을 선택한 후, 대표하는 머신의 이름(예: `tuist-macos`)으로 이름을 지정하세요. 풀 토큰을 복사하세요. Bitrise는 이를 한 번만 표시합니다.
4. **풀을 Tuist 프로필과 페어링.** Tuist의 Bitrise 카드에서 **Runner pools** 아래에서 풀, 빌드를 실행할 Tuist 프로필을 선택하고, 풀 토큰을 붙여넣은 후 **Add pool**을 선택하세요. 모든 활성화된 계정은 두 개의 프로필(`tuist-linux` 및 `tuist-macos`)로 시작합니다. 사용하려는 프로필마다 하나의 풀을 추가하세요.
5. **워크플로에서 풀 선택.** Bitrise의 Workflow Editor에서 **Stacks & Machines**을 열고 **Self-Hosted Runner: tuist-macos**를 선택하세요. `bitrise.yml`에서 Tuist가 풀 이름 아래에 표시하는 풀의 스택을 설정하세요:

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

6. **빌드 실행.** 몇 초 이내에 Tuist 머신이 풀에 연결되어 빌드를 가져오고, 완료되면 연결을 해제합니다. 빌드는 Tuist 대시보드의 **Runners** 섹션에 머신 지표와 Bitrise로 돌아가는 링크(로그가 유지되는 곳)와 함께 표시됩니다.

## 전용 풀 {#dedicated-pools}

Tuist와 페어링한 풀은 Tuist 용도로만 사용하세요. 자체 머신 중 하나가 페어링된 풀에도 연결되면 해당 풀의 빌드를 위해 Tuist와 경쟁하게 됩니다.

## 러너 제한 {#runner-limit}

각 Tuist 머신은 빌드를 실행하는 동안 하나의 Bitrise 러너로カウント되며, 연결이 해제되면 카운팅이 중단됩니다. 따라서 Bitrise 플랜의 러너 제한은 Tuist 동시성 제한과 함께 동시에 Tuist에서 실행할 수 있는 빌드 수를 제한합니다.

## 연결 해제 {#disconnecting}

Bitrise 카드에서 풀을 제거하면 Tuist가 해당 풀의 빌드를 가져오는 것을 중지합니다. 이미 실행 중인 빌드는 영향을 받지 않습니다.

Bitrise 카드에서 **Disconnect**를 선택하면 워크스페이스와 모든 풀이 제거됩니다.
