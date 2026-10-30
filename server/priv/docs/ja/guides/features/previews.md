---
{
  "title": "プレビュー",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Previews で iOS および Android アプリのビルドを即座に共有。TestFlight や Play Console の設定不要で、チームメンバーやステークホルダーにリンクを提供できます。"
}
---
# Previews {#previews}

Tuist Previews を使えば、アプリのプレビューを生成して共有でき、チームメンバーはローカルで再ビルドせずにビルドをテストできます。

アプリをビルドする際、フィードバックを得るために他の人と共有したいことがあるでしょう。従来、チームはアプリをビルドし、署名して、Apple の [TestFlight](https://developer.apple.com/testflight/) などのプラットフォームにプッシュすることでこれを行ってきました。しかし、このプロセスは煩雑で時間がかかることが多く、特に同僚や友人から迅速なフィードバックを得たい場合には負担になります。

このプロセスをより効率化するため、Tuist はアプリのプレビューを生成して誰でも共有できる方法を提供します。

> [!WARNING]
> **デバイス向けビルドには署名が必要です**
>
> デバイス向けにビルドする場合、アプリが正しく署名されていることを確認するのは現時点ではあなたの責任です。将来的にはこれを簡素化する予定です。

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

コマンドを実行すると、シミュレーターまたは実機でアプリを実行するためのリンクが生成され、それを誰とでも共有できます。共有先が行う必要があるのは、以下のコマンドを実行することだけです。

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

`.ipa` ファイルを共有する場合、プレビューリンクを使ってモバイルデバイスから直接アプリをダウンロードできます。`.ipa` プレビューへのリンクはデフォルトで _非公開_ であり、受信者はアプリをダウンロードするために Tuist アカウントで認証する必要があります。アプリを誰でも共有したい場合は、プロジェクト設定でこれを公開に変更できます。

`tuist run` では、`latest`、ブランチ名、または特定のコミットハッシュなどの指定子に基づいて最新のプレビューを実行することもできます。

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **CI での一意のビルド番号**
>
> ほとんどの CI プロバイダーが公開している CI 実行番号を活用して、`CFBundleVersion`（ビルドバージョン）が一意であることを確認してください。例えば、GitHub Actions では、`CFBundleVersion` を <code v-pre>${{ github.run_number }}</code> 変数に設定できます。 
>
> 同じバイナリ（ビルド）と同じ `CFBundleVersion` でプレビューをアップロードすると失敗します。

## Tracks {#tracks}

Tracks を使うと、プレビューを名前付きのグループに整理できます。例えば、内部テスター用の `beta` track や、自動ビルド用の `nightly` track を設けることができます。Track は遅延作成されます。共有時に track 名を指定するだけで、存在しない場合は自動的に作成されます。

特定の track でプレビューを共有するには、`--track` オプションを使用します。

```bash
tuist share App --track beta
tuist share App --track nightly
```

これは以下のような場合に役立ちます。
- **プレビューの整理**：目的別にプレビューをグループ化します（例：`beta`、`nightly`、`internal`）
- **アプリ内アップデート**：Tuist SDK は track を使用して、ユーザーに通知するアップデートを決定します
- **フィルタリング**：Tuist ダッシュボードで track ごとにプレビューを簡単に見つけて管理できます

> [!WARNING]
> **プレビューの公開範囲**
>
> プロジェクトが所属する組織へのアクセス権を持つ人だけがプレビューにアクセスできます。期限付きリンクのサポートを追加する予定です。

## リリースノート {#release-notes}

環境グループには track を使用し、個別のビルドの目的にはリリースノートを使用します。

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

リリースノートは任意のプレーンテキストで、最大 10,000 文字まで指定できます。最初の空白でない行は、Web および iOS のプレビューリストで一行スニペットとして表示されるため、ビルド番号やその他の識別情報が一目で確認できます。長い行は切り詰められ、詳細ページに全文が表示されます。両方のリストでの検索は、表示名と完全なリリースノート（スニペットに表示されていない行を含む）に一致します。複数行のノートもサポートされており、例えば `--release-notes "$(< release-notes.txt)"` のように指定できます。これらはアプリの表示名や track を変更しません。

### 互換性 {#preview-metadata-compatibility}

リリースノートは追加的なメタデータであり、プレビューの識別情報ではありません。新旧のクライアントからのアップロードは、プラットフォーム間で同じプレビューにグループ化されます。最初の空白でないノートは保持されます。後からのアップロードで以前なかったノートを埋めることはできますが、既存のノートを上書きすることはできません。`release_notes` を省略したり、`null` を送信したり、空または空白のみの文字列を送信しても、ノートがクリアされることはありません。既存のプレビューには後付けされず、ノートなしでも有効です。

リスト API のオプションの `track` クエリパラメータは、大文字小文字を区別せずに track 名全体と一致し、既存の track ストレージと整合しています。これを省略するか空の値（`?track=`）を送信すると、すべての track がリストされます。track 名は固定された値のリストではなく、オープンな文字列のままです。iOS アプリの **All Tracks** 選択ではフィルターが省略されます。iOS アプリの track ピルは、ビルド一覧と同じプレビュー読み取り権限の下で、`GET /api/projects/:account_handle/:project_handle/previews/tracks` から完全なプロジェクト概要を読み込みます。そのエンドポイントは、ソートされ、大文字小文字を区別せずにグループ化された名前付き track を持つ `{total_count, tracks: [{name, count}]}` を返します。カウントはページネーション、検索、選択された track とは独立してプロジェクト全体を対象とし、合計には track 未設定のプレビューも含まれます。バンドル識別子を持つリスト可能なプレビューのみがカウントされます。リスト API は、表示名または完全なリリースノートのリテラルで大文字小文字を区別しない部分文字列に対するオプションの `search` も受け付け、ページネーションの前に track と組み合わされます。既存の `display_name` フィルタリングは完全一致のままです。

古いクライアントは、どちらのフィールドも送信せずにプレビューのアップロードとリスト表示を続けることができます。新しいクライアントは、track やノートを省略した古いレスポンスを受け入れ、将来のサーバーによって追加された不明なレスポンスプロパティを無視します。API 統合も同様に不明なレスポンスプロパティを無視すべきであり、追加的なメタデータの互換性が保たれます。

セルフホスト型のデプロイメントでは、これらの機能を使用するために、リリースノートと track フィルタリングをサポートするサーバーバージョンと、更新された CLI およびアプリが必要です。古いサーバーはノートや不明なクエリパラメータを無視する可能性があります。track 検出が利用できない場合、iOS アプリはフィルターなしの閲覧を利用可能にし、track の選択には更新されたサーバーが必要であることを説明します。アクティブなフィルターにもかかわらずサーバーが別の track のプレビューを返す場合、iOS アプリは誤解を招く結果を表示するのではなく、フィルタリングがサポートされていないことを報告します。macOS アプリはまずアプリごとに最新の互換性のあるプレビューを要求します。プラットフォームフィルターを適用する前に個別のアプリを選択する古いサーバーでは、利用可能なビルドを隠してしまうようなカットオフを課さずに、ページネーションされた履歴にフォールバックします。

## Tuist macOS アプリ {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Tuist Previews の実行をさらに簡単にするために、Tuist macOS メニューバーアプリを開発しました。Tuist CLI を介して Previews を実行する代わりに、macOS アプリを [ダウンロード](https://tuist.dev/download) できます。また、`brew install --cask tuist/tuist/tuist` を実行してアプリをインストールすることもできます。

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

macOS アプリと同様に、Tuist iOS アプリはプレビューへのアクセスと実行を簡素化します。各プレビューにはその track が表示されます。ネイティブの検索フィールドを使用してアプリ名でプレビューを検索し、**Tracks** 下のピルを選択して環境でフィルタリングします。選択されたピルは紫色になります。track フィルターを解除するには **All** を選択してください。各ピルにはプロジェクト全体のプレビュー数が表示され、All には track がないビルドも含まれます。検索と track フィルタリングは、すでに読み込まれたプレビューだけでなく、ページ全体に適用されます。各ビルドの track タグはコミットハッシュの隣に表示されます。

## プル/マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Git プラットフォームとの統合が必要**
>
> 自動的なプル/マージリクエストのコメントを取得するには、<.localized_link href="/guides/server/accounts-and-projects">リモートプロジェクト</.localized_link> を <.localized_link href="/guides/server/authentication">Git プラットフォーム</.localized_link> と統合してください。

新機能のテストはコードレビューの一部であるべきです。しかし、アプリをローカルでビルドする必要があることは不要な摩擦を生み、開発者がデバイスでの機能テストを完全にスキップしてしまう原因となることがよくあります。しかし、*もし各プルリクエストに、Tuist macOS アプリで選択したデバイスで自動的にアプリを実行するビルドへのリンクが含まれていたらどうでしょうか？*

Tuist プロジェクトが [GitHub](https://github.com) などの Git プラットフォームと接続されたら、CI ワークフローに <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link> を追加してください。Tuist はその後、プルリクエストに直接プレビューリンクを投稿します：![Tuist プレビューリンクを含む GitHub アプリのコメント](/images/guides/features/github-app-with-preview.png)

## アプリ内更新通知 {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) は、新しいプレビューバージョンが利用可能になったことをアプリが検出し、ユーザーに通知することを可能にします。これはテスターを最新のビルドに維持するのに役立ちます。

SDK は同じ **プレビュー track** 内で更新を確認します。`--track` を使用して明示的な track でプレビューを共有すると、SDK はその track の更新を探します。track が指定されていない場合、git ブランチが track として使用されます。つまり、`main` ブランチからビルドされたプレビューは、`main` からビルドされた新しいプレビューについてのみ通知します。

### インストール {#sdk-installation}

Tuist SDK を Swift Package の依存関係として追加します：

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 更新の監視 {#sdk-monitor-updates}

`monitorPreviewUpdates` を使用して、新しいプレビューバージョンを定期的に確認します：

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

手動で更新を確認する場合：

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

`monitorPreviewUpdates` はキャンセル可能な `Task` を返します：

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> 更新チェックは、シミュレーターおよび App Store ビルドでは自動的に無効になります。

## README バッジ {#readme-badge}

リポジトリで Tuist Previews をより目立たせるために、最新の Tuist Preview へのリンクを含むバッジを `README` ファイルに追加できます：

[![Tuist プレビュー](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

バッジを `README` に追加するには、以下の Markdown を使用し、アカウントハンドルとプロジェクトハンドルを自分のものに置き換えてください：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

プロジェクトに異なるバンドル識別子を持つ複数のアプリが含まれている場合、`bundle-id` クエリパラメータを追加することで、どのアプリのプレビューにリンクするかを指定できます：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 自動化 {#automations}

`--json` フラグを使用して、`tuist share` コマンドから JSON 出力を取得できます：
```
tuist share --json
```

JSON 出力は、CI プロバイダーを使用して Slack メッセージを投稿するなど、カスタム自動化を作成するのに役立ちます。JSON には、完全なプレビューリンクを含む `url` キーと、実機からプレビューをダウンロードしやすくするための QR コード画像の URL を含む `qrCodeURL` キーが含まれています。JSON 出力の例を以下に示します：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
