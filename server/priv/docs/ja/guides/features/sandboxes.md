---
{
  "title": "サンドボックス",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuistのサンドボックスは、AmpやClaudeなどのコーディングエージェント向けに用意された永続的なLinuxおよびmacOS仮想マシンです。各エージェントセッションには専用のマシンが割り当てられ、アイドル状態になると一時停止し、ファイルはそのままで再開されます。"
}
---
# サンドボックス {#sandboxes}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux および macOS）は、キャパシティ拡張中のため現在招待制となっています。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。Sandboxes が一般提供開始となった時点で価格を発表します。

サンドボックスは、コーディングエージェントがコマンドを実行しファイルを編集するための仮想マシンです。各エージェントセッションには専用のサンドボックスが割り当てられ、セッション存続中はチェックアウト状態、ビルド成果物、インストール済みツールが保持されます。エージェントがアイドル状態になるとサンドボックスは一時停止し、次のメッセージで中断箇所から再開されます。

サンドボックスは <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> と同じフリート上で実行され、チームの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> と並列で動作するため、エージェントのビルドは CI やローカルマシンと同じキャッシュアーティファクトを利用できます。

サンドボックスは以下の方法で利用できます：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：Amp ワークスペースの orbs を Tuist で実行します。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：Claude Managed Agents セッションおよび Claude Code クラウドセッション（claude.ai、デスクトップ・モバイルアプリ、および `claude --cloud`）を Tuist で実行します。
- **[Tuist CLI](#cli)**：ターミナルからサンドボックスを作成してコマンドを実行するか、API を経由して独自のツールから操作します。

## CLI ではじめる {#cli}

`tuist sandbox` を使用して、ターミナルからサンドボックスを作成し、その中でコマンドを実行します。

### 1. ログイン {#cli-log-in}

サンドボックスの管理にはアカウント管理者が必要です：

```bash
tuist auth login
```

### 2. サンドボックスを作成 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux の場合は `--platform` を省略してください。より大きな [シェイプ](#platforms) を指定するには `--vcpus` と `--memory-gb` を渡し、より大きなディスクには `--workspace-gb` を指定します。コマンドはサンドボックスが実行状態になると戻り、ID を含む詳細情報を出力します。カレントディレクトリの Tuist プロジェクトのアカウントを使用します。別のアカウントを選択するには `--account` を渡してください。

### 3. コマンドを実行 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

このコマンドはサンドボックス内で `bash -lc` を使用して実行され、一時停止中であればまず再開してから実行されます。`tuist` はコマンドのステータスコードで終了します。

### よくあるタスク {#cli-tasks}

| タスク | コマンド |
| --- | --- |
| サンドボックスを一覧表示 | `tuist sandbox list` |
| 1件を表示 | `tuist sandbox show <id>` |
| 一時停止または再開 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 削除 | `tuist sandbox delete <id> --yes` |
| 使用状況を確認 | `tuist sandbox analytics` |

機械読み取り可能な出力を得るには `--json` を追加します。すべてのオプションについては <.localized_link href="/cli/sandbox">CLI リファレンス</.localized_link> を参照してください。コードからサンドボックスを操作する場合は、`/api/accounts/{account_handle}/sandboxes` 配下の [Tuist API](https://tuist.dev/api/docs) を介して同じ操作を実行するか、エージェントに <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> を介して利用させます。

## Linux と macOS {#platforms}

**Linux** サンドボックスは Ubuntu 24.04 で実行されます：

- 2 vCPU、4 GiB RAM（デフォルト）
- 4 vCPU、8 GiB RAM
- 8 vCPU、16 GiB RAM

**macOS** サンドボックスは Apple silicon 上で Xcode とともに実行されます：

- 8 vCPU、8 GiB RAM（デフォルト）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

## セキュリティ {#security}

- 各サンドボックスは独立した仮想マシンです。サンドボックス間、または CI ジョブとファイルシステム、メモリ、プロセスを共有しません。
- サンドボックスはアカウントに所属し、そのアカウントの管理者のみが管理できます。統合機能からのセッションは、その統合機能が接続されているアカウントのサンドボックスにのみアクセスできます。
- Amp プロバイダートークンや Claude 環境キーなど、統合機能の接続のために Tuist に提供する認証情報は暗号化されて保存され、再度表示されることはありません。
- サンドボックスはインターネットにアクセスできます。エージェントがそこからアクセスできるものは、CI ジョブと同様に扱ってください。
