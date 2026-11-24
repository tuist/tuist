---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CIプロバイダー · ランナー · 機能 · ガイド · Tuist",
  "description": "TuistランナーでBitriseビルドを実行：ワークスペースを接続し、セルフホスト型ランナープールをTuistプロファイルと紐付け、ワークフローでそのプールを選択します。"
}
---
# Bitrise {#bitrise}

> [!WARNING]
> **プライベートリポジトリのみ**
>
> Tuist はすべての Bitrise ビルドを信頼します。ビルドはアカウントのキャッシュを共有し、書き込むことができます。パブリックリポジトリのフォークからプルリクエストをビルドするワークフローを持つプールはペアリングしないでください。

Tuist は、Bitrise ワークスペースのセルフホスト型ランナープールを提供します。これらのプールのいずれかを選択したビルドは、プールとペアリングした<.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>の Tuist マシン上で実行されます。ワークフロー、トリガー、ログは Bitrise 上に残ります。変更されるのはマシンのみです。

1. **ワークスペースを接続する。** Bitrise で**Workspace settings → Security → Workspace API tokens**を開き、すべてのプロジェクトに対して Bitrise CI への**Viewer**ワークスペースロールと**Tester/QA**アクセス権を持つトークンを作成します。Tuist ダッシュボードで**Settings → Integrations**に移動し、Bitrise カードの**Connect**を選択してトークンを貼り付けます。Tuist はトークンからワークスペースを読み取り、トークンを暗号化して保存し、二度と表示しません。
2. **ランナープールを作成する。** Bitrise で**Workspace settings → Infrastructure**を開き、**Add Runner pool**を選択して、対象のマシンに合わせて名前を付けます（例：`tuist-macos`）。プールトークンをコピーします。Bitrise はこれを一度だけ表示します。
3. **プールを Tuist プロファイルとペアリングする。** Tuist の Bitrise カードで、**Runner pools**の下からプールを選択し、ビルドを実行する Tuist プロファイルを選択して、プールトークンを貼り付け、**Add pool**を選択します。有効なすべてのアカウントには、`tuist-linux`と`tuist-macos`の 2 つのプロファイルが最初から用意されています。使用したいプロファイルごとに 1 つのプールを追加してください。
4. **ワークフローでプールを選択する。** Bitrise の Workflow Editor で**Stacks & Machines**を開き、**Self-Hosted Runner: tuist-macos**を選択します。`bitrise.yml`で、プールのスタックを設定します。スタックは Tuist がプールの名前の下に表示します。

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

5. **ビルドを実行する。** 数秒以内に Tuist マシンがプールに接続し、ビルドを引き受けて、完了すると切断されます。ビルドは Tuist ダッシュボードの**Runners**セクションに表示され、マシンメトリクスと Bitrise へのリンク（ログが残る場所）が含まれます。

## 専用プール {#dedicated-pools}

Tuist とペアリングしたプールは Tuist 専用として使用してください。独自のマシンもペアリング済みのプールに接続する場合、そのプールのビルド獲得をめぐって Tuist と競合します。

## ランナー制限 {#runner-limit}

各 Tuist マシンは、ビルドを実行している間は Bitrise ランナー 1 台としてカウントされ、切断されるとカウントされなくなります。したがって、Bitrise プランのランナー制限により、Tuist の同時実行数制限とともに、同時に Tuist 上で実行できるビルド数が上限設定されます。

## 切断 {#disconnecting}

Bitrise カードからプールを削除すると、Tuist がそのプールのビルドを引き受けることを停止します。すでに実行中のビルドには影響しません。

Bitrise カードで**Disconnect**を選択すると、ワークスペースとそのすべてのプールが削除されます。
