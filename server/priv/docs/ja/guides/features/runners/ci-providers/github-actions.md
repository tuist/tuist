---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI プロバイダー · ランナー · 機能 · ガイド · Tuist",
  "description": "Tuist Runners で最初の GitHub Actions ジョブを実行しましょう。GitHub を接続し、runs-on を Tuist プロファイルに指定して、ダッシュボードで確認できます。"
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **招待制**
>
> Tuist Runners は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) でご連絡ください。

フリート上でジョブを実行するには、次の 3 つの変更が必要です。GitHub を接続し、`runs-on` を Tuist の <.localized_link href="/guides/features/runners/profiles">プロフィール</.localized_link> に指定して、プッシュします。

1. **アクセスをリクエストする。** ベータ期間中、Runners は招待制です。有効にしたいアカウントを添えて [お問い合わせ](mailto:contact@tuist.dev) ください。
2. **GitHub を接続する。** プロジェクトが <.localized_link href="/guides/integrations/gitforge/github">GitHub 組織に接続されていること</.localized_link> を確認してください。Tuist はその組織の `workflow_job` イベントを受信し、一致するジョブをフリートにディスパッチします。この接続がないと、ジョブはランナーに届きません。
3. **`runs-on` を Tuist プロフィールに指定する。** 有効化されたすべてのアカウントには、すぐに使用できる 2 つの <.localized_link href="/guides/features/runners/profiles">プロフィール</.localized_link>（`linux` と `macos`）が付属しています。`tuist-` プレフィックスを付けて参照します。

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **ランナープロフィールで Xcode を選択する**
   >
   > macOS ランナーイメージには単一の Xcode バージョンが含まれており、Tuist がジョブ開始前にプロフィールに基づいて選択します。GitHub ホスト型ランナーから移行する場合は、`xcode-select --switch`（または `xcode-select -s`）を使用して Xcode バージョンを切り替えるステップや、その他のツールおよびアクションを削除してください。これらのステップは GitHub ホスト型イメージ固有の Xcode インストールを参照することが多く、Tuist Runners では失敗する可能性があります。
   >
   > 別の Xcode バージョンを使用するには、そのバージョンを含む <.localized_link href="/guides/features/runners/profiles#creating-a-profile">プロフィールを作成または選択</.localized_link> し、`runs-on` を更新します（例: `runs-on: tuist-xcode-26-4`）。これにより、`xcodebuild`、`xcrun`、および `swift` はワークフローでの追加設定なしに、プロフィールで選択された Xcode を使用します。

4. **プッシュして監視する。** ジョブはキューに入れられ、ランナーによって処理され、Tuist ダッシュボードの **Runners** セクションにストリームバックされます。ここでログ、ステップ、マシンのメトリクスを追跡できます。

## キャッシュボリューム {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link> を使用して、ジョブ間で Xcode、モジュール、Gradle のキャッシュやその他のディレクトリを維持します。チェックアウト後、それらを使用するコマンドの前に追加してください。
