---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CIプロバイダー · ランナー · 機能 · ガイド · Tuist",
  "description": "Tuist Runnersで最初のBuildkiteジョブを実行しましょう：クラスターを接続し、Tuistプロファイルに合わせた名前のキューを作成し、ステップからそのキューを指定します。"
}
---
# Buildkite {#buildkite}

> [!IMPORTANT]
> **招待制**
>
> Tuist Runners は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。

Tuist は Buildkite クラスター内のセルフホストキューを監視し、検出したジョブをランナーフリート上で実行します。パイプラインは Buildkite 上で引き続き動作し、変更されるのはコンピューティングリソースのみです。フリート上でジョブを実行するには、次の 3 つの変更が必要です。クラスターを接続し、キューに Tuist の <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link> に基づいた名前を付け、ステップからそのキューをターゲットとして指定します。

1. **アクセスをリクエストする。** ベータ期間中、Runners は招待制です。有効化したいアカウントを添えて [お問い合わせ](mailto:contact@tuist.dev) ください。
2. **クラスターを接続する。** Buildkite でクラスターを開き、**Agent Tokens** に移動してトークンを作成します。トークンは `bkct_` で始まります。Tuist ダッシュボードで **Settings → Integrations** に移動し、Buildkite カードの **Connect** を選択して、組織のスラッグとトークンを入力します。トークンは暗号化されて保存され、再度表示されることはありません。後で組織を変更したりトークンを更新する場合は、カード上のフィールドを編集して **Save changes** を選択してください。Tuist は 1 分以内にクラスターの監視を開始します。
3. **キューに Tuist プロファイルに基づく名前を付ける。** 有効化されたすべてのアカウントには、すぐに使用可能な 2 つの <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>（`linux` と `macos`）が用意されており、ジョブのキューキーがプロファイルのラベルと一致すると、そのジョブが取得されます。クラスター内で `tuist-linux` および `tuist-macos` というキーを持つセルフホストキューを作成し、ステップからいずれかをターゲットとして指定します。

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

4. **プッシュして確認する。** ジョブはキューに入り、ランナーによって取得され、Tuist ダッシュボードの **Runners** セクションにストリームとして返されます。ここでログ、ステップ、マシンのメトリクスを追跡できます。ランナーはそのジョブにスコープされた認証情報を使用してジョブ内からログを送信するため、Buildkite API トークンは不要です。

## 一時停止と切断 {#pausing-and-disconnecting}

Buildkite キューでのディスパッチを一時停止すると、Tuist がそのキューから新しいジョブを取得しなくなります。すでに実行中のジョブには影響しません。

**Settings → Integrations** の Buildkite カードでクラスターの接続を解除すると、Tuist による監視が完全に停止します。

## キャッシュボリューム {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link> を使用して、ジョブ間で Xcode キャッシュ、モジュールキャッシュ、Gradle キャッシュ、およびその他のディレクトリを保持します。これらはチェックアウトの後、それらを使用するコマンドの前に追加してください。
