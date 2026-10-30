---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI 제공업체 · 러너 · 기능 · 가이드 · Tuist",
  "description": "Tuist 러너에서 첫 GitHub Actions 작업을 실행하세요: GitHub를 연결하고, runs-on을 Tuist 프로필로 지정하며, 대시보드에서 진행 상황을 확인하세요."
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **초대 전용**
>
> Tuist Runners는 현재 초대 전용입니다. 계정에 대한 액세스를 요청하려면 [문의](mailto:contact@tuist.dev)하거나 [커뮤니티 Slack](https://slack.tuist.dev)에서 연락하세요.

플릿에서 작업을 실행하려면 세 가지 변경이 필요합니다: GitHub 연결, Tuist <.localized_link href="/guides/features/runners/profiles">프로필</.localized_link>을 가리키도록 `runs-on` 설정, 그리고 푸시.

1. **액세스 요청.** 러너는 베타 기간 동안 초대 전용입니다. 활성화하려는 계정으로 [문의](mailto:contact@tuist.dev)하세요.
2. **GitHub 연결.** 프로젝트가 <.localized_link href="/guides/integrations/gitforge/github">GitHub 조직에 연결되어 있는지 확인하세요</.localized_link>. Tuist는 해당 조직의 `workflow_job` 이벤트를 수신하고 일치하는 작업을 플릿으로 전달합니다. 이 연결이 없으면 작업이 러너에 도달하지 않습니다.
3. **Tuist 프로필을 가리키도록 `runs-on` 설정.** 모든 활성화된 계정은 두 개의 사용 준비 완료 <.localized_link href="/guides/features/runners/profiles">프로필</.localized_link>로 시작합니다: `linux` 및 `macos`. `tuist-` 접두사를 사용하여 참조하세요:

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **러너 프로필로 Xcode 선택**
   >
   > macOS 러너 이미지에는 단일 Xcode 버전이 포함되어 있으며, Tuist는 프로필에 따라 작업 시작 전에 이를 선택합니다. GitHub 호스팅 러너에서 마이그레이션하는 경우, `xcode-select --switch`(또는 `xcode-select -s`) 또는 다른 도구와 액션을 사용하여 Xcode 버전을 전환하는 단계를 제거하세요. 이러한 단계는 일반적으로 GitHub 호스팅 이미지에 특정한 Xcode 설치를 참조하며 Tuist Runners에서 실패할 수 있습니다.
   >
   > 다른 Xcode 버전을 사용하려면, 해당 버전으로 <.localized_link href="/guides/features/runners/profiles#creating-a-profile">프로필을 생성하거나 선택</.localized_link>하고 `runs-on`을 업데이트하세요. 예를 들어 `runs-on: tuist-xcode-26-4`와 같이 설정합니다. 그러면 `xcodebuild`, `xcrun`, 및 `swift`은 워크플로우의 추가 설정 없이 프로필에서 선택한 Xcode를 사용합니다.

4. **푸시하고 모니터링.** 작업은 큐에 추가되고 러너에 의해 처리되며, Tuist 대시보드의 **Runners** 섹션으로 스트리밍됩니다. 여기서 로그, 단계 및 머신 지표를 확인할 수 있습니다.

## 캐시 볼륨 {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">캐시 볼륨</.localized_link>을 사용하여 작업 간에 Xcode, 모듈 및 Gradle 캐시와 기타 디렉터리를 유지하세요. 체크아웃 후와 이를 사용하는 명령어 전에 추가하세요.
