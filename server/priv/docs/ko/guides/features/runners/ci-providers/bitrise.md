---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CI 제공업체 · 러너 · 기능 · 가이드 · Tuist",
  "description": "Tuist 러너에서 Bitrise 빌드를 실행하세요: 워크스페이스를 연결하고, 자체 호스팅 러너 풀을 Tuist 프로필과 페어링한 후, 워크플로에서 해당 풀을 선택하세요."
}
---
# Bitrise {#bitrise}

<!-- @snippet: ./_invite-only -->

> [!WARNING]
> **비공개 저장소 전용**
>
> Tuist는 모든 Bitrise 빌드를 신뢰합니다. 빌드는 계정의 캐시를 공유하고 여기에 쓸 수 있습니다. 공개 저장소의 포크에서 풀 리퀘스트를 빌드하는 워크플로우가 있는 풀은 연결하지 마세요.

Tuist는 Bitrise 워크스페이스의 자체 호스팅 러너 풀을 제공합니다. 해당 풀 중 하나를 선택한 빌드는 풀과 연결한 <.localized_link href="/guides/features/runners/profiles">프로필</.localized_link>에 해당하는 Tuist 머신에서 실행됩니다. 워크플로우, 트리거 및 로그는 Bitrise에 그대로 유지되며, 머신만 변경됩니다.

1. **워크스페이스를 연결하세요.** Bitrise에서 **Workspace settings → Security → Workspace API tokens**를 열고, 모든 프로젝트에 대해 Bitrise CI의 **Viewer** 워크스페이스 역할과 **Tester/QA** 액세스 권한을 가진 토큰을 생성하세요. Tuist 대시보드에서 **Settings → Integrations**로 이동하고, Bitrise 카드에서 **Connect**를 선택한 후 토큰을 붙여넣으세요. Tuist는 토큰에서 워크스페이스 정보를 읽고, 토큰을 암호화하여 저장하며 다시 표시하지 않습니다.
2. **러너 풀을 생성하세요.** Bitrise에서 **Workspace settings → Infrastructure**를 열고, **Add Runner pool**을 선택한 후, 해당 풀이 대표하는 머신의 이름(예: `tuist-macos`)으로 이름을 지정하세요. 풀 토큰을 복사하세요. Bitrise는 이를 한 번만 표시합니다.
3. **풀을 Tuist 프로필과 연결하세요.** Tuist의 Bitrise 카드에서 **Runner pools** 아래에서 풀과 빌드가 실행될 Tuist 프로필을 선택하고, 풀 토큰을 붙여넣은 후 **Add pool**을 선택하세요. 활성화된 모든 계정은 `tuist-linux`와 `tuist-macos` 두 개의 프로필로 시작합니다. 사용하려는 프로필마다 하나의 풀을 추가하세요.
4. **워크플로우에서 풀을 선택하세요.** Bitrise의 Workflow Editor에서 **Stacks & Machines**를 열고 **Self-Hosted Runner: tuist-macos**를 선택하세요. `bitrise.yml`에서 Tuist가 풀 이름 아래에 표시하는 풀의 스택을 설정하세요:

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

5. **빌드를 실행하세요.** 몇 초 이내에 Tuist 머신이 풀에 연결되어 빌드를 수행하고, 완료되면 연결을 해제합니다. 빌드는 Tuist 대시보드의 **Runners** 섹션에 머신 지표와 Bitrise로 돌아가는 링크(로그가 유지되는 곳)와 함께 표시됩니다.

## 전용 풀 {#dedicated-pools}

Tuist와 연결한 풀은 Tuist 전용으로만 사용하세요. 직접 소유한 머신 중 하나가 연결된 풀에도 연결되면, 해당 풀의 빌드를 위해 Tuist와 경쟁하게 됩니다.

## 러너 제한 {#runner-limit}

각 Tuist 머신은 빌드를 실행하는 동안 Bitrise 러너 하나로 간주되며, 연결이 해제되면 카운트에서 제외됩니다. 따라서 Bitrise 플랜의 러너 제한은 Tuist 동시성 제한과 함께 Tuist에서 동시에 실행할 수 있는 빌드 수를 제한합니다.

## 연결 해제 {#disconnecting}

Bitrise 카드에서 풀을 제거하면 Tuist가 해당 풀의 빌드를 가져가지 않도록 중단됩니다. 이미 실행 중인 빌드에는 영향을 미치지 않습니다.

Bitrise 카드에서 **Disconnect**를 선택하면 워크스페이스와 모든 풀이 제거됩니다.
