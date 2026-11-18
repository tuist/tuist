---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CIプロバイダー · ランナー · 機能 · ガイド · Tuist",
  "description": "Tuist Runnersで最初のGitHub Actionsジョブを実行しましょう。GitHubを接続し、runs-onをTuistプロファイルに指定して、ダッシュボードで確認できます。"
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

Fleet でジョブを実行するには、次の 3 つの変更が必要です。GitHub を接続し、`runs-on` を Tuist の <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link> に指定して、プッシュします。

1. **GitHub を接続する。** プロジェクトが <.localized_link href="/guides/integrations/gitforge/github">GitHub 組織に接続されていること</.localized_link> を確認してください。Tuist はその組織の `workflow_job` イベントを受信し、一致するジョブを Fleet にディスパッチします。この接続がないと、ジョブはランナーに到達しません。
2. **`runs-on` を Tuist プロファイルに指定する。** 有効なアカウントには、すぐに使える 2 つの <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>（`linux` と `macos`）が付属しています。`tuist-` プレフィックスを付けて参照します。

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **ランナープロファイルで Xcode を選択する**
   >
   > macOS ランナーイメージには単一の Xcode バージョンが含まれており、Tuist はプロファイルに基づいてジョブ開始前にそのバージョンを選択します。GitHub ホスト型ランナーから移行する場合は、`xcode-select --switch`（または `xcode-select -s`）を使用して Xcode バージョンを切り替えるステップや、他のツールやアクションを削除してください。これらのステップは GitHub ホスト型イメージ固有の Xcode インストールを参照することが多く、Tuist Runners では失敗する可能性があります。
   >
   > 別の Xcode バージョンを使用するには、そのバージョンを含むプロファイルを <.localized_link href="/guides/features/runners/profiles#creating-a-profile">作成または選択</.localized_link> し、`runs-on` を更新します（例：`runs-on: tuist-xcode-26-4`）。これにより、`xcodebuild`、`xcrun`、`swift` はワークフローでの追加設定なしに、プロファイルで選択された Xcode を使用します。

3. **プッシュして監視する。** ジョブはキューに入れられ、ランナーによって取得され、Tuist ダッシュボードの **Runners** セクションにストリーミングされます。ここでログ、ステップ、マシンのメトリクスを追跡できます。

## キャッシュボリューム {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link> を使用して、ジョブ間で Xcode キャッシュ、モジュールキャッシュ、Gradle キャッシュ、その他のディレクトリを保持します。チェックアウト後、それらを使用するコマンドの前に追加してください。

ジョブに `id-token: write` を付与し、キャッシュボリュームとキャッシュされたチェックアウトが開始直後にアタッチされるようにします。これがない場合、ランナーは GitHub が実行中のジョブを報告するのを待ち、GitHub が遅れて報告したジョブは空のキャッシュで開始されます。OpenID Connect で Tuist にログインするワークフローでは、すでにこれが付与されています。

```yaml
permissions:
  contents: read
  id-token: write
```
