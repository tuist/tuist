---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# プレビュー{#previews}

警告 要件
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuistアカウントとプロジェクト</LocalizedLink>
<!-- -->
:::

アプリを構築する際、フィードバックを得るために他者と共有したい場合があります。従来、チームはアプリをビルドし、署名し、Appleの[TestFlight](https://developer.apple.com/testflight/)などのプラットフォームにプッシュすることでこれを実現してきました。しかし、このプロセスは煩雑で時間がかかり、特に同僚や友人から迅速なフィードバックを得たい場合には不便です。

このプロセスをより効率化するため、Tuistではアプリのプレビューを生成し、誰でも共有できる機能を提供しています。

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
デバイス向けにビルドする際、アプリが正しく署名されていることを確認するのは現時点ではあなたの責任です。将来的にはこのプロセスを簡素化する予定です。
<!-- -->
:::

コードグループ
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

このコマンドは、シミュレータまたは実機でアプリを実行するための共有リンクを生成します。リンクを受け取った人は、以下のコマンドを実行するだけでアプリを実行できます：

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

`.ipa` ファイルを共有する場合、プレビューリンクからモバイルデバイスに直接アプリをダウンロードできます。`.ipa`
プレビューへのリンクはデフォルトで_private_
となっており、受信者はTuistアカウントで認証してアプリをダウンロードする必要があります。誰でもアプリを共有したい場合は、プロジェクト設定でこれを公開に変更できます。

`tuist run` は、`latest` などの指定子、ブランチ名、または特定のコミットハッシュに基づいて最新プレビューを実行することも可能です：

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
`CFBundleVersion` (ビルドバージョン)
が一意であることを保証するため、ほとんどのCIプロバイダーが公開しているCI実行番号を活用してください。例えばGitHub
Actionsでは、`CFBundleVersion` を <code v-pre>${{ github.run_number }}</code>
変数に設定できます。

同じバイナリ（ビルド）と同一の`CFBundleVersion` を持つプレビューのアップロードは失敗します。
<!-- -->
:::

## トラック{#tracks}

トラック機能により、プレビューを名前付きグループに整理できます。例えば、内部テスター向けには「`」ベータ版（`
）トラックを、自動ビルド向けには「`」ナイトリー版（`
）トラックを設定できます。トラックは遅延作成されます。共有時にトラック名を指定するだけで、存在しない場合は自動的に作成されます。

特定のトラックのプレビューを共有するには、`--track` オプションを使用してください：

```bash
tuist share App --track beta
tuist share App --track nightly
```

これは以下の場合に有用です：
- **プレビューの整理**: プレビューを目的別にグループ化（例：`beta`,`nightly`,`internal` ）
- **アプリ内更新**: Tuist SDKは、ユーザーに通知する更新内容を決定するためにトラックを使用します
- **** のフィルタリング：Tuistダッシュボードでトラック別にプレビューを簡単に検索・管理

::: warning PREVIEWS' VISIBILITY
<!-- -->
プロジェクトが属する組織へのアクセス権を持つ者のみがプレビューにアクセスできます。リンクの有効期限設定機能の追加を予定しています。
<!-- -->
:::

## Tuist macOS アプリ{#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Tuistプレビューの実行をさらに簡単にするため、Tuist macOSメニューバーアプリを開発しました。Tuist
CLI経由でプレビューを実行する代わりに、macOSアプリを[ダウンロード](https://tuist.dev/download)できます。また、以下のコマンドを実行してアプリをインストールすることも可能です：`brew
install --cask tuist/tuist/tuist`

プレビューページで「実行」をクリックすると、macOSアプリが自動的に選択中のデバイスで起動します。

警告 要件
<!-- -->
Xcodeをローカルにインストールし、macOS 14以降を使用している必要があります。
<!-- -->
:::

## Tuist iOSアプリ{#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

macOSアプリと同様に、Tuist iOSアプリではプレビューへのアクセスと実行が効率化されています。

## プル/マージリクエストのコメント{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
自動プルリクエスト/マージリクエストコメントを取得するには、<LocalizedLink href="/guides/server/accounts-and-projects">リモートプロジェクト</LocalizedLink>を<LocalizedLink href="/guides/server/authentication">Gitプラットフォーム</LocalizedLink>と連携させてください。
<!-- -->
:::

新機能のテストはコードレビューの一部であるべきです。しかし、アプリをローカルでビルドする必要性は不要な摩擦を生み、開発者がデバイス上での機能テストを完全に省略する原因となることが多々あります。*もし各プルリクエストに、Tuist
macOSアプリで選択したデバイス上でアプリを自動実行するビルドへのリンクが含まれていたらどうでしょうか？*

Tuistプロジェクトを[GitHub](https://github.com)などのGitプラットフォームと連携させたら、CIワークフローに<LocalizedLink href="/cli/share">`tuist
share
MyApp`</LocalizedLink>を追加してください。これによりTuistがプルリクエスト内にプレビューリンクを直接投稿します：![GitHubアプリへのTuistプレビューリンク付きコメント](/images/guides/features/github-app-with-preview.png)


## アプリ内更新通知{#in-app-update-notifications}

[Tuist
SDK](https://github.com/tuist/sdk)を使用すると、アプリは新しいプレビュー版が利用可能になったことを検出し、ユーザーに通知できます。これにより、テスターを最新のビルドに維持するのに役立ちます。

SDKは同じ**プレビュートラック内での更新を確認します** 。`--track`
で明示的なトラックを指定してプレビューを共有すると、SDKはそのトラックの更新を検索します。トラックが指定されていない場合、gitブランチがトラックとして使用されます。したがって、`main`
ブランチからビルドされたプレビューは、`main` からビルドされた新しいプレビューについてのみ通知します。

### インストール{#sdk-installation}

Tuist SDKをSwift Packageの依存関係として追加:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 更新を確認する{#sdk-monitor-updates}

`monitorPreviewUpdates` を定期的にチェックして新しいプレビュー版を確認してください:

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

### 単一更新チェック{#sdk-single-check}

手動での更新確認について：

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### 更新監視の停止{#sdk-stop-monitoring}

`monitorPreviewUpdates` は、キャンセル可能な`タスク` を返します:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

::: info
<!-- -->
シミュレータおよびApp Store向けビルドでは、更新チェックが自動的に無効化されます。
<!-- -->
:::

## README バッジ{#readme-badge}

リポジトリでTuist Previewsをより目立たせるには、`のREADMEファイルに、最新のTuist Previewを指すバッジを追加できます。`

[![Tuist
Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

`のREADMEにバッジを追加するには、` の以下のマークダウンを使用し、アカウント名とプロジェクト名を自身のものに変更してください：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

プロジェクトに異なるバンドルIDを持つ複数のアプリが含まれる場合、`bundle-id`
クエリパラメータを追加することで、リンク先のプレビュー対象アプリを指定できます:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 自動化{#automations}

`tuist share` コマンドから JSON 出力を取得するには、`--json` フラグを使用できます:
```
tuist share --json
```

JSON出力は、CIプロバイダーを使用したSlackメッセージ投稿など、カスタム自動化を作成するのに便利です。JSONには、プレビューリンク全体を含む```
URL（` キー）と、実機からプレビューを簡単にダウンロードできるようにするQRコード画像のURLを含む``` QRコードURL（`
キー）が含まれます。JSON出力の例は以下の通りです：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
