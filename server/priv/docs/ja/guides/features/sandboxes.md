---
{
  "title": "サンドボックス",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuistのサンドボックスは、AmpやClaudeなどのコーディングエージェント向けに用意された永続的なLinuxおよびmacOS仮想マシンです。各エージェントセッションには専用のマシンが割り当てられ、アイドル状態になると一時停止し、再開時にはファイルがそのまま維持されます。"
}
---
# サンドボックス {#sandboxes}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux と macOS の両方）は、キャパシティ増強中の現在、招待制となっています。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。Sandboxes が一般提供開始となった時点で、料金プランを発表します。

サンドボックスは、コーディングエージェントがコマンドを実行しファイルを編集するための仮想マシンです。各エージェントセッションには専用のサンドボックスが割り当てられ、セッションの間はチェックアウト内容、ビルド成果物、インストール済みツールが保持されます。エージェントがアイドル状態になるとサンドボックスは一時停止し、次のメッセージで中断した箇所から再開します。

サンドボックスは <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> と同じフリート上で実行され、チームの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> と隣接しているため、エージェントによるビルドは CI やローカルマシンと同じキャッシュアーティファクトを利用できます。

サンドボックスは以下の方法で利用できます。

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Amp ワークスペースの orb を Tuist で実行するか、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> を使用して任意の Amp スレッドに Xcode ビルド用の Mac を提供します。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Claude Managed Agents セッションおよび Claude Code クラウドセッション（claude.ai、デスクトップおよびモバイルアプリ、`claude --cloud`）を Tuist で実行します。
- **[The Tuist CLI](#cli)**: ターミナルからサンドボックスを作成してコマンドを実行したり、API を経由して独自のツールから操作したりできます。

## CLI で始める {#cli}

ターミナルで `tuist sandbox` を使用してサンドボックスを作成し、その中でコマンドを実行します。

### 1. ログイン {#cli-log-in}

アカウントのメンバーであれば誰でも、サンドボックスの作成と管理が可能です。

```bash
tuist auth login
```

### 2. サンドボックスを作成 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux の場合は `--platform` を省略してください。特定の [Xcode](#xcode) を搭載した Mac を用意するには、`--xcode` にバージョン（例: `--xcode 26.1.1`）を指定します。これにより `--platform macos` が隐含されます。より大きな [シェイプ](#platforms) を選択するには `--vcpus` と `--memory-gb` を、より大きなディスク容量を選択するには `--workspace-gb` を指定します。コマンドはサンドボックスが起動すると戻り、ID を含む詳細情報を出力します。カレントディレクトリの Tuist プロジェクトのアカウントが使用されます。別のアカウントを選択するには `--account` を指定してください。

### 3. コマンドを実行 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

コマンドはサンドボックス内で `bash -l` を使用して実行され、一時停止中であればまず再開されます。`tuist` は実行時間に関わらず出力をストリーミングし、コマンドのステータスで終了します。Ctrl-C でサンドボックス内の処理をキャンセルできます。必要に応じて `--cwd`、`--env NAME=VALUE`、`--timeout`（最大6時間）を指定してください。

### よくあるタスク {#cli-tasks}

| タスク | コマンド |
| --- | --- |
| サンドボックスの一覧表示 | `tuist sandbox list` |
| 1件を表示 | `tuist sandbox show <id>` |
| 一時停止または再開 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| ローカルの Git ワークツリーのファイルを同期 | `tuist sandbox sync <id>` |
| ファイルのコピー（出し入れ） | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 削除 | `tuist sandbox delete <id> --yes` |
| 使用状況を確認 | `tuist sandbox analytics` |

機械読み取り可能な出力を得るには `--json` を追加してください。すべてのオプションについては <.localized_link href="/cli/sandbox">CLI リファレンス</.localized_link> を参照してください。コードからサンドボックスを操作する場合は、[Tuist API](https://tuist.dev/api/docs) の `/api/accounts/{account_handle}/sandboxes` エンドポイントを通じて同じ操作を実行するか、エージェントに <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> を介して利用させます。

対話的にログインできないツール（macOS サンドボックスでビルドを行うエージェントプラグインなど）は、代わりに `account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> で認証できます。アカウントメンバーと同様に、サンドボックスの作成、コマンドの実行、一時停止、再開、アーカイブ、削除が可能です。統合設定はアカウント管理者が管理します。

### サンドボックス内の Tuist {#tuist-in-sandbox}

サンドボックスイメージには Tuist CLI が含まれていないため、プロジェクトでピン留めされたバージョンが実行されます。最初の `tuist sandbox sync` の後、サンドボックス上のリポジトリルートで `mise install` を実行します（`mise` および `brew` はインストール済み）。`tuist sandbox exec` で開始するすべてのコマンドでは、mise の shim（`$HOME/.local/share/mise/shims`）が `PATH` の先頭に配置されるため、`tuist` や他の mise ツールがコマンド内や Xcode のビルドフェーズ（スキームの post-actions など）で実行されます。

`tuist sandbox exec` で開始するすべてのコマンドは Tuist runner と同じ環境を受け取るため、サンドボックス内のビルドは資格情報を渡さなくてもアカウントの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> を利用できます。

- `TUIST_URL`、およびサンドボックスのホストから到達可能な場合（macOS など）、同じラック内のキャッシュの `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`。そのコマンド用の短期有効な ID トークンです。Tuist CLI 4.218.0 以降は自動的にこれでサインインします。4.215.0 ～ 4.217.x では、同じコマンド内で事前に `tuist auth login` を実行してください。

トークンはコマンドごとに発行され、そのコマンドの実行中のみ Tuist トークンと交換できるため、サンドボックスが長寿命の資格情報を保持することはありません。コマンドを開始した人物またはトークンがキャッシュに対して実行できる権限を超えることは決してありません。キャッシュ書き込みトークンのみを持つアカウントメンバーは読み取りアクセス権を得られ、サンドボックスがキャッシュを利用するには、`account:sandboxes:write` と併せて `ci` などのキャッシュスコープを持つアカウントトークンが必要です。`--env` で渡した変数が優先されます。

## コーディングエージェントから Mac でビルド {#coding-agents}

クラウドエージェントセッションなど Linux で動作するコーディングエージェントは、ファイル編集を実行環境で行いながら、macOS サンドボックス上で Apple プラットフォーム向けコードのビルド、テスト、実行を行えます。Amp では <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> をインストールしてください。Claude Code や Cursor などの他のエージェントの場合:

1. エージェントを Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP サーバー</.localized_link> に接続します。`create_sandbox` ツールが、エージェントに Mac の操作方法を指示します。
2. エージェントが実行される環境に Tuist CLI をインストールします。例えば環境のセットアップスクリプトで `mise use -g tuist@latest`、または `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM の場合は `tuist-linux-aarch64`）を実行します。
3. CLI を認証します。MCP サーバーのサインイン状態は引き継がれないため、アカウントメンバーとして `tuist auth login` を実行するか、`account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> を `TUIST_TOKEN` に設定してください。
4. 環境でネットワークアクセスが制限されている場合は、`tuist.dev` を許可してください。CLI はこれ経由で Mac にファイルをアップロードするため、他のドメインは必要ありません。

エージェントはタスクごとに 1 台の Mac を作成し、プロジェクトで固定された [Xcode](#xcode) を使用します。`create_sandbox` が選択可能な Xcode の一覧を表示し、エージェントにプロジェクトの固定バージョン（例: `.xcode-version`）を読み取るよう指示します。各コマンドの実行前に `tuist sandbox sync` を実行します。Git が無視しないファイル（コミット済みかどうかを問わず）をコピーし、その後は変更されたファイルのみをコピーします。初回同期後、Mac 上のリポジトリルートで `mise install` を実行するため、[プロジェクトで固定された Tuist](#tuist-in-sandbox) が利用可能になり、アカウントのキャッシュにサインインした状態になります。その後、エージェントは `tuist sandbox exec` を使って `xcodebuild` などのコマンドを実行し、`tuist sandbox cp` でスクリーンショットやビルド済みアプリなどの結果をコピーして戻し、タスク完了時に Mac を削除します。Mac は最後のコマンド実行後 10 分間稼働し続けるため、次のコマンドはすぐに開始されます。`tuist sandbox pause` を使えばより早く返却できます。放置された Mac は一時停止し、14 日間一時停止状態が続くと削除されます。

## Linux と macOS {#platforms}

**Linux** サンドボックスは Ubuntu 24.04 で動作します:

- 2 vCPU、4 GiB RAM（デフォルト）
- 4 vCPU、8 GiB RAM
- 8 vCPU、16 GiB RAM

**macOS** サンドボックスは Apple シリコン上で Xcode とともに動作します:

- 8 vCPU、8 GiB RAM（デフォルト）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

### Xcode の選択 {#xcode}

各 macOS サンドボックスは 1 つの Xcode で動作し、作成時に選択します。その Xcode 用の <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> プロファイルと同じイメージで起動するため、エージェントは CI と同じツールチェーンとシミュレーターでビルドを行います。tuist.dev では現在、以下の macOS サンドボックスを提供しています:

- `26.6`（デフォルト）
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

ランナープロファイルと同様に、正確なバージョンを指定して `xcode_version`（CLI では `--xcode`）で選択します:

| 場所 | 方法 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API および MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp 用 Tuist Mac プラグイン | `xcode` を指定した `tuist_mac_start` |
| Amp orbs | orb タイプ `macos-xcode-26-1-1`（<.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link> を参照） |
| Claude Code および Claude Managed Agents | 環境ごとの `xcode_version`、または Managed Agents セッションごと（<.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link> を参照） |

- **バージョンを指定しない場合**、Mac はデフォルトのバージョンを使用します。
- **Tuist が提供していないバージョンは拒否され**、エラーメッセージに選択可能なバージョンが一覧表示されるため、現在利用可能なバージョンを確認できます。
- **Tuist はリポジトリの `.xcode-version` を読み取りません。** バージョンはあなた自身、または Mac を要求するエージェントが選択します。MCP ツールと Tuist Mac プラグインは、エージェントにプロジェクトで固定されたバージョンと一致させるよう指示します。
- **サンドボックスはその Xcode を生涯保持します。** 別の Xcode でビルドするには、新しいサンドボックスを作成してください。`xcodebuild -version` で Mac が実行している Xcode を確認できます。

## セキュリティ {#security}

- 各サンドボックスは独立した仮想マシンです。サンドボックス同士、または CI ジョブとファイルシステム、メモリ、プロセスを共有しません。
- サンドボックスはアカウントに属し、そのメンバーはすべて、統合サービスを提供するサンドボックスを含めて、サンドボックスの使用と管理を行えます。統合サービスの接続は管理者のみが行えます。統合サービスからのセッションは、その統合サービスが接続されているアカウントのサンドボックスにのみアクセスできます。
- 統合サービスの接続のために Tuist に提供する資格情報（Amp プロバイダートークンや Claude 環境キーなど）は暗号化されて保存され、再度表示されることはありません。
- サンドボックスはインターネットにアクセスできます。エージェントがそこからアクセスできるものは、CI ジョブと同様に扱ってください。
