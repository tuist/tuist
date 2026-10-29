---
{
  "title": "Profiles",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Runner profiles are named machine shapes you reference from runs-on to choose a platform, size, and Xcode version for Tuist Runners."
}
---
# 프로필 {#profiles}

**프로필**은 계정 범위의 명명된 머신 셰이프입니다. 워크플로의 `runs-on`에서 이를 참조하면, Tuist는 일치하는 러너로 작업을 라우팅합니다. 프로필은 인프라 선택 사항(플랫폼, 크기, Xcode 버전)을 모든 워크플로 파일에 분산시키지 않고 한곳에 모아두고, CI가指向할 수 있는 안정적인 라벨을 제공합니다.

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

라벨은 `tuist-` 접두사가 붙은 프로필 이름입니다. 이름이 `macos`인 프로필은 `runs-on: tuist-macos`이고, 이름이 `linux-large`인 프로필은 `runs-on: tuist-linux-large`입니다. 매칭은 대소문자를 구분하지 않습니다.

## 기본 프로필 {#default-profiles}

Runners가 활성화된 모든 계정은 아무것도 구성하지 않고도 풀을 사용할 수 있도록 두 개의 프로필로 시작합니다:

{{runner_default_profiles_table}}

둘 다 해당 플랫폼의 기본 <.localized_link href="/guides/features/runners/profiles#machine-shapes">셰이프</.localized_link>를 가리킵니다. 이들은 **보호됨** 상태이므로 삭제할 수 없으며, 워크플로가 의존하는 라벨이 항상 해결됩니다. 여전히 셰이프나 Xcode 버전을 변경할 수 있으며, 다른 크기나 Xcode 버전에 대한 추가 프로필을 생성할 수 있습니다.

## 머신 셰이프 {#machine-shapes}

러너는 macOS(Apple 실리콘, Mac 풀에서 가상화됨)와 Linux에서 사용할 수 있습니다. 각 프로필은 아래 카탈로그에서 하나의 머신 셰이프, 즉 `(vCPUs, memory)` 쌍을 고정합니다.

### Linux {#linux}

{{runner_linux_shapes_table}}

모든 Linux 프로필은 `/dev/kvm`을 통해 <.localized_link href="/guides/features/runners#android-emulators">하드웨어 가속 Android 에뮬레이터</.localized_link>를 지원합니다. 별도의 KVM 프로필이 필요하지 않습니다.

### macOS {#macos}

{{runner_macos_shapes_table}}

더 큰 macOS 셰이프는 풀 내에서 더 적은 수의 머신에서 실행되므로, 이를 요청하는 작업은 더 작은 셰이프에서 실행되는 동일한 작업보다 시작을 위해 더 오래 기다릴 수 있습니다. 작업이 CPU에 의해 제한될 때 더 큰 셰이프를 선택하고, 그 외의 경우에는 기본 셰이프를 유지하세요. 확실하지 않다면 둘 다에서 작업을 실행하고 대시보드에서 지속 시간을 비교하세요.

macOS 프로필은 또한 **Xcode 버전**을 고정합니다. 이 버전은 해당 Xcode가 미리 설치된 러너 이미지를 선택하므로, 작업이 툴체인이 이미 준비된 상태에서 시작됩니다. 현재 지원되는 버전:

{{runner_macos_xcode_versions}}

> [!NOTE]
> 하드웨어와 Xcode 릴리스를 추가함에 따라 카탈로그는 진화합니다. 대시보드의 **새 프로필** 양식과 `tuist runner profile catalog`는 항상 계정에 현재 사용 가능한 셰이프와 Xcode 버전을 표시하므로, 이를 신뢰할 수 있는 출처로 간주하세요.

macOS 러너의 이름은 실행 중인 macOS 버전, 프로필의 Xcode 버전 및 셰이프를 나타냅니다. 예를 들어 `tuist-macos-26.6-xcode-27.0-6vcpu-14gb-1a2b3c4d5e6f`입니다. 이 이름은 GitHub의 작업 **작업 설정** 단계와 Tuist 대시보드의 작업 세부 정보에 표시됩니다.

## 프로필 생성 {#creating-a-profile}

1. 계정 대시보드의 **Runners → Profiles** 섹션을 엽니다.
2. **새 프로필**을 선택합니다.
3. 이름을 지정하고, 플랫폼을 선택하고, 셰이프를 선택하세요. macOS의 경우 Xcode 버전도 선택하세요.
4. 저장한 후, 워크플로에서 `runs-on: tuist-<name>`로 참조하세요.

명령줄에서도 프로필을 관리할 수 있습니다. 프로필 생성, 변경 및 삭제에는 대시보드와 마찬가지로 계정 관리 권한 또는 `account:runners:write` 스코프가 포함된 계정 토큰이 필요합니다:

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

에이전트는 <.localized_link href="/guides/features/agentic-coding/mcp">MCP 서버</.localized_link>를 통해 동일한 작업을 수행할 수 있습니다.

예를 들어, 8 vCPU / 32 GB 셰이프에서 이름이 `linux-large`인 프로필:

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

또는 Xcode `26.4.1`에 고정된 이름이 `xcode-26-4`인 macOS 프로필로, 기본 `macos` 프로필이 최신 버전을 추적하는 동안 작업이 이전 툴체인에서 실행될 수 있도록 합니다:

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
