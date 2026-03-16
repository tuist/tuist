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

アプリを開発する際、フィードバックを得るために他の人と共有したいと思うことがあるでしょう。従来、チームはアプリをビルドし、署名を行い、Appleの[TestFlight](https://developer.apple.com/testflight/)のようなプラットフォームにプッシュすることでこれを行ってきました。しかし、特に同僚や友人から手っ取り早くフィードバックを得たい場合、このプロセスは煩雑で時間がかかることがあります。

このプロセスをより効率化するため、Tuistではアプリのプレビューを生成し、誰とでも共有できる機能を提供しています。

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
デバイス向けにビルドする際、アプリが正しく署名されていることを確認するのは、現時点ではユーザーの責任となります。将来的にはこのプロセスを簡素化する予定です。
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

このコマンドを実行すると、シミュレータまたは実機でアプリを実行するためのリンクが生成され、誰とでも共有できます。共有先では、以下のコマンドを実行するだけで利用可能です：

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

`.ipa` ファイルを共有する場合、プレビューリンクを使用してモバイルデバイスから直接アプリをダウンロードできます。`.ipa`
プレビューへのリンクは、デフォルトで_private_ 設定になっており、受信者はアプリをダウンロードするために Tuist
アカウントで認証を行う必要があります。アプリを誰でも共有したい場合は、プロジェクト設定でこれを public に変更できます。

`tuist run` を使用すると、`latest`
のような指定子、ブランチ名、または特定のコミットハッシュに基づいて、最新のプレビューを実行することもできます:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
`CFBundleVersion`
（ビルドバージョン）が一意になるよう、ほとんどのCIプロバイダーが公開しているCI実行番号を活用してください。たとえば、GitHub
Actionsでは、`CFBundleVersion` を <code v-pre>${{ github.run_number }}</code>
変数に設定できます。

同じバイナリ（ビルド）および同じ`CFBundleVersion` を持つプレビューをアップロードしようとすると、失敗します。
<!-- -->
:::

## トラック{#tracks}

トラックを使用すると、プレビューを名前付きのグループに整理できます。たとえば、社内テスター向けの「`beta`
」トラックや、自動ビルド向けの「`nightly`
」トラックを作成できます。トラックは遅延生成されます。共有時にトラック名を指定するだけで、存在しない場合は自動的に作成されます。

特定のトラックのプレビューを共有するには、`--track` オプションを使用してください:

```bash
tuist share App --track beta
tuist share App --track nightly
```

これは次のような場合に役立ちます：
- **プレビューの整理**: プレビューを目的別にグループ化してください（例：`beta`,`nightly`,`internal` ）
- **アプリ内アップデート**: Tuist SDKは、ユーザーに通知するアップデートを決定するために「トラック」を使用します
- **** のフィルタリング：Tuistダッシュボードでトラックごとのプレビューを簡単に検索・管理

::: warning PREVIEWS' VISIBILITY
<!-- -->
プレビューにアクセスできるのは、プロジェクトが所属する組織のメンバーのみです。リンクの有効期限設定機能の追加を予定しています。
<!-- -->
:::

## Tuist macOSアプリ{#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Tuist Previewsの実行をさらに簡単にするため、Tuist macOSメニューバーアプリを開発しました。Tuist
CLI経由でPreviewsを実行する代わりに、macOSアプリを[ダウンロード](https://tuist.dev/download)できます。また、`brew
install --cask tuist/tuist/tuist` を実行してアプリをインストールすることもできます。

プレビューページで「実行」をクリックすると、macOSアプリが現在選択されているデバイス上で自動的に起動します。

警告 要件
<!-- -->
Xcodeがローカルにインストールされており、macOS 14以降が動作している必要があります。
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

macOSアプリと同様に、TuistのiOSアプリもプレビューへのアクセスと実行を効率化します。

## プル/マージリクエストのコメント{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
プルリクエストやマージリクエストのコメントを自動生成するには、<LocalizedLink href="/guides/server/accounts-and-projects">リモートプロジェクト</LocalizedLink>を<LocalizedLink href="/guides/server/authentication">Gitプラットフォーム</LocalizedLink>と連携させてください。
<!-- -->
:::

新機能のテストは、あらゆるコードレビューの一部であるべきです。しかし、ローカルでアプリをビルドしなければならないことは、不必要な手間となり、開発者が自身のデバイスでの機能テストを完全に省略してしまうことにつながりがちです。しかし、*もし各プルリクエストに、Tuist
macOSアプリで選択したデバイス上でアプリを自動的に実行するビルドへのリンクが含まれていたらどうでしょうか？*

Tuistプロジェクトを[GitHub](https://github.com)などのGitプラットフォームに接続したら、CIワークフローに
<LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink>
を追加してください。これにより、Tuistがプルリクエストにプレビューリンクを直接投稿します:
![Tuistプレビューリンク付きのGitHubアプリコメント](/images/guides/features/github-app-with-preview.png)


## アプリ内アップデート通知{#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk)
を使用すると、アプリは新しいプレビュー版が利用可能になったことを検出し、ユーザーに通知できます。これは、テスターを最新のビルドに維持するのに役立ちます。

SDKは、同じ**プレビュートラック内（** ）で更新を確認します。`--track`
を使用して特定のトラックを指定してプレビューを共有すると、SDKはそのトラックで更新を確認します。トラックが指定されていない場合、gitブランチがトラックとして使用されます。つまり、`main`
ブランチからビルドされたプレビューは、`main` からビルドされた新しいプレビューについてのみ通知します。

### インストール{#sdk-installation}

Tuist SDK を Swift パッケージの依存関係として追加します:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 更新情報を確認してください{#sdk-monitor-updates}

`monitorPreviewUpdates` を使用して、新しいプレビュー版を定期的に確認してください：

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

### 単一の更新チェック{#sdk-single-check}

手動での更新確認については：

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### 更新の監視を停止する{#sdk-stop-monitoring}

`monitorPreviewUpdates` は、キャンセル可能な`Task` を返します:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

::: info
<!-- -->
シミュレータおよびApp Storeビルドでは、更新チェックは自動的に無効になります。
<!-- -->
:::

## README バッジ{#readme-badge}

リポジトリ内で Tuist Previews をより目立たせるには、`の README ファイル（` ）に、最新の Tuist Preview
へのリンクを含むバッジを追加してください：

[![Tuist
プレビュー](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

`のREADME` にバッジを追加するには、以下のマークダウンを使用し、アカウント名とプロジェクト名を自分のものに置き換えてください：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

プロジェクトに異なるバンドルIDを持つ複数のアプリが含まれている場合、`bundle-id`
というクエリパラメータを追加することで、リンク先のアプリのプレビューを指定できます:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 自動化{#automations}

``--json`` フラグを使用すると、``tuist share`` コマンドから JSON 形式の出力を取得できます:
```
tuist share --json
```

このJSON出力は、CIプロバイダーを使用してSlackメッセージを投稿するなど、カスタム自動化を作成する際に役立ちます。JSONには、プレビューの完全なリンクを含む`（`
）キーと、実際のデバイスからプレビューを簡単にダウンロードできるようにするためのQRコード画像のURLを含む`（qrCodeURL：`
）キーが含まれています。JSON出力の例は以下の通りです：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
