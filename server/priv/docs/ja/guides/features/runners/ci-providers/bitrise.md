---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CIプロバイダー · ランナー · 機能 · ガイド · Tuist",
  "description": "TuistランナーでBitriseビルドを実行します。ワークスペースを接続し、セルフホスト型ランナープールをTuistプロファイルとペアリングして、ワークフローでそのプールを選択します。"
}
---
# Bitrise {#bitrise}

> [!IMPORTANT]
> **招待制**
>
> Tuist Runners は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。

> [!WARNING]
> **プライベートリポジトリ限定**
>
> Tuist はすべての Bitrise ビルドを信頼します。ビルドはアカウントのキャッシュを共有し、書き込みが可能です。パブリックリポジトリのフォークからプルリクエストをビルドするワークフローを持つプールとは連携しないでください。

Tuist は、Bitrise ワークスペースのセルフホスト型ランナープールを提供します。これらのプールのいずれかを選択したビルドは、プールとペアリングした<.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>に応じた Tuist マシン上で実行されます。ワークフロー、トリガー、ログは Bitrise に残ります。変更されるのはマシンのみです。

1. **アクセスをリクエスト。** ベータ期間中、Runners は招待制です。有効化したいアカウントを持って[お問い合わせ](mailto:contact@tuist.dev)ください。
2. **ワークスペースを接続。** Bitrise で**Workspace settings → Security → Workspace API tokens**を開き、すべてのプロジェクトに対して Bitrise CI への**Viewer**ワークスペースロールと**Tester/QA**アクセス権を持つトークンを作成します。Tuist ダッシュボードで**Settings → Integrations**に移動し、Bitrise カードの**Connect**を選択してトークンを貼り付けます。Tuist はトークンからワークスペースを読み取り、トークンを暗号化して保存するため、二度と表示されません。
3. **ランナープールを作成。** Bitrise で**Workspace settings → Infrastructure**を開き、**Add Runner pool**を選択して、対象のマシンに合わせて名前を付けます（例: `tuist-macos`）。プールトークンをコピーしてください。Bitrise ではこのトークンは一度しか表示されません。
4. **プールを Tuist プロファイルとペアリング。** Tuist の Bitrise カードで、**Runner pools**の下からプールと、そのビルドを実行すべき Tuist プロファイルを選択し、プールトークンを貼り付けて**Add pool**を選択します。有効なすべてのアカウントには、`tuist-linux`と`tuist-macos`の 2 つのプロファイルが最初から用意されています。使用したいプロファイルごとに 1 つのプールを追加してください。
5. **ワークフローでプールを選択。** Bitrise の Workflow Editor で**Stacks & Machines**を開き、**Self-Hosted Runner: tuist-macos**を選択します。`bitrise.yml`で、プール名の下に Tuist が表示するプールのスタックを設定します。

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

6. **ビルドを実行。** 数秒以内に Tuist マシンがプールに接続してビルドを引き受け、完了すると切断されます。ビルドは Tuist ダッシュボードの**Runners**セクションに表示され、マシンメトリクスと、ログが残る Bitrise へのリンクが含まれます。

## 専用プール {#dedicated-pools}

Tuist とペアリングしたプールは、Tuist 専用として使用してください。独自のマシンのいずれかもペアリング済みのプールに接続する場合、そのプールのビルドをめぐって Tuist と競合します。

## ランナー制限 {#runner-limit}

各 Tuist マシンは、ビルドを実行している間は Bitrise ランナー 1 台としてカウントされ、切断されるとカウントされなくなります。したがって、Bitrise プランのランナー制限は、Tuist の同時実行数制限とともに、同時に Tuist で実行できるビルド数の上限となります。

## 切断 {#disconnecting}

Bitrise カードからプールを削除すると、Tuist がそのプールのビルドを引き受けなくなります。すでに実行中のビルドには影響しません。

Bitrise カードで**Disconnect**を選択すると、ワークスペースとそのすべてのプールが削除されます。
