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
- A<LocalizedLink href="/guides/server/accounts-and-projects">トゥイストのアカウントとプロジェクト</LocalizedLink>
<!-- -->
:::

アプリを作るとき、他の人と共有してフィードバックを得たいと思うかもしれません。伝統的に、これはAppleの[TestFlight](https://developer.apple.com/testflight/)のようなプラットフォームにアプリをビルドし、署名し、プッシュすることによってチームが行うことです。しかし、このプロセスは面倒で時間がかかることがあり、特に同僚や友人からの素早いフィードバックを求めている場合はなおさらです。

このプロセスをより合理化するために、Tuistはアプリのプレビューを生成して誰とでも共有する方法を提供する。

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
デバイス用にビルドする場合、アプリが正しく署名されていることを確認するのは、現在のところお客様の責任です。将来的にはこれを合理化する予定です。
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

このコマンドを実行すると、シミュレーターでも実機でも、アプリを実行するためのリンクが生成される。必要なのは、以下のコマンドを実行することだけだ：

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

`.ipa` ファイルを共有する場合、プレビューリンクを使用してモバイルデバイスからアプリを直接ダウンロードできます。`.ipa`
プレビューへのリンクは、デフォルトでは_公開_
となっています。将来的には非公開にするオプションが追加され、リンクの受信者はアプリをダウンロードするためにTuistアカウントで認証する必要があります。

`tuist run` は、`latest` 、ブランチ名、特定のコミットハッシュなどの指定子に基づいて最新のプレビューを実行することもできます：

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
`CFBundleVersion` (ビルドバージョン) が一意であることを確認するには、ほとんどの CI プロバイダが公開している CI run number
を利用します。例えば、GitHub Actions では、`CFBundleVersion` を <code v-pre>${{
github.run_number }}</code> 変数に設定できます。

同じバイナリ（ビルド）と同じ`CFBundleVersion` を持つプレビューのアップロードは失敗します。
<!-- -->
:::

## トラック{#tracks}

トラックによって、プレビューを名前付きのグループに整理することができます。例えば、社内テスター用に`beta`
トラックを用意し、自動ビルド用に`nightly`
トラックを用意することができます。トラックは簡単に作成できます。共有時にトラック名を指定するだけで、存在しない場合は自動的に作成されます。

特定のトラックでプレビューを共有するには、`--track` オプションを使用します：

```bash
tuist share App --track beta
tuist share App --track nightly
```

これは次のような場合に役立つ：
- **プレビューの整理** ：目的別にプレビューをグループ化する（例：`ベータ版：` 、`夜間版：` 、`内部版：` ）。
- **アプリ内アップデート** ：Tuist SDKは、どのアップデートをユーザーに通知するかを決定するためにトラックを使用します。
- **フィルタリング** ：Tuistのダッシュボードでトラックごとのプレビューを簡単に検索・管理できる

::: warning PREVIEWS' VISIBILITY
<!-- -->
プレビューにアクセスできるのは、プロジェクトが所属する組織にアクセスできる人だけです。期限切れリンクのサポートを追加する予定です。
<!-- -->
:::

## TuistのmacOSアプリ{#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Tuist Previewsの実行をさらに簡単にするために、我々はTuist macOSメニューバーアプリを開発した。Tuist
CLI経由でプレビューを実行する代わりに、macOSアプリを[ダウンロード](https://tuist.dev/download)することができる。`brew
install --cask tuist/tuist/tuist` を実行してアプリをインストールすることもできます。

プレビューページで「実行」をクリックすると、macOSアプリが現在選択されているデバイス上で自動的に起動します。

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

macOSアプリと同様に、Tuist iOSアプリはプレビューへのアクセスと実行を効率化します。

## プル/マージリクエストのコメント{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
プル/マージリクエストのコメントを自動的に取得するには、<LocalizedLink href="/guides/server/accounts-and-projects">リモートプロジェクト</LocalizedLink>と<LocalizedLink href="/guides/server/authentication">Gitプラットフォーム</LocalizedLink>を統合します。
<!-- -->
:::

新しい機能のテストは、あらゆるコードレビューの一部であるべきだ。しかし、アプリをローカルでビルドしなければならないことは、不必要な摩擦を増やし、開発者が自分のデバイスで機能をテストすることをスキップしてしまうことになりがちだ。しかし、*、各プルリクエストに、Tuist
macOSアプリで選択したデバイス上でアプリを自動的に実行するビルドへのリンクが含まれていたらどうだろう？*

Tuistプロジェクトが[GitHub](https://github.com)などのGitプラットフォームと接続されたら、CIワークフローに<LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink>を追加します。するとTuistはプルリクエストに直接プレビューリンクを投稿します: ![GitHub
app comment with a Tuist Preview
link](/images/guides/features/github-app-with-preview.png).


## アプリ内アップデート通知{#in-app-update-notifications}

Tuist
SDK](https://github.com/tuist/sdk)を使用すると、新しいプレビュー版が利用可能になったことをアプリが検出し、ユーザーに通知することができます。これはテスターを最新ビルドに保つのに便利です。

SDKは、同じ**プレビュートラック** 内の更新をチェックします。`--track` を使ってプレビューを明示的なトラックと共有すると、SDK
はそのトラックの更新を探します。トラックが指定されていない場合は、git ブランチがトラックとして使用されます。そのため、`main`
ブランチからビルドされたプレビューは、`main` からビルドされた新しいプレビューについてのみ通知されます。

### インストール{#sdk-installation}

Swift Packageの依存関係としてTuist SDKを追加する：

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### アップデートを監視する{#sdk-monitor-updates}

`monitorPreviewUpdates` を使用して、新しいプレビュー・バージョンを定期的にチェックしてください：

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

### シングル・アップデート・チェック{#sdk-single-check}

手動更新チェック用：

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### アップデート監視の停止{#sdk-stop-monitoring}

`monitorPreviewUpdates` ` キャンセル可能なタスク` を返す：

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

::: info
<!-- -->
アップデートチェックは、シミュレータおよびApp Storeビルドでは自動的に無効になります。
<!-- -->
:::

## READMEバッジ{#readme-badge}

Tuistプレビューをリポジトリでより見やすくするために、`README` ファイルに最新のTuistプレビューを指すバッジを追加することができます：

[トゥイスト・プレビュー](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)。

`README` にバッジを追加するには、以下のマークダウンを使用し、アカウントとプロジェクトのハンドルを独自のものに置き換えてください：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

プロジェクトに異なるバンドル識別子を持つ複数のアプリが含まれている場合、`bundle-id`
クエリパラメータを追加することで、どのアプリのプレビューにリンクするかを指定できます：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## オートメーション{#automations}

`--json` フラグを使えば、`tuist share` コマンドからJSON出力を得ることができる：
```
tuist share --json
```

JSON出力は、CIプロバイダを使用してSlackメッセージを投稿するなどのカスタム自動化を作成するのに便利です。JSONには、`url`
キーにプレビューのフルリンク、`qrCodeURL`
キーにQRコード画像のURLが含まれており、実際のデバイスからプレビューをダウンロードしやすくなっています。JSON出力の例を以下に示す：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
