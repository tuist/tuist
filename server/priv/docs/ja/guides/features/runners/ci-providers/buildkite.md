---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CIプロバイダー · ランナー · 機能 · ガイド · Tuist",
  "description": "Tuist Runnersで最初のBuildkiteジョブを実行しましょう。クラスターを接続し、Tuistプロファイルに基づいてキューに名前を付け、ステップからそのキューをターゲットとして指定します。"
}
---
# Buildkite {#buildkite}

Tuist は、Buildkite クラスター内のセルフホストキューを監視し、見つかったジョブをフリート上で実行します。パイプラインは Buildkite 上で引き続き動作し、変更されるのはコンピューティングリソースのみです。フリートでジョブを実行するには、次の 3 つの変更が必要です。クラスターを接続し、Tuist の <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link> に合わせてキューに名前を付け、ステップからそのキューをターゲットとして指定します。

1. **クラスターを接続する。** Buildkite でクラスターを開き、**Agent Tokens** に移動してトークンを作成します。トークンは `bkct_` で始まります。Tuist ダッシュボードで **Settings → Integrations** に移動し、Buildkite カードの **Connect** を選択して、組織のスラッグとトークンを入力します。トークンは暗号化されて保存され、二度と表示されることはありません。後で組織を変更したりトークンを更新する場合は、カードのフィールドを編集して **Save changes** を選択します。Tuist は 1 分以内にクラスターの監視を開始します。
2. **Tuist プロファイルに合わせてキューに名前を付ける。** 有効なアカウントには、すぐに使用できる <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link> として `linux` と `macos` の 2 つが用意されており、ジョブのキューキーがプロファイルのラベルと一致するとジョブが取得されます。クラスター内で `tuist-linux` と `tuist-macos` というキーを持つセルフホストキューを作成し、ステップからいずれかをターゲットとして指定します。

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

3. **プッシュして監視する。** ジョブはキューに入れられ、ランナーによって取得されると、Tuist ダッシュボードの **Runners** セクションにストリームバックされます。ここでログ、ステップ、マシンのメトリクスを追跡できます。ランナーは、そのジョブにスコープされた認証情報を使用してジョブ内部からログを送信するため、Buildkite API トークンは不要です。

## 一時停止と切断 {#pausing-and-disconnecting}

Buildkite キューでのディスパッチを一時停止すると、Tuist はそのキューから新しいジョブを取得しなくなります。すでに実行中のジョブには影響しません。

**Settings → Integrations** の Buildkite カードでクラスターを切断すると、Tuist による監視が完全に停止します。

## キャッシュボリューム {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link> を使用して、ジョブ間で Xcode キャッシュ、モジュールキャッシュ、Gradle キャッシュ、およびその他のディレクトリを保持します。チェックアウト後、それらを使用するコマンドの前に追加します。
