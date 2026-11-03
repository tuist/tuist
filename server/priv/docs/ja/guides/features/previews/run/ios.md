---
{
  "title": "iPhoneアプリでプレビューを実行",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Tuist iOSアプリを使ってAppleのプレビューを検索、フィルタリング、アクセスします。"
}
---
# iPhoneアプリでプレビューを実行

[App StoreからTuist iOSアプリをインストール](https://apps.apple.com/us/app/tuist/id6748460335)して、Appleのプレビューを検索・アクセスしてください。公開ワークフローの署名とデバイス Eligibility の要件は引き続き適用されます。

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <img src="/images/guides/features/tuist-app.png" style="width: 220px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="App Storeでダウンロード" style="height: 40px;">
    </a>
</div>

アプリ名またはリリースノートで検索し、トラックを選択してプレビューをフィルタリングします。**すべて**を選択すると、トラックのないプレビューを含むすべてのトラックを閲覧できます。プレビューを開いて、完全なリリースノートを確認してください。

## クライアントとサーバーの互換性 {#client-and-server-compatibility}

Tuistアプリを最新の状態に保ってください。Tuistをセルフホストしている場合は、サーバーを更新してトラックフィルタリングとリリースノートを利用できるようにしてください。古いサーバーでも、フィルタリングなしでプレビューを閲覧できます。

## アプリ内更新通知 {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk)を使用すると、Appleアプリが新しいプレビューを検出してテスターに通知できます。同じ**プレビュートラック**内の更新をチェックします。`tuist share --track`で公開されたプレビューの場合、その明示的なトラックが使用されます。明示的なトラックがない場合はgitブランチが使用されるため、`main`からビルドされたプレビューは`main`からの新しいプレビューのみを通知します。

### インストール {#sdk-installation}

Swift Packageの依存関係としてTuist SDKを追加します:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 更新を監視 {#sdk-monitor-updates}

`monitorPreviewUpdates`を使用して、定期的に新しいプレビューバージョンをチェックします:

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

### 単一の更新チェック {#sdk-single-check}

手動で更新をチェックする場合:

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### 更新監視の停止 {#sdk-stop-monitoring}

`monitorPreviewUpdates`はキャンセル可能な`Task`を返します:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> 更新チェックは、シミュレーターおよびApp Storeビルドでは自動的に無効になります。
