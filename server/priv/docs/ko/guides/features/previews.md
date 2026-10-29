---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Share iOS and Android app builds instantly with Tuist Previews. Give teammates and stakeholders a link, no TestFlight or Play Console setup required."
}
---
# 프리뷰 {#previews}

Tuist Previews를 사용하면 앱 프리뷰를 생성하고 공유할 수 있어 팀원들이 로컬에서 다시 빌드하지 않고도 빌드를 테스트할 수 있습니다.

앱을 빌드할 때 피드백을 받기 위해 다른 사람들과 공유하고 싶을 수 있습니다. 전통적으로 팀들은 Apple의 [TestFlight](https://developer.apple.com/testflight/)와 같은 플랫폼에 앱을 빌드, 서명 및 푸시하여 이 작업을 수행합니다. 그러나 이 과정은 번거롭고 느릴 수 있으며, 특히 동료나 친구로부터 빠른 피드백을 원할 때 더욱 그렇습니다.

이 과정을 더 효율적으로 만들기 위해 Tuist는 누구나 앱의 프리뷰를 생성하고 공유할 수 있는 방법을 제공합니다.

> [!WARNING]
> **기기 빌드는 서명이 필요합니다**
>
> 기기를 대상으로 빌드할 때 앱이 올바르게 서명되었는지 확인하는 것은 현재 사용자의 책임입니다. 향후 이 과정을 간소화할 계획입니다.

::: code-group
```bash [Tuist Project (Debug)]
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Tuist Project (Release)]
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Release -sdk iphonesimulator # Build the app for the simulator
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Release -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Release
```
```bash [Xcode Project (Debug)]
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
```bash [Xcode Project (Release)]
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Release # Build the app for the simulator
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Release -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Release --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

이 명령어는 시뮬레이터 또는 실제 기기에서 앱을 실행하기 위해 누구와도 공유할 수 있는 링크를 생성합니다. 필요한 작업은 아래 명령어를 실행하는 것뿐입니다.

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

`.ipa` 파일을 공유할 때 프리뷰 링크를 사용하여 모바일 기기에서 직접 앱을 다운로드할 수 있습니다. `.ipa` 프리뷰에 대한 링크는 기본적으로 _비공개_ 이며, 이는 수신자가 앱을 다운로드하려면 Tuist 계정으로 인증해야 함을 의미합니다. 누구와든 앱을 공유하려면 프로젝트 설정에서 이를 공개로 변경할 수 있습니다.

`tuist run`를 사용하면 `latest`, 브랜치 이름 또는 특정 커밋 해시와 같은 지정자를 기반으로 최신 프리뷰를 실행할 수도 있습니다.

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **Ci에서의 고유 빌드 번호**
>
> 대부분의 CI 제공업체가 노출하는 CI 실행 번호를 활용하여 `CFBundleVersion`(빌드 버전)가 고유하도록 하십시오. 예를 들어 GitHub Actions에서는 `CFBundleVersion`를 <code v-pre>${{ github.run_number }}</code> 변수로 설정할 수 있습니다. 
>
> 동일한 바이너리(빌드)와 동일한 `CFBundleVersion`를 가진 프리뷰를 업로드하면 실패합니다.

## 트랙 {#tracks}

트랙을 사용하면 프리뷰를 이름이 지정된 그룹으로 조직할 수 있습니다. 예를 들어 내부 테스터용 `beta` 트랙과 자동화된 빌드용 `nightly` 트랙을 가질 수 있습니다. 트랙은 지연 생성됩니다 — 공유할 때 트랙 이름을 지정하면 존재하지 않는 경우 자동으로 생성됩니다.

특정 트랙에서 프리뷰를 공유하려면 `--track` 옵션을 사용하십시오.

```bash
tuist share App --track beta
tuist share App --track nightly
```

이는 다음과 같은 경우에 유용합니다.
- **프리뷰 조직화**: 목적별로 프리뷰를 그룹화합니다(예: `beta`, `nightly`, `internal`)
- **인앱 업데이트**: Tuist SDK는 트랙을 사용하여 사용자에게 알림을 보낼 업데이트를 결정합니다.
- **필터링**: Tuist 대시보드에서 트랙별로 프리뷰를 쉽게 찾고 관리합니다.

> [!WARNING]
> **프리뷰의 가시성**
>
> 프로젝트가 속한 조직에 접근 권한이 있는 사람만 프리뷰에 접근할 수 있습니다. 만료되는 링크에 대한 지원을 추가할 계획입니다.

## 릴리스 노트 {#release-notes}

환경 그룹에는 트랙을 사용하고 개별 빌드의 목적에는 릴리스 노트를 사용하십시오.

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

릴리스 노트는 선택 사항인 일반 텍스트이며 최대 10,000자까지 가능합니다. 첫 번째 비공백 줄은 웹 및 iOS 프리뷰 목록에서 한 줄 스니펫으로 표시되므로 빌드 번호 및 기타 식별 정보를 한눈에 볼 수 있습니다. 긴 줄은 생략되며 전체 노트는 상세 페이지에 표시됩니다. 두 목록 모두에서의 검색은 스니펫에 표시되지 않은 줄을 포함하여 표시 이름과 전체 릴리스 노트와 일치합니다. 여러 줄 노트는 지원되며, 예를 들어 `--release-notes "$(< release-notes.txt)"`와 같이 사용할 수 있습니다. 이는 앱의 표시 이름이나 트랙을 변경하지 않습니다.

### 호환성 {#preview-metadata-compatibility}

릴리스 노트는 추가 메타데이터이며 프리뷰 식별자의 일부가 아닙니다. 이전 및 새 클라이언트의 업로드는 여전히 플랫폼 간에 동일한 프리뷰로 그룹화됩니다. 첫 번째 비공백 노트는 유지됩니다. 이후 업로드는 이전에 없었던 노트를 채울 수 있지만 기존 노트를 덮어쓸 수는 없습니다. `release_notes`을 생략하거나 `null`를 보내거나 빈 문자열 또는 공백만으로 구성된 문자열을 보내면 노트가 지워지지 않습니다. 기존 프리뷰는 백필되지 않으며 노트 없이도 유효하게 유지됩니다.

목록 API의 선택적 `track` 쿼리 매개변수는 기존 트랙 저장소와 일관되게 대소문자를 구분하지 않고 전체 트랙 이름과 일치합니다. 모든 트랙을 나열하려면 이를 생략하거나 빈 값(`?track=`)을 보내십시오. 트랙 이름은 고정된 값 목록이 아닌 개방형 문자열로 유지됩니다. iOS 앱의 **모든 트랙** 선택은 필터를 생략합니다. iOS 앱의 트랙 필은 빌드 목록과 동일한 프리뷰 읽기 권한 하에서 `GET /api/projects/:account_handle/:project_handle/previews/tracks`에서 전체 프로젝트 요약을 로드합니다. 해당 엔드포인트는 정렬되고 대소문자를 구분하지 않고 그룹화된 이름이 지정된 트랙과 함께 `{total_count, tracks: [{name, count}]}`를 반환합니다. 카운트는 페이지네이션, 검색 및 선택된 트랙과 독립적으로 전체 프로젝트를 커버하며 총계에는 추적되지 않은 프리뷰가 포함됩니다. 번들 식별자가 있는 목록 가능한 프리뷰만 카운트됩니다. 목록 API는 또한 표시 이름 또는 전체 릴리스 노트의 리터럴 대소문자 구분 없는 부분 문자열을 위한 선택적 `search`을 허용하며, 페이지네이션 전에 트랙과 결합됩니다. 기존 `display_name` 필터링은 정확히 유지됩니다.

이전 클라이언트는 두 필드 중 어느 것도 보내지 않고 프리뷰를 계속 업로드하고 목록화할 수 있습니다. 새 클라이언트는 트랙이나 노트를 생략한 이전 응답을 수용하며 미래 서버에서 추가된 알 수 없는 응답 속성을 무시합니다. API 통합도 추가 메타데이터가 호환되도록 알 수 없는 응답 속성을 무시해야 합니다.

자체 호스팅 배포는 이러한 기능을 사용하기 위해 릴리스 노트 및 트랙 필터링을 지원하는 서버 버전과 함께 업데이트된 CLI 및 앱이 필요합니다. 이전 서버는 노트나 알 수 없는 쿼리 매개변수를 무시할 수 있습니다. 트랙 검색이 불가능한 경우 iOS 앱은 필터링되지 않은浏览을 계속 사용할 수 있게 하며 트랙 선택에는 업데이트된 서버가 필요하다고 설명합니다. 활성 필터에도 불구하고 서버가 다른 트랙의 프리뷰를 반환하면 iOS 앱은 오해의 소지가 있는 결과를 제시하는 대신 필터링이 지원되지 않음을 보고합니다. macOS 앱은 먼저 앱당 최신 호환 프리뷰를 요청합니다. 플랫폼 필터를 적용하기 전에 distinct 앱을 선택하는 이전 서버의 경우 사용 가능한 빌드를 숨길 수 있는 컷오프를 부과하지 않고 페이지네이션된 기록으로 대체합니다.

## Tuist macOS 앱 {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Tuist Previews 실행을 더 쉽게 하기 위해 Tuist macOS 메뉴 바 앱을 개발했습니다. Tuist CLI를 통해 프리뷰를 실행하는 대신 macOS 앱을 [다운로드](https://tuist.dev/download)할 수 있습니다. `brew install --cask tuist/tuist/tuist`를 실행하여 앱을 설치할 수도 있습니다.

프리뷰 페이지에서 "Run"을 클릭하면 macOS 앱이 현재 선택된 기기에서 자동으로 실행됩니다.

## Tuist iOS 앱 {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="App Store에서 다운로드" style="height: 40px;">
    </a>
</div>

macOS 앱과 마찬가지로 Tuist iOS 앱은 프리뷰에 접근하고 실행하는 과정을 간소화합니다. 각 프리뷰는 자신의 트랙을 표시합니다. 기본 검색 필드를 사용하여 앱 이름으로 프리뷰를 찾은 다음 **Tracks** 아래의 필터를 선택하여 환경별로 필터링하세요. 선택된 필터는 보라색으로 표시됩니다. 트랙 필터를 제거하려면 **All**을 선택하세요. 각 필터는 프로젝트 전체의 프리뷰 개수를 표시하며, All에는 트랙이 없는 빌드도 포함됩니다. 검색 및 트랙 필터링은 이미 로드된 프리뷰뿐만 아니라 모든 페이지에 적용됩니다. 각 빌드의 트랙 태그는 커밋 해시 옆에 표시됩니다.

## Pull/Merge 요청 댓글 {#pullmerge-request-comments}

> [!WARNING]
> **Git 플랫폼 통합 필요**
>
> 자동으로 Pull/Merge 요청 댓글을 받으려면 <.localized_link href="/guides/server/accounts-and-projects">원격 프로젝트</.localized_link>를 <.localized_link href="/guides/server/authentication">Git 플랫폼</.localized_link>과 통합하세요.

새로운 기능 테스트는 모든 코드 리뷰의 일부여야 합니다. 하지만 앱을 로컬에서 빌드해야 하는 것은 불필요한 마찰을 유발하며, 종종 개발자가 기기에서의 기능 테스트를 완전히 건너뛰게 만듭니다. 하지만 *각 Pull Request에 Tuist macOS 앱에서 선택한 기기에서 앱을 자동으로 실행하는 빌드 링크가 포함되어 있다면 어떨까요?*

Tuist 프로젝트가 [GitHub](https://github.com)와 같은 Git 플랫폼과 연결되면 CI 워크플로우에 <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link>를 추가하세요. 그러면 Tuist가 Pull Request에 직접 프리뷰 링크를 게시합니다: ![Tuist 프리뷰 링크가 포함된 GitHub 앱 댓글](/images/guides/features/github-app-with-preview.png)

## 앱 내 업데이트 알림 {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk)는 앱이 최신 프리뷰 버전을 감지하고 사용자에게 알릴 수 있게 해줍니다. 이는 테스터들을 최신 빌드로 유지하는 데 유용합니다.

SDK는 동일한 **프리뷰 트랙** 내에서 업데이트를 확인합니다. `--track`를 사용하여 명시적인 트랙으로 프리뷰를 공유하면 SDK는 해당 트랙에서 업데이트를 찾습니다. 트랙이 지정되지 않으면 Git 브랜치가 트랙으로 사용되므로 `main` 브랜치에서 빌드된 프리뷰는 `main`에서 빌드된 최신 프리뷰에 대해서만 알림을 받습니다.

### 설치 {#sdk-installation}

Tuist SDK를 Swift Package 의존성으로 추가하세요:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 업데이트 모니터링 {#sdk-monitor-updates}

`monitorPreviewUpdates`를 사용하여 주기적으로 새 프리뷰 버전을 확인하세요:

```swift
import TuistSDK

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    TuistSDK(
                        fullHandle: "myorg/myapp",
                        apiKey: "your-api-key"
                    )
                    .monitorPreviewUpdates()
                }
        }
    }
}
```

### 단일 업데이트 확인 {#sdk-single-check}

수동 업데이트 확인용:

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### 업데이트 모니터링 중지 {#sdk-stop-monitoring}

`monitorPreviewUpdates`는 취소할 수 있는 `Task`를 반환합니다:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> 시뮬레이터 및 App Store 빌드에서는 업데이트 확인이 자동으로 비활성화됩니다.

## README 배지 {#readme-badge}

저장소에서 Tuist Previews를 더 잘 보이게 하려면 최신 Tuist Preview를 가리키는 배지를 `README` 파일에 추가할 수 있습니다:

[![Tuist 프리뷰](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

배지를 `README`에 추가하려면 다음 마크다운을 사용하고 계정 및 프로젝트 핸들을 여러분의 것으로 교체하세요:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

프로젝트에 서로 다른 번들 식별자를 가진 여러 앱이 포함된 경우 `bundle-id` 쿼리 매개변수를 추가하여 링크할 앱의 프리뷰를 지정할 수 있습니다:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 자동화 {#automations}

`tuist share` 명령에서 JSON 출력을 얻기 위해 `--json` 플래그를 사용할 수 있습니다:
```
tuist share --json
```

JSON 출력은 CI 제공자를 사용하여 Slack 메시지를 게시하는 등 custom 자동화를 생성하는 데 유용합니다. JSON에는 전체 프리뷰 링크가 포함된 `url` 키와 실제 기기에서 프리뷰를 더 쉽게 다운로드할 수 있도록 QR 코드 이미지 URL이 포함된 `qrCodeURL` 키가 있습니다. JSON 출력 예시는 다음과 같습니다:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
