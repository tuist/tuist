---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI 제공자 · 러너 · 기능 · 가이드 · Tuist",
  "description": "Tuist 러너에서 첫 GitHub Actions 작업을 실행하세요: GitHub를 연결하고, runs-on을 Tuist 프로필로 지정하며, 대시보드에서 확인하세요."
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

플릿에서 작업을 실행하려면 세 가지 변경이 필요합니다: GitHub를 연결하고, `runs-on`를 Tuist <.localized_link href="/guides/features/runners/profiles">프로필</.localized_link>로 지정하며, 코드를 푸시하세요.

1. **GitHub를 연결하세요.** 프로젝트가 <.localized_link href="/guides/integrations/gitforge/github">GitHub 조직에 연결</.localized_link>되어 있는지 확인하세요. Tuist는 해당 조직의 `workflow_job` 이벤트를 수신하여 일치하는 작업을 플릿으로 전달합니다. 이 연결이 없으면 어떤 작업도 러너에 도달하지 않습니다.
2. **`runs-on`를 Tuist 프로필로 지정하세요.** 활성화된 모든 계정은 기본적으로 사용할 수 있는 두 개의 <.localized_link href="/guides/features/runners/profiles">프로필</.localized_link>(`linux` 및 `macos`)을 제공합니다. `tuist-` 접두사를 사용하여 참조하세요:

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
   > macOS 러너 이미지에는 단일 Xcode 버전이 포함되어 있으며, Tuist는 프로필에 따라 작업 시작 전에 이를 선택합니다. GitHub 호스팅 러너에서 마이그레이션하는 경우, `xcode-select --switch`(또는 `xcode-select -s`) 또는 기타 도구나 액션을 사용하여 Xcode 버전을 전환하는 단계를 제거하세요. 이러한 단계는 일반적으로 GitHub 호스팅 이미지에 특정한 Xcode 설치를 참조하며 Tuist 러너에서는 실패할 수 있습니다.
   >
   > 다른 Xcode 버전을 사용하려면, 해당 버전의 <.localized_link href="/guides/features/runners/profiles#creating-a-profile">프로필을 생성하거나 선택</.localized_link>하고 `runs-on`를 업데이트하세요(예: `runs-on: tuist-xcode-26-4`). 그러면 `xcodebuild`, `xcrun`, `swift`는 워크플로우의 추가 설정 없이 프로필에서 선택한 Xcode를 사용합니다.

3. **푸시하고 모니터링하세요.** 작업은 큐에 들어가고, 러너에 의해 할당되며, Tuist 대시보드의 **러너** 섹션으로 스트리밍됩니다. 여기서 로그, 단계 및 머신 지표를 추적할 수 있습니다.

## 캐시 볼륨 {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">캐시 볼륨</.localized_link>을 사용하여 작업 간에 Xcode, 모듈 및 Gradle 캐시와 기타 디렉터리를 유지하세요. 체크아웃 후에 그리고 이를 사용하는 명령어 전에 추가하세요.

작업에 `id-token: write` 권한을 부여하여 캐시 볼륨과 캐시된 체크아웃이 시작되는 즉시 연결되도록 하세요. 이 권한이 없으면 러너는 GitHub가 실행 중인 작업을 보고할 때까지 기다리며, GitHub가 늦게 보고하는 작업은 빈 캐시로 시작됩니다. OpenID Connect로 Tuist에 로그인하는 워크플로우는 이미 이 권한을 부여합니다.

```yaml
permissions:
  contents: read
  id-token: write
```
