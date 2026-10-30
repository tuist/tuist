---
{
  "title": "プレビュー",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Previews で iOS および Android アプリのビルドを即座に共有。TestFlight や Play Console の設定不要で、チームメンバーやステークホルダーにリンクを提供できます。"
}
---
# プレビュー {#previews}

Tuist Previews を使うと、アプリのプレビューを生成して共有できるため、チームメンバーはローカルで再ビルドせずにビルドをテストできます。

アプリをビルドする際、フィードバックを得るために他者と共有したいことがあるでしょう。従来、チームは Apple の [TestFlight](https://developer.apple.com/testflight/) などのプラットフォームにアプリをビルド、署名、プッシュすることでこれを行っていました。しかし、このプロセスは煩雑で時間がかかることが多く、同僚や友人から素早いフィードバックを得たい場合には特に負担になります。

このプロセスをよりスムーズにするため、Tuist はアプリのプレビューを生成し、誰でも共有できる手段を提供します。

> [!WARNING]
> **デバイス向けビルドには署名が必要です**
>
> デバイス向けにビルドする場合、アプリが正しく署名されていることを確認するのは現時点ではあなたの責任です。将来的にはこの手順を簡素化する予定です。

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

コマンドを実行すると、シミュレータまたは実機のいずれかでアプリを実行するためのリンクが生成され、誰とでも共有できます。相手が必要なのは、以下のコマンドを実行することだけです。

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

`.ipa` ファイルを共有する場合、プレビューリンクを使ってモバイルデバイスから直接アプリをダウンロードできます。`.ipa` プレビューへのリンクはデフォルトで _非公開_ であり、受信者はアプリをダウンロードするために Tuist アカウントで認証する必要があります。アプリを誰でも共有したい場合は、プロジェクト設定で公開に変更できます。

`tuist run` を使うと、`latest`、ブランチ名、特定のコミットハッシュなどの指定子に基づいて最新のプレビューを実行することもできます。

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **CI での一意なビルド番号**
>
> ほとんどの CI プロバイダーが公開している CI 実行番号を活用して、`CFBundleVersion`（ビルドバージョン）が一意であることを確認してください。たとえば、GitHub Actions では `CFBundleVersion` を <code v-pre>${{ github.run_number }}</code> 変数に設定できます。 
>
> 同じバイナリ（ビルド）と同じ `CFBundleVersion` でプレビューをアップロードすると失敗します。

## トラック {#tracks}

トラックを使うと、プレビューを名前付きのグループに整理できます。たとえば、内部テスター向けの `beta` トラックや、自動ビルド向けの `nightly` トラックを用意できます。トラックは遅延作成されます。共有時にトラック名を指定するだけで、存在しない場合は自動的に作成されます。

特定のトラックでプレビューを共有するには、`--track` オプションを使用します。

```bash
tuist share App --track beta
tuist share App --track nightly
```

これは次のような場合に役立ちます。
- **プレビューの整理**: 目的ごとにプレビューをグループ化します（例: `beta`、`nightly`、`internal`）
- **アプリ内アップデート**: Tuist SDK はトラックを使用して、ユーザーに通知するアップデートを決定します
- **フィルタリング**: Tuist ダッシュボードでトラックごとにプレビューを簡単に見つけて管理できます

> [!WARNING]
> **プレビューの公開範囲**
>
> プロジェクトが所属する組織へのアクセス権を持つ人だけがプレビューにアクセスできます。期限切れリンクのサポート追加を予定しています。

## リリースノート {#release-notes}

環境グループにはトラックを、個別のビルドの目的にはリリースノートを使用します。

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

リリースノートは任意のプレーンテキストで、最大 10,000 文字です。最初の空白でない行が Web および iOS のプレビュー一覧で単行スニペットとして表示されるため、ビルド番号やその他の識別情報がひと目で確認できます。長い行は切り詰められ、詳細ページに全文が表示されます。両方のリストでの検索は、表示名と完全なリリースノートに一致し、スニペットに表示されていない行も対象になります。複数行のノートもサポートされており、たとえば `--release-notes "$(< release-notes.txt)"` のように指定できます。これらはアプリの表示名やトラックを変更しません。

### 互換性 {#preview-metadata-compatibility}

リリースノートは付加的なメタデータであり、プレビューの識別情報ではありません。古いクライアントと新しいクライアントからのアップロードは、プラットフォーム間で同じプレビューにグループ化されます。最初の空白でないノートは保持されます。後続のアップロードで以前なかったノートを埋めることはできますが、既存のノートを上書きすることはできません。`release_notes` を省略するか、`null` を送信するか、空または空白のみの文字列を送信しても、ノートはクリアされません。既存のプレビューには後からノートが埋め込まれず、ノートなしでも有効です。

リスト API のオプションの `track` クエリパラメータは、大文字小文字を区別せずトラック名全体に一致し、既存のトラック保存と整合しています。これを省略するか空の値（`?track=`）を送信すると、すべてのトラックが一覧表示されます。トラック名は固定された値のリストではなく、オープンな文字列のままです。iOS アプリの **すべてのトラック** 選択ではフィルターが省略されます。iOS アプリのトラックピルは、ビルド一覧と同じプレビュー読み取り権限のもとで `GET /api/projects/:account_handle/:project_handle/previews/tracks` から完全なプロジェクト概要を読み込みます。そのエンドポイントは `{total_count, tracks: [{name, count}]}` を返し、ソートされ、大文字小文字を区別せずにグループ化された名前付きトラックが含まれます。カウントはページネーション、検索、選択されたトラックとは独立してプロジェクト全体を対象とし、合計にはトラック未設定のプレビューも含まれます。バンドル識別子を持つ一覧可能なプレビューのみがカウントされます。リスト API はまた、表示名または完全なリリースノートのリテラルで大文字小文字を区別しない部分文字列に対するオプションの `search` も受け付け、ページネーション前にトラックと組み合わされます。既存の `display_name` フィルタリングは完全一致のままです。

古いクライアントは、いずれのフィールドも送信せずにプレビューのアップロードと一覧取得を継続できます。新しいクライアントは、トラックやノートを省略した古いレスポンスを受け入れ、将来のサーバーによって追加された未知のレスポンスプロパティを無視します。API 統合も同様に未知のレスポンスプロパティを無視し、付加的なメタデータの互換性を維持すべきです。

セルフホスト構成でこれらの機能を使用するには、リリースノートとトラックフィルタリングをサポートするサーバーバージョンと、更新された CLI およびアプリが必要です。古いサーバーはノートや未知のクエリパラメータを無視する場合があります。トラック検出が利用できない場合、iOS アプリはフィルターなしの閲覧を維持し、トラックの選択には更新されたサーバーが必要であることを説明します。アクティブなフィルターがあるにもかかわらずサーバーが別のトラックのプレビューを返す場合、iOS アプリは誤解を招く結果を表示するのではなく、フィルタリングがサポートされていないことを報告します。macOS アプリはまずアプリごとに最新の互換性のあるプレビューをリクエストします。プラットフォームフィルターを適用する前に個別のアプリを選択する古いサーバーでは、利用可能なビルドを隠してしまうカットオフを課さずに、ページネーションされた履歴にフォールバックします。

## Tuist macOS アプリ {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Tuist Previews の実行をさらに簡単にするため、Tuist macOS メニューバーアプリを開発しました。Tuist CLI 経由でプレビューを実行する代わりに、macOS アプリを [ダウンロード](https://tuist.dev/download) できます。また、`brew install --cask tuist/tuist/tuist` を実行してアプリをインストールすることもできます。

プレビューページで「Run」をクリックすると、macOS アプリが現在選択されているデバイスで自動的にアプリを起動します。

## Tuist iOS アプリ {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="App Store でダウンロード" style="height: 40px;">
    </a>
</div>

macOS アプリと同様に、Tuist iOS アプリはプレビューへのアクセスと実行を効率化します。各プレビューにはトラックが表示されます。ネイティブの検索フィールドを使用してアプリ名でプレビューを検索し、**Tracks** 下のピルを選択して環境でフィルタリングします。選択されたピルは紫色になります。トラックフィルターを解除するには **All** を選択してください。各ピルにはプロジェクト全体のプレビュー数が表示され、All にはトラックのないビルドも含まれます。検索とトラックによるフィルタリングはページ全体に適用され、すでに読み込まれたプレビューだけでなく、すべてのページにわたって機能します。各ビルドのトラックタグはコミットハッシュの隣に表示されます。

## プル/マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Git プラットフォームとの統合が必要です**
>
> プル/マージリクエストに自動的にコメントを追加するには、<.localized_link href="/guides/server/accounts-and-projects">リモートプロジェクト</.localized_link> を <.localized_link href="/guides/server/authentication">Git プラットフォーム</.localized_link> と統合してください。

新機能のテストはコードレビューの一部であるべきです。しかし、ローカルでアプリをビルドする必要があると不要な摩擦が生じ、開発者がデバイスでの機能テストを完全にスキップしてしまうことがよくあります。*もし、各プルリクエストに、Tuist macOS アプリで選択したデバイスで自動的にアプリを実行するビルドへのリンクが含まれていたらどうでしょうか？*

Tuist プロジェクトが [GitHub](https://github.com) などの Git プラットフォームと接続されたら、CI ワークフローに <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link> を追加してください。Tuist はプルリクエストに直接プレビューリンクを投稿します: ![Tuist プレビューリンクを含む GitHub アプリのコメント](/images/guides/features/github-app-with-preview.png)

## アプリ内更新通知 {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) を使用すると、新しいプレビューバージョンが利用可能になったことを検出してユーザーに通知できます。これはテスターを最新のビルドに維持するのに役立ちます。

SDK は同じ **プレビュートラック** 内で更新を確認します。`--track` を使用して明示的なトラックを指定してプレビューを共有すると、SDK はそのトラックの更新を探します。トラックが指定されていない場合、git ブランチがトラックとして使用されます。つまり、`main` ブランチからビルドされたプレビューは、`main` からビルドされた新しいプレビューのみを通知します。

### インストール {#sdk-installation}

Tuist SDK を Swift Package の依存関係として追加します:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 更新の監視 {#sdk-monitor-updates}

`monitorPreviewUpdates` を使用して、新しいプレビューバージョンを定期的に確認します:

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

手動で更新を確認する場合:

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

`monitorPreviewUpdates` はキャンセル可能な `Task` を返します:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> シミュレーターおよび App Store ビルドでは、更新チェックは自動的に無効になります。

## README バッジ {#readme-badge}

リポジトリで Tuist Previews をより目立たせるために、最新の Tuist プレビューを指すバッジを `README` ファイルに追加できます:

[![Tuist プレビュー](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

バッジを `README` に追加するには、以下の Markdown を使用し、アカウントハンドルとプロジェクトハンドルを自分のものに置き換えてください:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

プロジェクトに異なるバンドル識別子を持つ複数のアプリが含まれている場合、`bundle-id` クエリパラメータを追加することで、どのアプリのプレビューにリンクするかを指定できます:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 自動化 {#automations}

`--json` フラグを使用して、`tuist share` コマンドから JSON 出力を取得できます:
```
tuist share --json
```

JSON 出力は、CI プロバイダーを使用して Slack メッセージを投稿するなど、カスタム自動化を作成するのに役立ちます。JSON には、完全なプレビューリンクを含む `url` キーと、QR コード画像の URL を含む `qrCodeURL` キーが含まれており、実機からプレビューをダウンロードしやすくします。JSON 出力の例を以下に示します:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
