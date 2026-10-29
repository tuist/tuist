---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run your first Buildkite job on Tuist Runners: connect your cluster, name a queue after a Tuist profile, and target it from a step."
}
---
# Buildkite {#buildkite}

> [!IMPORTANT]
> **招待制**
>
> Tuist Runners は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。

Tuist は Buildkite クラスター内のセルフホスト型キューを監視し、検出したジョブをフリート上で実行します。パイプラインは Buildkite 上で引き続き実行され、変更されるのはコンピューティングリソースのみです。フリートでジョブを実行するには、次の 3 つの変更が必要です。クラスターを接続し、Tuist の <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link> に基づいてキューに名前を付け、ステップからそのキューをターゲットに指定します。

1. **アクセスをリクエストする。** ベータ期間中、Runners は招待制です。有効化したいアカウントを添えて [お問い合わせ](mailto:contact@tuist.dev) ください。
2. **クラスターを接続する。** Buildkite でクラスターを開き、**Agent Tokens** に移動してトークンを作成します。トークンは `bkct_` で始まります。Tuist ダッシュボードで **Settings → Integrations** に移動し、Buildkite カードの **Connect** を選択して、組織のスラッグとトークンを入力します。トークンは暗号化されて保存され、二度と表示されることはありません。後で組織を変更したりトークンを更新したりするには、カード上のフィールドを編集して **Save changes** を選択します。Tuist は 1 分以内にクラスターの監視を開始します。
3. **Tuist プロファイルに基づいてキューに名前を付ける。** 有効化されたすべてのアカウントには、すぐに使用可能な 2 つの <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>、`linux` と `macos` が用意されており、ジョブのキューキーがプロファイルのラベルと一致するとジョブが取得されます。クラスター内に `tuist-linux` および `tuist-macos` をキーとするセルフホスト型キューを作成し、ステップからいずれかをターゲットに指定します。

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

4. **プッシュして監視する。** ジョブはキューに登録され、ランナーによって引き受けられ、Tuist ダッシュボードの **Runners** セクションにストリーミングされます。ここでログ、ステップ、マシンのメトリクスを追跡できます。ランナーはそのジョブ専用のスコープを持つ認証情報を使用してジョブ内部からログを送信するため、Buildkite API トークンは不要です。

## 一時停止と切断 {#pausing-and-disconnecting}

Buildkite キューでのディスパッチを一時停止すると、Tuist はそのキューから新しいジョブを取得しなくなります。すでに実行中のジョブには影響しません。

**Settings → Integrations** 下の Buildkite カードでクラスターを切断すると、Tuist による監視が完全に停止します。

## キャッシュボリューム {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link> を使用して、ジョブ間で Xcode、モジュール、Gradle のキャッシュやその他のディレクトリを保持します。チェックアウト後、それらを使用するコマンドの前に追加してください。
