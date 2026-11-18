---
{
  "title": "iPhone 앱으로 프리뷰 실행하기",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Tuist iOS 앱으로 Apple 프리뷰를 찾고, 필터링하고, 접근하세요."
}
---
# iPhone 앱으로 프리뷰 실행하기

[앱 스토어에서 Tuist iOS 앱 설치](https://apps.apple.com/us/app/tuist/id6748460335)하여 Apple 프리뷰를 찾고 액세스하세요. 게시 워크플로의 서명 및 장치 자격 요건은 여전히 적용됩니다.

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <img src="/images/guides/features/tuist-app.png" style="width: 220px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="앱 스토어에서 다운로드" style="height: 40px;">
    </a>
</div>

앱 이름 또는 릴리스 노트로 검색한 후, 트랙을 선택하여 프리뷰를 필터링하세요. **모두**를 선택하면 트랙이 없는 프리뷰를 포함하여 모든 트랙의 프리뷰를 탐색할 수 있습니다. 프리뷰를 열어 전체 릴리스 노트를 읽어보세요.

## 클라이언트와 서버 호환성 {#client-and-server-compatibility}

Tuist 앱을 최신 상태로 유지하세요. Tuist를 자체 호스팅하는 경우, 트랙 필터링과 릴리스 노트를 사용하도록 서버를 업데이트하세요. 이전 버전의 서버에서도 필터링 없이 프리뷰를 계속 탐색할 수 있습니다.

## 인앱 업데이트 알림 {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk)를 사용하면 Apple 앱에서 더 새로운 프리뷰를 감지하고 테스터에게 알릴 수 있습니다. 동일한 **프리뷰 트랙** 내에서 업데이트를 확인합니다. `tuist share --track`으로 게시된 프리뷰의 경우 명시적으로 지정된 트랙을 사용합니다. 명시적인 트랙이 없으면 git 브랜치가 사용되므로, `main`에서 빌드된 프리뷰는 `main`의 더 새로운 프리뷰에 대해서만 알림을 보냅니다.

### 설치 {#sdk-installation}

Tuist SDK를 Swift Package 의존성으로 추가하세요:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 업데이트 모니터링 {#sdk-monitor-updates}

`monitorPreviewUpdates`를 사용하여 새 프리뷰 버전을 주기적으로 확인하세요:

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

수동으로 업데이트를 확인하려면:

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
> 시뮬레이터와 앱 스토어 빌드에서는 업데이트 확인이 자동으로 비활성화됩니다.
