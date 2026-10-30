---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CIプロバイダー · ランナー · 機能 · ガイド · Tuist",
  "description": "Tuist Runnersで最初のBuildkiteジョブを実行しましょう。クラスターを接続し、Tuistプロファイルに合わせてキューに名前を付け、ステップからそのキューをターゲットとして指定します。"
}
---
# Buildkite {#buildkite}

> [!IMPORTANT]
> **招待制**
>
> Tuist Runners は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev)でご連絡ください。

Tuist は Buildkite クラスター内のセルフホストキューを監視し、見つかったジョブをフリート上で実行します。パイプラインは Buildkite 上で引き続き動作し、変更されるのはコンピューティングリソースのみです。フリートでジョブを実行するには、次の 3 つの変更が必要です。クラスターを接続し、キューに Tuist の<.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>の名前を付け、ステップからそのキューをターゲットとして指定します。

1. **アクセスをリクエストする。** ランナーはベータ期間中、招待制です。有効化したいアカウントとともに[お問い合わせ](mailto:contact@tuist.dev)ください。
2. **クラスターを接続する。** Buildkite でクラスターを開き、**Agent Tokens**に移動してトークンを作成します。トークンは `bkct_` で始まります。Tuist ダッシュボードで **Settings → Integrations** に移動し、Buildkite カードの **Connect** を選択して、組織のスラッグとトークンを入力します。トークンは暗号化されて保存され、二度と表示されません。後で組織を変更したりトークンを更新するには、カード上のフィールドを編集して **Save changes** を選択します。Tuist は 1 分以内にクラスターの監視を開始します。
3. **Tuist プロファイルに合わせてキューに名前を付ける。** 有効なすべてのアカウントには、すぐに使用可能な 2 つの <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>、`linux` および `macos` が用意されており、ジョブのキューキーがプロファイルのラベルと一致するとジョブが取得されます。クラスター内で `tuist-linux` および `tuist-macos` をキーとするセルフホストキューを作成し、ステップからいずれかをターゲットとして指定します。

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

4. **プッシュして確認する。** ジョブはキューに入れられ、ランナーによって取得され、Tuist ダッシュボードの **Runners** セクションにストリーミングされます。ここではログ、ステップ、マシンのメトリクスを追跡できます。ランナーはそのジョブにスコープされた認証情報を使用してジョブ内からログを送信するため、Buildkite API トークンは不要です。

## 一時停止と切断 {#pausing-and-disconnecting}

Buildkite キューでのディスパッチを一時停止すると、Tuist はそのキューから新しいジョブを取得しなくなります。すでに実行中のジョブには影響しません。

**Settings → Integrations** 下の Buildkite カードでクラスターを切断すると、Tuist による監視が完全に停止します。

## キャッシュボリューム {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link>を使用して、ジョブ間で Xcode、モジュール、Gradle のキャッシュやその他のディレクトリを保持します。チェックアウトの後、それらを使用するコマンドの前に追加してください。
