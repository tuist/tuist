---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# 미리 보기 {#previews}

::: warning 요구 사항
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 계정 및
  프로젝트</LocalizedLink>
<!-- -->
:::

앱을 빌드할 때 다른 사람의 피드백을 받기 위해 공유하고 싶을 수 있습니다. 일반적으로 팀은 앱을 빌드하고 서명하여 Apple의
[TestFlight](https://developer.apple.com/testflight/)와 같은 플랫폼에 올리는 방식으로 이 작업을
수행합니다. 하지만 이 과정은 번거롭고 느릴 수 있으며, 특히 동료나 친구로부터 빠른 피드백을 받고자 할 때는 더욱 그렇습니다.

이 과정을 더욱 간소화하기 위해, Tuist는 앱의 미리보기를 생성하고 누구와도 공유할 수 있는 방법을 제공합니다.

::: warning 기기용 빌드는 서명 필요
<!-- -->
기기용으로 빌드할 때, 앱이 올바르게 서명되었는지 확인하는 것은 현재는 여러분의 책임이지만, 향후 이 과정을 간소화할 계획입니다.
<!-- -->
:::

::: code-group
```bash [Tuist Project]
tuist generate App
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

이 명령은 시뮬레이터나 실제 기기에서 앱을 실행할 수 있도록 다른 사람과 공유할 수 있는 링크를 생성합니다. 아래 명령을 실행하기만 하면
됩니다:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

`.ipa` 파일을 공유할 때, **미리 보기** 링크를 사용하여 모바일 기기에서 직접 앱을 다운로드할 수 있습니다. ` .ipa` 미리 보기
링크는 기본적으로 _비공개_ 로 되어 있는데, 수신자가 앱을 다운로드하려면 자신의 Tuist 계정으로 인증해야 하는 것을 의미 합니다. 앱을
다른 사람과 공유하려는 경우 프로젝트 설정에서 _공개_로 변경할 수 있습니다.

`tuist run` 을 사용하면 `최신`, 브랜치 이름 또는 특정 커밋 해시와 같은 지정자를 기반으로 최신 미리보기를 실행할 수도 있습니다:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning CI의 고유 빌드 번호
<!-- -->
대부분의 CI 제공업체가 제공하는 CI 실행 번호를 활용하여 `CFBundleVersion` (빌드 버전)이 고유하도록 만드세요. 예를 들어,
GitHub Actions에서 `CFBundleVersion` 을 <code v-pre>${{ github.run_number }}</code>
변수로 설정할 수 있습니다.

동일한 바이너리(빌드)와 동일한 `CFBundleVersion` 으로 미리 보기를 업로드하면 실패합니다.
<!-- -->
:::

## 트랙 {#tracks}

트랙을 사용하면 미리 보기를 이름 지정된 그룹으로 구성할 수 있습니다. 예를 들어 내부 테스터를 위한 `베타` 트랙과 자동화된 빌드를 위한
`선공개` 트랙이 있을 수 있습니다. 트랙은 느리게 생성되므로 공유할 때 트랙 이름을 지정하기만 하면 트랙이 없는 경우 자동으로 생성됩니다.

특정 트랙에서 미리보기를 공유하려면 `--track` 옵션을 사용하세요:

```bash
tuist share App --track beta
tuist share App --track nightly
```

이 기능은 아래 경우에 유용합니다:
- **미리보기 구성**: 목적별 그룹 미리보기(예: `베타`, `선공개`, `내부`)
- **인앱 업데이트**: Tuist SDK는 트랙을 사용하여 사용자에게 알릴 업데이트를 결정합니다
- **필터링**: Tuist 대시보드에서 트랙별 미리보기를 쉽게 찾고 관리할 수 있습니다

::: warning 미리 보기 권한
<!-- -->
프로젝트가 속한 조직에 대한 액세스 권한이 있는 사람만 미리 보기에 액세스할 수 있습니다. 만료되는 링크에 대한 지원도 추가할 계획입니다.
<!-- -->
:::

## Tuist macOS 앱 {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Tuist 미리 보기를 더욱 쉽게 실행할 수 있도록, Tuist는 Tuist macOS 메뉴바 앱을 개발했습니다. Tuist CLI를 통해 미리
보기를 실행하는 대신, macOS 앱을 [다운로드](https://tuist.dev/download)할 수 있습니다. ` brew install
--cask tuist/tuist/tuist`을 실행하여 앱을 설치할 수도 있습니다.

이제 미리보기 페이지에서 '실행'을 클릭하면, 현재 선택한 기기에서 macOS 앱이 자동으로 실행됩니다.

::: warning 요구 사항
<!-- -->
Xcode가 로컬에 설치되어 있어야 하며 macOS 14 이상을 사용 중이어야 합니다.
<!-- -->
:::

## Tuist iOS 앱 {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

macOS 앱과 마찬가지로, Tuist iOS 앱은 미리보기에 액세스하고 실행하는 과정을 원활하게 합니다.

## Pull/병합 요청 댓글 {#pullmerge-request-comments}

::: warning Git과 통합 필요
<!-- -->
자동으로 Pull/병합 요청 댓글을 받으려면
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist
프로젝트</LocalizedLink>를 <LocalizedLink href="/guides/server/authentication">Git
플랫폼</LocalizedLink>과 통합하세요.
<!-- -->
:::

새로운 기능을 테스트하는 것은 모든 코드 리뷰의 일부가 되어야 합니다. 그러나 앱을 로컬에서 빌드해야 하는 경우 불필요한 마찰이 발생하여
개발자가 기기에서 기능 테스트를 아예 건너뛰는 경우가 종종 있습니다. 하지만 *각 Pull Request에 Tuist macOS 앱에서 선택한
기기에서 앱을 자동으로 실행할 수 있는 빌드 링크가 포함되어 있다면 어떨까요?*

Tuist 프로젝트가 [GitHub](https://github.com)와 같은 Git 플랫폼에 연결되면,
<LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink>을 CI 워크플로에
추가하세요. 그러면 Tuist가 여러분의 Pull Request에 미리보기 링크를 바로 답니다: ![Tuist 미리보기 링크가 포함된
GitHub 앱 댓글](/images/guides/features/github-app-with-preview.png)


## 인앱 업데이트 알림 {#in-app-update-notifications}

Tuist SDK](https://github.com/tuist/sdk)를 사용하면 앱에서 최신 프리뷰 버전을 사용할 수 있는 시기를 감지하여
사용자에게 알릴 수 있습니다. 이는 테스터를 최신 빌드로 유지하는 데 유용합니다.

SDK는 동일한 **미리 보기 트랙** 내에서 업데이트를 확인합니다. ` --track` 을 사용하여 프리뷰를 명시적 트랙과 공유하면, SDK는
해당 트랙에서 업데이트를 찾습니다. 트랙을 지정하지 않으면 git 브랜치가 트랙으로 사용되므로 `main` 브랜치에서 빌드된 미리 보기는
`main` 에서 빌드된 최신 미리 보기에 대해서만 알림을 보냅니다.

### 설치 {#sdk-installation}

Tuist SDK를 Swift Package 의존성으로 추가하세요:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 업데이트 모니터링 {#sdk-monitor-updates}

주기적으로 새 미리 보기 버전을 확인하기 위해 `monitorPreviewUpdates`를 사용하세요:

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

수동 업데이트 확인:

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

`monitorPreviewUpdates` 는 취소할 수 있는 `Task`를 반환합니다:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

::: info Mise란?
<!-- -->
시뮬레이터 및 App Store 빌드에서는 업데이트 확인이 자동으로 비활성화 됩니다.
<!-- -->
:::

## README 배지 {#readme-badge}

Repository에서 Tuist 미리 보기를 더 잘 보이게 하려면 `README` 파일에 최신 튜이스트 미리 보기를 가리키는 배지를 추가하면
됩니다:

[![Tuist 미리
보](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

`README` 에 배지를 추가하려면, 아래 마크다운을 사용하고 계정과 프로젝트 Handle을 여러분의 것으로 바꾸세요:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

프로젝트에 번들 식별자가 다른 여러 앱이 포함된 경우, URL에 `bundle-id` Parameter를 추가하여 링크할 앱의 미리 보기를
지정할 수 있습니다:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 자동화 {#automations}

`tuist share` 명령에서 JSON 출력을 얻기 위해 `--json` 플래그를 사용할 수 있습니다:
```
tuist share --json
```

JSON 출력은 CI 제공업체를 사용하여 Slack 메시지를 게시하는 등의 사용자 지정 자동화를 만드는 데 유용합니다. JSON에는 전체 미리
보기 링크가 포함된 `url` 키와 실제 기기에서 미리 보기를 쉽게 다운로드할 수 있도록 QR 코드 이미지의 URL이 포함된
`qrCodeURL` 키가 포함되어 있습니다. JSON 출력의 예는 아래와 같습니다:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
