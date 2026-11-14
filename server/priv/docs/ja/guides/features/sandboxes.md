---
{
  "title": "サンドボックス",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Sandboxes は、Amp や Claude などのコーディングエージェント向けに用意された永続的な Linux および macOS 仮想マシンです。各エージェントセッションは専用のマシンで実行され、アイドル状態になると一時停止し、再開時にはファイルがそのまま維持されます。"
}
---
# サンドボックス {#sandboxes}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux と macOS の両方）は、現在キャパシティ増強中のため招待制となっています。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。Sandboxes が一般提供開始となった時点で、料金プランを発表します。

サンドボックスは、コーディングエージェントがコマンドを実行しファイルを編集するための仮想マシンです。各エージェントセッションには専用のサンドボックスが割り当てられ、セッション存续中はチェックアウト内容、ビルド成果物、インストール済みツールが保持されます。エージェントがアイドル状態になるとサンドボックスは一時停止し、次のメッセージで前回中断した箇所から再開します。

サンドボックスは <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> と同じフリート上で動作し、チームの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> の隣に配置されるため、エージェントによるビルドは CI やローカルマシンと同じキャッシュアーティファクトを利用できます。

サンドボックスは以下の方法で利用できます：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：Amp ワークスペースの orbs を Tuist 上で実行するか、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> を使って任意の Amp スレッドに Xcode ビルド用の Mac を提供します。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：Claude Managed Agents セッションおよび Claude Code クラウドセッション（claude.ai、デスクトップ・モバイルアプリ、`claude --cloud`）を Tuist 上で実行します。
- **[The Tuist CLI](#cli)**：ターミナルからサンドボックスを作成してコマンドを実行したり、API を介して独自のツールから操作したりできます。

## CLI で始める {#cli}

`tuist sandbox` を使ってターミナルからサンドボックスを作成し、その中でコマンドを実行します。

### 1. ログイン {#cli-log-in}

サンドボックスを管理するにはアカウント管理者が必要です：

```bash
tuist auth login
```

### 2. サンドボックスを作成 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux の場合は `--platform` を省略してください。より大きな [シェイプ](#platforms) を指定するには `--vcpus` と `--memory-gb` を渡し、より大きなディスクには `--workspace-gb` を指定します。サンドボックスが起動するとコマンドは完了し、ID を含む詳細情報を出力します。カレントディレクトリの Tuist プロジェクトのアカウントを使用します。別のアカウントを選択するには `--account` を渡してください。

### 3. コマンドを実行 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

このコマンドはサンドボックス内で `bash -l` で実行され、一時停止中であればまず再開されます。`tuist` は実行時間に関係なく出力をストリーミングし、コマンドのステータスで終了します。Ctrl-C でサンドボックス内の処理をキャンセルできます。必要に応じて `--cwd`、`--env NAME=VALUE`、`--timeout`（最大6時間）を指定してください。

### よく使うタスク {#cli-tasks}

| タスク | コマンド |
| --- | --- |
| サンドボックスを一覧表示 | `tuist sandbox list` |
| 1つを表示 | `tuist sandbox show <id>` |
| 一時停止または再開 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| ローカルの Git ワークツリーのファイルを同期 | `tuist sandbox sync <id>` |
| ファイルのコピー（出し入れ） | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 削除 | `tuist sandbox delete <id> --yes` |
| 使用状況を確認 | `tuist sandbox analytics` |

機械読み取り可能な出力を得るには `--json` を追加してください。すべてのオプションについては <.localized_link href="/cli/sandbox">CLI リファレンス</.localized_link> を参照してください。コードからサンドボックスを操作する場合は、[Tuist API](https://tuist.dev/api/docs) の `/api/accounts/{account_handle}/sandboxes` エンドポイントを通じて同じ操作を行うか、エージェントに <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> を介して利用させます。

対話的なログインができないツール（macOSサンドボックスでビルドを行うエージェントプラグインなど）は、代わりに<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>と`account:sandboxes:write`スコープを使用して認証できます。このトークンは、アカウントメンバーと同様に、サンドボックスの作成、コマンドの実行、一時停止、再開、削除を行えます。AmpまたはClaude統合を提供するサンドボックス、アナリティクス、および統合設定はアカウント管理者が管理します。

## コーディングエージェントから Mac でビルド {#coding-agents}

クラウドエージェントセッションなど Linux 上で動作するコーディングエージェントは、ファイル編集を続行しながら macOS サンドボックス上で Apple プラットフォーム向けコードのビルド、テスト、実行を行えます。Amp では <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> をインストールしてください。Claude Code や Cursor など他のエージェントの場合は次の手順に従います：

1. エージェントを Tuist の <.localized_link href="/guides/features/agentic-coding/mcp">MCP サーバー</.localized_link> に接続します。`create_sandbox` ツールが Mac を操作する方法をエージェントに指示します。
2. エージェントが実行される環境に Tuist CLI をインストールします。例えば環境のセットアップスクリプトで `mise use -g tuist@latest`、または `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM では `tuist-linux-aarch64`）を実行します。
3. CLI を認証します。MCP サーバーのサインイン情報は引き継がれないため、アカウントメンバーとして `tuist auth login` を実行するか、`account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> を `TUIST_TOKEN` に設定します。
4. 環境でネットワークアクセスが制限されている場合は、`tuist.dev` を許可してください。CLI はこれを介して Mac にファイルをアップロードするため、他のドメインは不要です。

エージェントはタスクごとに1台の Mac を作成し、各コマンドの前に `tuist sandbox sync` を実行します。Git が無視しないファイル（コミット済みかどうかを問わず）をコピーし、その後変更されたファイルのみを同期します。その後、エージェントは `tuist sandbox exec` を使って `xcodebuild` などのコマンドを実行し、`tuist sandbox cp` でスクリーンショットやビルド済みアプリなどの結果をコピーバックし、タスク完了後に Mac を削除します。Mac は最後のコマンド実行後10分間稼働し続けるため、次のコマンドはすぐに開始されます。`tuist sandbox pause` を使えばより早く返却できます。放置された Mac は一時停止し、14日間一時停止状態が続くと削除されます。

## Linux と macOS {#platforms}

**Linux** サンドボックスは Ubuntu 24.04 で動作します：

- 2 vCPU、4 GiB RAM（デフォルト）
- 4 vCPU、8 GiB RAM
- 8 vCPU、16 GiB RAM

**macOS** サンドボックスは Apple silicon 上で Xcode を使用して動作します：

- 8 vCPU、8 GiB RAM（デフォルト）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

## セキュリティ {#security}

- 各サンドボックスは独立した仮想マシンです。サンドボックス間や CI ジョブとの間でファイルシステム、メモリ、プロセスを共有しません。
- サンドボックスはアカウントに属し、その管理者のみが管理できます。統合からのセッションは、統合が接続されているアカウントのサンドボックスにのみアクセスできます。
- Amp プロバイダートークンや Claude 環境キーなど、統合の接続のために Tuist に提供する認証情報は暗号化して保存され、二度と表示されることはありません。
- サンドボックスはインターネットにアクセスできます。エージェントがそこからアクセスできるものは、CI ジョブと同様に扱ってください。
