---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CIプロバイダー · ランナー · 機能 · ガイド · Tuist",
  "description": "Tuist Runners上でBitriseビルドを実行します。ワークスペースを接続し、セルフホスト型ランナープールをTuistプロファイルと紐付け、ワークフローでそのプールを選択してください。"
}
---
# Bitrise {#bitrise}

<!-- @snippet: ./_invite-only -->

> [!WARNING]
> **プライベートリポジトリのみ**
>
> Tuist はすべての Bitrise ビルドを信頼します。ビルドはアカウントのキャッシュを共有し、書き込むことができます。パブリックリポジトリのフォークからプルリクエストをビルドするワークフローを持つプールは連携しないでください。

Tuist は、Bitrise ワークスペースのセルフホスト型ランナープールを提供します。これらのプールの 1 つを選択したビルドは、プールと連携させた<.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>の Tuist マシン上で実行されます。ワークフロー、トリガー、ログは Bitrise に残ったまま、マシンだけが置き換わります。

1. **ワークスペースを接続する。** Bitrise で**Workspace settings → Security → Workspace API tokens**を開き、すべてのプロジェクトに対して Bitrise CI への**Viewer**ワークスペースロールと**Tester/QA**アクセス権を持つトークンを作成します。Tuist ダッシュボードで**Settings → Integrations**に移動し、Bitrise カードの**Connect**を選択してトークンを貼り付けます。Tuist はトークンからワークスペースを読み取り、トークンを暗号化して保存し、再度表示しません。
2. **ランナープールを作成する。** Bitrise で**Workspace settings → Infrastructure**を開き、**Add Runner pool**を選択して、対象のマシンに合わせて名前を付けます（例：`tuist-macos`）。プールトークンをコピーしてください。Bitrise ではこのトークンは一度しか表示されません。
3. **プールを Tuist プロファイルと連携させる。** Tuist の Bitrise カードで、**Runner pools**の下からプールと、そのビルドを実行する Tuist プロファイルを選択し、プールトークンを貼り付けて**Add pool**を選択します。有効なアカウントには、`tuist-linux`と`tuist-macos`の 2 つのプロファイルが最初から用意されています。使用したいプロファイルごとに 1 つのプールを追加してください。
4. **ワークフローでプールを選択する。** Bitrise の Workflow Editor で**Stacks & Machines**を開き、**Self-Hosted Runner: tuist-macos**を選択します。`bitrise.yml`で、プールのスタックを設定します。スタックは Tuist がプールの名前の下に表示します。

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

5. **ビルドを実行する。** 数秒以内に Tuist マシンがプールに接続し、ビルドを引き受けて、完了すると切断されます。ビルドは Tuist ダッシュボードの**Runners**セクションに表示され、マシンのメトリクスと、ログが残る Bitrise へのリンクが含まれます。

## 専用プール {#dedicated-pools}

Tuist と連携させたプールは Tuist 専用として使用してください。独自のマシンも連携済みのプールに接続すると、そのプールのビルドを Tuist と競合することになります。

## ランナー制限 {#runner-limit}

各 Tuist マシンはビルド実行中に Bitrise ランナー 1 台としてカウントされ、切断されるとカウントから外れます。したがって、Bitrise プランのランナー制限により、Tuist の同時実行数制限に加えて、同時に Tuist で実行できるビルド数が上限となります。

## 切断 {#disconnecting}

Bitrise カードからプールを削除すると、Tuist がそのプールのビルドを引き受けなくなります。すでに実行中のビルドには影響しません。

Bitrise カードで**Disconnect**を選択すると、ワークスペースとそのすべてのプールが削除されます。
