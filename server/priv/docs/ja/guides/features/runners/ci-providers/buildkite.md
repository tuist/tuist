---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CIプロバイダー · Runners · 機能 · ガイド · Tuist",
  "description": "Tuist Runnersで最初のBuildkiteジョブを実行します。クラスターを接続し、Tuistプロファイルに合わせたキューに名前を付け、ステップからそのキューをターゲットとして指定します。"
}
---
# Buildkite {#buildkite}

Tuist は Buildkite クラスター内のセルフホスト型キューを監視し、見つかったジョブをフリート上で実行します。パイプラインは Buildkite 上で引き続き動作し、変更されるのはコンピューティングリソースのみです。フリートでジョブを実行するには、次の 3 つの変更が必要です。クラスターを接続し、Tuist の <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link> に合わせてキューに名前を付け、ステップからそのキューをターゲットとして指定します。

1. **クラスターを接続する。** Buildkite でクラスターを開き、**Agent Tokens** に移動してトークンを作成します。トークンは `bkct_` で始まります。Tuist ダッシュボードで **Settings → Integrations** に移動し、Buildkite カードの **Connect** を選択して、組織のスラッグとトークンを入力します。トークンは暗号化されて保存され、再度表示されることはありません。後で組織を変更したりトークンを更新する場合は、カードのフィールドを編集して **Save changes** を選択してください。Tuist は 1 分以内にクラスターの監視を開始します。
2. **Tuist プロファイルに合わせてキューに名前を付ける。** 有効なアカウントには、すぐに使用できる 2 つの <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>（`linux` と `macos`）が用意されており、ジョブのキューキーがプロファイルのラベルと一致するとジョブが取得されます。クラスター内に `tuist-linux` および `tuist-macos` というキーを持つセルフホスト型キューを作成し、ステップからいずれかをターゲットとして指定します。

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

3. **プッシュして監視する。** ジョブはキューに入り、ランナーによって取得され、Tuist ダッシュボードの **Runners** セクションにストリーミングされます。ここでログ、ステップ、マシンのメトリクスを追跡できます。ランナーはそのジョブ専用の資格情報を使用してジョブ内からログを送信するため、Buildkite API トークンは不要です。

## 一時停止と切断 {#pausing-and-disconnecting}

Buildkite キューでのディスパッチを一時停止すると、Tuist がそのキューから新しいジョブを取得しなくなります。すでに実行中のジョブには影響しません。

**Settings → Integrations** の下の Buildkite カードでクラスターを切断すると、Tuist による監視が完全に停止します。

## キャッシュボリューム {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link> を使用して、ジョブ間で Xcode キャッシュ、モジュールキャッシュ、Gradle キャッシュ、その他のディレクトリを保持します。チェックアウトの後、それらを使用するコマンドの前に追加してください。
