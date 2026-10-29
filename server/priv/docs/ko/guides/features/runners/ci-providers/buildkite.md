---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run your first Buildkite job on Tuist Runners: connect your cluster, name a queue after a Tuist profile, and target it from a step."
}
---
# Buildkite {#buildkite}

> [!IMPORTANT]
> **초대 전용**
>
> Tuist Runners는 현재 초대 전용입니다. 계정에 대한 액세스를 요청하려면 [문의하기](mailto:contact@tuist.dev) 또는 [커뮤니티 Slack](https://slack.tuist.dev)에서 저희에게 연락하세요.

Tuist는 Buildkite 클러스터의 자체 호스팅 큐를 모니터링하고 발견된 작업을 플릿에서 실행합니다. 파이프라인은 Buildkite에서 계속 실행되며, 컴퓨팅 리소스만 변경됩니다. 플릿에서 작업을 실행하려면 세 가지 변경 사항이 필요합니다: 클러스터를 연결하고, Tuist <.localized_link href="/guides/features/runners/profiles">프로필</.localized_link>에 따라 큐 이름을 지정하며, 단계에서 해당 큐를 대상으로 설정하세요.

1. **액세스 요청.** 베타 기간 동안 Runners는 초대 전용입니다. 활성화하려는 계정으로 [문의하세요](mailto:contact@tuist.dev).
2. **클러스터 연결.** Buildkite에서 클러스터를 열고 **Agent Tokens**으로 이동하여 토큰을 생성하세요. 토큰은 `bkct_`로 시작합니다. Tuist 대시보드에서 **설정 → 통합**으로 이동하고, Buildkite 카드에서 **연결**을 선택한 후 조직 슬러그와 토큰을 입력하세요. 토큰은 암호화되어 저장되며 다시 표시되지 않습니다. 나중에 조직을 변경하거나 토큰을 회전하려면 카드의 필드를 편집하고 **변경 사항 저장**을 선택하세요. Tuist는 1분 이내에 클러스터 모니터링을 시작합니다.
3. **Tuist 프로필에 따라 큐 이름을 지정하세요.** 모든 활성화된 계정은 두 개의 사용 준비 완료 <.localized_link href="/guides/features/runners/profiles">프로필</.localized_link>, `linux` 및 `macos`으로 시작하며, 큐 키가 프로필 레이블과 일치할 때 작업이 선택됩니다. 클러스터에서 `tuist-linux` 및 `tuist-macos` 키를 사용하여 자체 호스팅 큐를 생성한 다음, 단계에서 하나를 대상으로 설정하세요:

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

4. **푸시하고 모니터링하세요.** 작업이 큐에 추가되고 러너에 의해 할당되며, Tuist 대시보드의 **Runners** 섹션으로 스트리밍됩니다. 여기서 로그, 단계 및 머신 메트릭스를 추적할 수 있습니다. 러너는 해당 작업에만 범위가 지정된 자격 증명을 사용하여 작업 내부에서 로그를 전송하므로 Buildkite API 토큰이 필요하지 않습니다.

## 일시 중지 및 연결 해제 {#pausing-and-disconnecting}

Buildkite 큐에서 디스패치를 일시 중지하면 Tuist가 해당 큐에서 새 작업을 가져오지 않습니다. 이미 실행 중인 작업에는 영향을 미치지 않습니다.

**설정 → 통합** 아래의 Buildkite 카드에서 클러스터 연결을 해제하면 Tuist가 완전히 모니터링을 중지합니다.

## 캐시 볼륨 {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">캐시 볼륨</.localized_link>을 사용하여 작업 간에 Xcode, 모듈 및 Gradle 캐시와 기타 디렉터리를 유지하세요. 체크아웃 후와 이를 사용하는 명령어 전에 추가하세요.
