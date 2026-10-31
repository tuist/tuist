---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CIプロバイダー · ランナー · 機能 · ガイド · Tuist",
  "description": "Tuist Runnerで最初のGitHub Actionsジョブを実行しましょう。GitHubを接続し、runs-onをTuistプロファイルに指定して、ダッシュボードで確認できます。"
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **招待制**
>
> Tuist Runners は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。

フリート上でジョブを実行するには、次の 3 つの変更が必要です。GitHub を接続し、`runs-on` を Tuist の <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link> に向け、プッシュします。

1. **アクセスをリクエストする。** ベータ期間中、Runners は招待制です。有効にしたいアカウントを添えて [お問い合わせ](mailto:contact@tuist.dev) ください。
2. **GitHub を接続する。** プロジェクトが <.localized_link href="/guides/integrations/gitforge/github">GitHub Organization に接続されている</.localized_link> ことを確認してください。Tuist はその Organization の `workflow_job` イベントを受信し、一致するジョブをフリートにディスパッチします。この接続がないと、ジョブは Runner に届きません。
3. **`runs-on` を Tuist のプロファイルに向ける。** 有効化されたすべてのアカウントには、すぐに使用できる <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link> が 2 つ用意されています。`linux` と `macos` です。`tuist-` プレフィックスを付けて参照します。

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **Runner プロファイルで Xcode を選択する**
   >
   > macOS Runner イメージには単一の Xcode バージョンが含まれており、Tuist がプロファイルに基づいてジョブ開始前に選択します。GitHub ホスト型 Runner から移行する場合は、`xcode-select --switch`（または `xcode-select -s`）を使用して Xcode のバージョンを切り替えるステップや、他のツールおよびアクションを削除してください。これらのステップは GitHub ホスト型イメージ固有の Xcode インストールを参照することが多く、Tuist Runners では失敗する可能性があります。
   >
   > 別の Xcode バージョンを使用するには、そのバージョンを含むプロファイルを <.localized_link href="/guides/features/runners/profiles#creating-a-profile">作成または選択</.localized_link> し、`runs-on` を更新します（例: `runs-on: tuist-xcode-26-4`）。これにより、`xcodebuild`、`xcrun`、および `swift` はワークフローでの追加設定なしに、プロファイルで選択された Xcode を使用します。

4. **プッシュして監視する。** ジョブはキューに入れられ、Runner によって処理され、Tuist ダッシュボードの **Runners** セクションにストリーミングされます。ここでログ、ステップ、マシンのメトリクスを追跡できます。

## キャッシュボリューム {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link> を使用して、ジョブ間で Xcode、モジュール、Gradle のキャッシュやその他のディレクトリを保持します。チェックアウトの後、それらを使用するコマンドの前に追加します。
