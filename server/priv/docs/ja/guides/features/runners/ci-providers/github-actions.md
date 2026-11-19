---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CIプロバイダー · ランナー · 機能 · ガイド · Tuist",
  "description": "Tuistランナーで最初のGitHub Actionsジョブを実行しましょう。GitHubを接続し、runs-onをTuistプロファイルに指定して、ダッシュボードで確認します。"
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

フリートでジョブを実行するには、3つの手順が必要です。GitHubを接続し、`runs-on`をTuistの<.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>に向け、プッシュします。

1. **GitHubを接続する。** プロジェクトが<.localized_link href="/guides/integrations/gitforge/github">GitHub組織に接続されている</.localized_link>ことを確認してください。Tuistはその組織の`workflow_job`イベントを受信し、一致するジョブをフリートにディスパッチします。この接続がないと、ジョブはランナーに届きません。
2. **`runs-on`をTuistのプロファイルに向ける。** 有効化されたすべてのアカウントには、すぐに使用できる2つの<.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>（`linux`と`macos`）が用意されています。`tuist-`プレフィックスを付けて参照します。

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **ランナープロファイルでXcodeを選択する**
   >
   > macOSランナーイメージには単一のXcodeバージョンが含まれており、Tuistはプロファイルに基づいてジョブ開始前にこれを選択します。GitHubホスト型ランナーから移行する場合は、`xcode-select --switch`（または`xcode-select -s`）を使用してXcodeバージョンを切り替えるステップや、その他のツールおよびアクションを削除してください。これらのステップは通常、GitHubホスト型イメージ固有のXcodeインストールを参照しており、Tuist Runnersでは失敗する可能性があります。
   >
   > 別のXcodeバージョンを使用するには、そのバージョンを含むプロファイルを<.localized_link href="/guides/features/runners/profiles#creating-a-profile">作成または選択</.localized_link>し、`runs-on`を更新します（例：`runs-on: tuist-xcode-26-4`）。その後、`xcodebuild`、`xcrun`、および`swift`は、ワークフローでの追加設定なしに、プロファイルで選択されたXcodeを使用します。

3. **プッシュして監視する。** ジョブはキューに入れられ、ランナーによって取得され、Tuistダッシュボードの**Runners**セクションにストリーミングされます。ここでログ、ステップ、マシンのメトリクスを追跡できます。

## キャッシュボリューム {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link>を使用して、ジョブ間でXcode、モジュール、Gradleのキャッシュや他のディレクトリを保持します。チェックアウトの後、それらを使用するコマンドの前に追加してください。

ジョブに`id-token: write`を付与し、キャッシュボリュームとキャッシュされたチェックアウトが開始時にすぐにアタッチされるようにします。これがないと、ランナーはGitHubが実行中のジョブを報告するのを待ち、GitHubからの報告が遅れたジョブは空のキャッシュで開始されます。OpenID ConnectでTuistにログインするワークフローは、すでにこれを付与しています。

```yaml
permissions:
  contents: read
  id-token: write
```
