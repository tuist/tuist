---
{
  "title": "サンドボックス",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist サンドボックスは、Amp や Claude などのコーディングエージェント向けに用意された永続的な Linux および macOS 仮想マシンです。各エージェントセッションには専用のマシンが割り当てられ、アイドル状態になると一時停止し、ファイルはそのままの状態で再開されます。"
}
---
# サンドボックス {#sandboxes}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux と macOS の両方）は、キャパシティ拡張中の現在、招待制となっています。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。Sandboxes が一般提供開始された時点で、料金プランを発表します。

サンドボックスは、コーディングエージェントがコマンドを実行しファイルを編集するための仮想マシンです。各エージェントセッションには専用のサンドボックスが割り当てられ、セッション存続中はチェックアウト内容、ビルド成果物、インストール済みツールが保持されます。エージェントがアイドル状態になるとサンドボックスは一時停止し、次のメッセージで中断した箇所から再開します。

サンドボックスは <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> と同じフリート上で、チームの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> と並んで実行されるため、エージェントのビルドは CI やローカルマシンと同じキャッシュ成果物を利用できます。

サンドボックスは以下の方法で利用できます：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：Amp ワークスペースの orbs を Tuist で実行するか、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> を使用して任意の Amp スレッドに Xcode ビルド用の Mac を提供します。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：Claude Managed Agents セッションと Claude Code クラウドセッション（claude.ai、デスクトップおよびモバイルアプリ、`claude --cloud`）を Tuist で実行します。
- **[Tuist CLI](#cli)**：ターミナルからサンドボックスを作成してコマンドを実行するか、API を介して独自のツールから操作します。

## CLI で始める {#cli}

`tuist sandbox` を使用して、ターミナルからサンドボックスを作成し、その中でコマンドを実行します。

### 1. ログイン {#cli-log-in}

アカウントのメンバーであれば誰でも、サンドボックスの作成と管理が可能です：

```bash
tuist auth login
```

### 2. サンドボックスを作成 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux の場合は `--platform` を省略してください。特定の [Xcode](#xcode) を搭載した Mac を用意するには、`--xcode 26.1.1` のようにバージョンを指定して `--xcode` を渡します（これにより `--platform macos` が暗黙的に指定されます）。より大きな [シェイプ](#platforms) を選択するには `--vcpus` と `--memory-gb` を、より大きなディスク容量を選択するには `--workspace-gb` を指定します。サンドボックスが実行状態になるとコマンドは完了し、ID を含む詳細情報が出力されます。カレントディレクトリの Tuist プロジェクトのアカウントが使用されます。別のアカウントを選択するには `--account` を指定してください。

### 3. コマンドを実行 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

コマンドはサンドボックス内で `bash -l` として実行され、一時停止中であればまず再開されます。`tuist` は実行時間がどれだけ長くても出力をストリーミングし、コマンドのステータスで終了します。Ctrl-C でサンドボックス内の処理をキャンセルできます。必要に応じて `--cwd`、`--env NAME=VALUE`、`--timeout`（最大6時間）を指定してください。

### 一般的なタスク {#cli-tasks}

| タスク | コマンド |
| --- | --- |
| サンドボックスを一覧表示 | `tuist sandbox list` |
| 1件を表示 | `tuist sandbox show <id>` |
| 一時停止または再開 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| ローカルの Git ワークツリーのファイルをミラーリング | `tuist sandbox sync <id>` |
| ファイルのコピー（出し入れ） | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 削除 | `tuist sandbox delete <id> --yes` |
| 使用状況を確認 | `tuist sandbox analytics` |

機械可読な出力を得るには `--json` を追加してください。すべてのオプションについては <.localized_link href="/cli/sandbox">CLI リファレンス</.localized_link> を参照してください。コードからサンドボックスを操作する場合は、`/api/accounts/{account_handle}/sandboxes` 下の [Tuist API](https://tuist.dev/api/docs) を介して同じ操作を行うか、エージェントに <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> を介して利用させます。

対話的なログインができないツール（macOS サンドボックスでビルドを行うエージェントプラグインなど）は、代わりに `account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> で認証できます。アカウントメンバーと同様に、サンドボックスの作成、コマンドの実行、一時停止、再開、アーカイブ、削除が可能です。統合設定はアカウント管理者が管理します。

### サンドボックス内の Tuist {#tuist-in-sandbox}

サンドボックスイメージには Tuist CLI が含まれていないため、プロジェクトでピン留めされたバージョンが実行されます。最初の `tuist sandbox sync` の後、サンドボックス上のリポジトリルートで `mise install` を実行します（`mise` と `brew` はインストール済み）。その後、mise を介して `tuist` を実行します。例えば、`PATH` 上の `$HOME/.local/share/mise/shims` を使用します。

`tuist sandbox exec` で開始するすべてのコマンドは、Tuist ランナーと同様の環境を受け取るため、サンドボックス内のビルドは資格情報を渡すことなくアカウントの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> を利用できます：

- `TUIST_URL`、および macOS などサンドボックスのホストから到達可能な場合、同じラック内にあるキャッシュの `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`：そのコマンド用の短命な ID トークンです。Tuist CLI 4.218.0 以降は自動的にこれでサインインします。4.215.0 ～ 4.217.x では、同じコマンド内で事前に `tuist auth login` を実行してください。

トークンはコマンドごとに発行され、そのコマンドの実行中のみ Tuist トークンと交換できるため、サンドボックスが長寿命の資格情報を保持することはありません。コマンドを開始した人物またはトークンがキャッシュに対して実行できる権限を超える権限は付与されません。キャッシュトークンの書き込み権限のみを持つアカウントメンバーは読み取りアクセスを得ており、サンドボックスがキャッシュを使用するには、`account:sandboxes:write` に加えて `ci` などのキャッシュスコープを持つアカウントトークンが必要です。`--env` で渡した変数が優先されます。

## コーディングエージェントから Mac でビルド {#coding-agents}

クラウドエージェントセッションなど Linux で動作するコーディングエージェントは、実行場所でファイルを編集し続けながら、macOS サンドボックス上で Apple プラットフォーム向けコードのビルド、テスト、実行を行えます。Amp では <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> をインストールしてください。Claude Code や Cursor などの他のエージェントの場合：

1. エージェントを Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP サーバー</.localized_link> に接続します。MCP サーバーの `create_sandbox` ツールが、Mac を操作する方法をエージェントに指示します。
2. エージェントが実行される環境に Tuist CLI をインストールします。例えば環境のセットアップスクリプトで：`mise use -g tuist@latest`、または `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM の場合は `tuist-linux-aarch64`）。
3. CLI を認証します。MCP サーバーのサインイン状態は引き継がれないため、アカウントメンバーとして `tuist auth login` を実行するか、`account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> を `TUIST_TOKEN` に設定してください。
4. 環境がネットワークアクセスを制限している場合は、`tuist.dev` を許可してください。CLI はこれを通じて Mac にファイルをアップロードするため、他のドメインは必要ありません。

エージェントはタスクごとに 1 台の Mac を作成し、プロジェクトでピン留めされた [Xcode](#xcode) を使用します。`create_sandbox` は選択可能な Xcode の一覧を表示し、`.xcode-version` などのプロジェクトのピンを読み取るようエージェントに指示します。各コマンドの実行前に `tuist sandbox sync` を実行します。Git が無視しないファイル（コミット済みかどうかに関わらず）をコピーし、以降は変更されたファイルのみをコピーします。初回同期後、Mac 上のリポジトリルートで `mise install` を実行し、アカウントのキャッシュにサインインした状態の [プロジェクトでピン留めされた Tuist](#tuist-in-sandbox) を準備します。その後、エージェントは `tuist sandbox exec` を使って `xcodebuild` などのコマンドを実行し、`tuist sandbox cp` でスクリーンショットやビルド済みアプリなどの結果をコピーバックし、タスク完了時に Mac を削除します。Mac は最後のコマンド実行後 10 分間稼働し続けるため、次のコマンドはすぐに開始されます。`tuist sandbox pause` を実行すればより早く返却できます。放置された Mac は一時停止し、14 日間一時停止状態が続くと削除されます。

## Linux と macOS {#platforms}

**Linux** サンドボックスは Ubuntu 24.04 で動作します：

- 2 vCPU、4 GiB RAM（デフォルト）
- 4 vCPU、8 GiB RAM
- 8 vCPU、16 GiB RAM

**macOS** サンドボックスは Apple silicon 上で Xcode とともに動作します：

- 8 vCPU、8 GiB RAM（デフォルト）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

### Xcode の選択 {#xcode}

各 macOS サンドボックスは 1 つの Xcode で動作し、作成時に選択します。その Xcode に対応する <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> プロファイルと同じイメージで起動するため、エージェントは CI と同じツールチェーンとシミュレーターでビルドを行います。tuist.dev では現在、以下の macOS サンドボックスを提供しています：

- `26.6`（デフォルト）
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

ランナープロファイルと同様に、正確なバージョンを指定して `xcode_version`（CLI では `--xcode`）で選択します：

| 場所 | 方法 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API および MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp 用 Tuist Mac プラグイン | `xcode` を指定した `tuist_mac_start` |
| Amp orbs | orb タイプ `macos-xcode-26-1-1`（<.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link> を参照） |
| Claude Code および Claude Managed Agents | 環境ごとの `xcode_version`、または Managed Agents セッションごと（<.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link> を参照） |

- **バージョンを指定しない場合**、Mac はデフォルトバージョンを使用します。
- **Tuist が提供していないバージョンは拒否され**、エラーメッセージに選択可能なバージョンが一覧表示されるため、現在利用可能なバージョンを確認できます。
- **Tuist はリポジトリの `.xcode-version` を読み取りません。** バージョンはあなた自身、または Mac を要求するエージェントが選択します。MCP ツールと Tuist Mac プラグインは、プロジェクトでピン留めされたバージョンに合わせるようエージェントに指示します。
- **サンドボックスはその寿命の間、Xcode を維持します。** 別の Xcode でビルドするには、新しいサンドボックスを作成してください。`xcodebuild -version` は Mac が実行している Xcode を示します。

## セキュリティ {#security}

- 各サンドボックスは独立した仮想マシンです。サンドボックス同士、または CI ジョブとファイルシステム、メモリ、プロセスを共有しません。
- サンドボックスはアカウントに属しており、そのメンバーはすべて、統合サービスを提供するサンドボックスを含めて、サンドボックスの使用と管理を行えます。統合サービスの接続は管理者のみが行えます。統合サービスからのセッションは、その統合サービスが接続されているアカウントのサンドボックスにのみアクセスできます。
- Amp プロバイダートークンや Claude 環境キーなど、統合サービスの接続のために Tuist に提供する資格情報は暗号化されて保存され、二度と表示されることはありません。
- サンドボックスはインターネットにアクセスできます。エージェントがそこからアクセスできるものは、CI ジョブと同様に扱ってください。
