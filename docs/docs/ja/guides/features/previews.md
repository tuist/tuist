---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# プレビュー

> [重要】要件
> - A<LocalizedLink href="/guides/server/accounts-and-projects">トゥイストのアカウントとプロジェクト</LocalizedLink>

アプリを作るとき、他の人と共有してフィードバックを得たいと思うかもしれません。伝統的に、これはAppleの[TestFlight](https://developer.apple.com/testflight/)のようなプラットフォームにアプリをビルドし、署名し、プッシュすることによってチームが行うことです。しかし、このプロセスは面倒で時間がかかることがあり、特に同僚や友人からの素早いフィードバックを求めている場合はなおさらです。

このプロセスをより合理化するために、Tuistはアプリのプレビューを生成して誰とでも共有する方法を提供する。

> [デバイス用にビルドする場合、アプリが正しく署名されていることを確認するのは、現在のところあなたの責任です。将来的には、これを合理化する予定です。

::コードグループ
```bash [Tuist Project]
tuist build App # Build the app for the simulator
tuist build App -- -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
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

> [重要] プレビューの可視性 プロジェクトが属する組織にアクセスできる人だけがプレビューにアクセスできます。期限切れリンクのサポートを追加する予定です。

## TuistのmacOSアプリ{#tuist-macos-app}。

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

> [重要】要件
> 
> Xcodeをローカルにインストールし、macOS 14以降を使用している必要があります。

## TuistのiOSアプリ{#tuist-ios-app}。

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

macOSアプリと同様に、Tuist iOSアプリはプレビューへのアクセスと実行を効率化します。

## プル/マージリクエストのコメント {#pullmerge-request-comments}

> [重要】Gitプラットフォームとの統合が必要
> プル/マージリクエストのコメントを自動的に取得するには、<LocalizedLink href="/guides/server/accounts-and-projects">リモートプロジェクト</LocalizedLink>を<LocalizedLink href="/guides/server/authentication">Gitプラットフォーム</LocalizedLink>と統合してください。｝

新しい機能のテストは、あらゆるコードレビューの一部であるべきだ。しかし、アプリをローカルでビルドしなければならないことは、不必要な摩擦を増やし、開発者が自分のデバイスで機能をテストすることをスキップしてしまうことになりがちだ。しかし、*、各プルリクエストに、Tuist
macOSアプリで選択したデバイス上でアプリを自動的に実行するビルドへのリンクが含まれていたらどうだろう？*

Tuistプロジェクトが[GitHub](https://github.com)などのGitプラットフォームと接続されたら、CIワークフローに<LocalizedLink href="/cli/share">`tuist
share MyApp`</LocalizedLink>を追加します。するとTuistはプルリクエストに直接プレビューリンクを投稿します: ![GitHub
app comment with a Tuist Preview
link](/images/guides/features/github-app-with-preview.png).

## READMEバッジ {#readme-badge}。

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

## オートメーション {#automations}

`--json` フラグを使えば、`tuist share` コマンドからJSON出力を得ることができる：
```
tuist share --json
```

JSON出力は、CIプロバイダを使用してSlackメッセージを投稿するなど、カスタムオートメーションを作成するのに便利です。JSONには、`url`
キーにプレビューのフルリンク、`qrCodeURL`
キーにQRコード画像のURLが含まれており、実際のデバイスからプレビューをダウンロードしやすくなっています。JSON出力の例を以下に示す：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
