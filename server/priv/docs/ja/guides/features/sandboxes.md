---
{
  "title": "サンドボックス",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuistサンドボックスは、AmpやClaudeなどのコーディングエージェント向けに用意された永続的なLinuxおよびmacOS仮想マシンです。各エージェントセッションには専用のマシンが割り当てられ、アイドル状態になると一時停止し、再開時にはファイルがそのまま残っています。"
}
---
# サンドボックス {#sandboxes}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux および macOS）は、キャパシティ増強中の現在、招待制となっています。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。Sandboxes が一般提供開始され次第、料金プランを発表します。

サンドボックスは、コーディングエージェントがコマンドを実行しファイルを編集するための仮想マシンです。各エージェントセッションには専用のサンドボックスが割り当てられ、セッション存续中はチェックアウト内容、ビルド成果物、インストール済みツールが保持されます。エージェントがアイドル状態になるとサンドボックスは一時停止し、次のメッセージで中断した箇所から再開します。

サンドボックスは <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> と同じフリート上で実行され、チームの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> と隣接しているため、エージェントのビルドは CI やローカルマシンと同じキャッシュアーティファクトを利用できます。

サンドボックスは以下の方法で利用できます：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：Amp ワークスペースの Orb を Tuist で実行するか、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> を使用して任意の Amp スレッドに Xcode ビルド用の Mac を提供します。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：Claude Managed Agents セッションおよび Claude Code クラウドセッション（claude.ai、デスクトップおよびモバイルアプリ、`claude --cloud`）を Tuist で実行します。
- **[The Tuist CLI](#cli)**：ターミナルからサンドボックスを作成してコマンドを実行するか、API を介して独自のツールから操作します。

## CLI で始める {#cli}

`tuist sandbox` を使用して、ターミナルからサンドボックスを作成し、その中でコマンドを実行します。

### 1. ログイン {#cli-log-in}

アカウントのどのメンバーでも、サンドボックスの作成と管理が可能です：

```bash
tuist auth login
```

### 2. サンドボックスを作成 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux の場合は `--platform` を省略してください。特定の [Xcode](#xcode) を搭載した Mac 用には、バージョン（例：`--xcode 26.1.1`）を指定して `--xcode` を渡します。これは `--platform macos` を意味します。より大きな [シェイプ](#platforms) には `--vcpus` と `--memory-gb` を、Linux サンドボックスにより多くの [CPU](#guaranteed-cpu) を保証するには `--guaranteed-vcpus` を、より大きなディスクには `--workspace-gb` を指定します。コマンドはサンドボックスが実行状態になると戻り、ID を含む詳細情報を出力します。カレントディレクトリの Tuist プロジェクトのアカウントを使用します。別のアカウントを選択するには `--account` を渡してください。

### 3. コマンドを実行 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

コマンドはサンドボックス内で `bash -l` で実行され、一時停止中であればまず再開されます。`tuist` は実行時間に関わらず出力をストリーミングし、コマンドのステータスで終了します。Ctrl-C でサンドボックス内の処理をキャンセルできます。必要に応じて `--cwd`、`--env NAME=VALUE`、`--timeout`（最大6時間）を指定してください。

### よくあるタスク {#cli-tasks}

| タスク | コマンド |
| --- | --- |
| サンドボックスを一覧表示 | `tuist sandbox list` |
| 1つを表示 | `tuist sandbox show <id>` |
| 一時停止または再開 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| ローカルの Git ワークツリーのファイルをミラーリング | `tuist sandbox sync <id>` |
| ファイルを出し入れ | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 削除 | `tuist sandbox delete <id> --yes` |
| 使用状況を確認 | `tuist sandbox analytics` |

機械可読な出力を得るには `--json` を追加してください。すべてのオプションについては <.localized_link href="/cli/sandbox">CLI リファレンス</.localized_link> を参照してください。コードからサンドボックスを操作する場合は、`/api/accounts/{account_handle}/sandboxes` 下の [Tuist API](https://tuist.dev/api/docs) を介して同じ操作を行うか、エージェントに <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> を介して利用させます。

macOS サンドボックスでビルドするエージェントプラグインなど、対話的にログインできないツールは、代わりに `account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> で認証できます。アカウントメンバーと同様に、サンドボックスの作成、コマンドの実行、一時停止、再開、アーカイブ、削除が可能です。インテグレーションの設定はアカウント管理者が管理します。

### サンドボックス内の Tuist {#tuist-in-sandbox}

サンドボックスイメージには Tuist CLI が含まれていないため、プロジェクトでピン留めされたバージョンが実行されます。最初の `tuist sandbox sync` の後、サンドボックス上のリポジトリルートで `mise install` を実行します（`mise` および `brew` はインストール済み）。`tuist sandbox exec` で開始するすべてのコマンドでは、mise のシム（`$HOME/.local/share/mise/shims`）が `PATH` の先頭に配置されるため、`tuist` や他の mise ツールがコマンド内や Xcode ビルドフェーズ（スキームのポストアクションなど）で実行されます。

`tuist sandbox exec` で開始するすべてのコマンドは Tuist ランナーと同じ環境を受け取るため、サンドボックス内のビルドは資格情報を渡すことなくアカウントの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> を利用できます：

- `TUIST_URL`、および macOS などサンドボックスホストから到達可能な場合、同じラック内のキャッシュの `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`（そのコマンド用の短命な ID トークン）。Tuist CLI 4.218.0 以降はこれを使用して自動的にサインインします。4.215.0 ～ 4.217.x では、同じコマンド内で最初に `tuist auth login` を実行してください。

トークンは各コマンドごとに発行され、そのコマンドの実行中のみ Tuist トークンと交換できるため、サンドボックスが長寿命の資格情報を保持することはありません。コマンドを開始した人物またはトークンがキャッシュに対して実行できる操作以上に権限が付与されることはありません。キャッシュ書き込み権限がトークンのみに制限されているアカウントのメンバーは読み取りアクセスのみを得られ、サンドボックスがキャッシュを利用するには、アカウントトークンに `account:sandboxes:write` と併せて `ci` などのキャッシュスコープが必要です。`--env` で渡した変数が優先されます。

## コーディングエージェントから Mac でビルド {#coding-agents}

クラウドエージェントセッションなど Linux で実行されるコーディングエージェントは、ファイル編集を実行場所で継続しながら、macOS サンドボックス上で Apple プラットフォーム向けコードのビルド、テスト、実行を行えます。Amp では <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> をインストールしてください。Claude Code や Cursor などの他のエージェントの場合：

1. エージェントを Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP サーバー</.localized_link> に接続します。`create_sandbox` ツールがエージェントに Mac の操作方法を指示します。
2. エージェントが実行される環境に Tuist CLI をインストールします。例えば環境のセットアップスクリプトで：`mise use -g tuist@latest`、または `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM の場合は `tuist-linux-aarch64`）。
3. CLI を認証します。MCP サーバーのサインイン状態は引き継がれないため、アカウントメンバーとして `tuist auth login` を実行するか、`TUIST_TOKEN` に `account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> を設定してください。
4. 環境がネットワークアクセスを制限している場合は、`tuist.dev` を許可してください。CLI はこれを通じて Mac にファイルをアップロードするため、他のドメインは必要ありません。

エージェントはタスクごとに 1 台の Mac を作成し、プロジェクトで固定された [Xcode](#xcode) を使用します。`create_sandbox` が選択可能な Xcode の一覧を表示し、エージェントにプロジェクトの固定バージョン（例：`.xcode-version`）を読み取るよう指示します。各コマンドの実行前に `tuist sandbox sync` を実行します。Git が無視しないファイル（コミット済みかどうかに関わらず）をコピーし、以降は変更されたファイルのみをコピーします。初回同期後、Mac 上のリポジトリルートで `mise install` を実行するため、[プロジェクトで固定された Tuist](#tuist-in-sandbox) が配置され、アカウントのキャッシュにサインインした状態になります。その後、エージェントは `tuist sandbox exec` を使用して `xcodebuild` などのコマンドを実行し、`tuist sandbox cp` を使用してスクリーンショットやビルド済みアプリなどの結果をコピーバックし、タスク完了時に Mac を削除します。Mac は最後のコマンド実行後 10 分間稼働し続けるため、次のコマンドはすぐに開始されます。`tuist sandbox pause` を使用すればより早く返却できます。放置された Mac は一時停止し、14 日間一時停止状態が続くと削除されます。

## Linux と macOS {#platforms}

**Linux** サンドボックスは Ubuntu 24.04 で実行されます。すべての Linux サンドボックスは 16 vCPU を持ち、実行マシンのアイドルコアへバーストするため、シェイプによってメモリ容量が決まります。

- 2 GiB RAM（`--vcpus 1 --memory-gb 2`）
- 4 GiB RAM（`--vcpus 2 --memory-gb 4`、デフォルト）
- 8 GiB RAM（`--vcpus 4 --memory-gb 8`）
- 16 GiB RAM（`--vcpus 8 --memory-gb 16`）
- 32 GiB RAM（`--vcpus 16 --memory-gb 32`）
- 44 GiB RAM（`--vcpus 16 --memory-gb 44`）

**macOS** サンドボックスは Apple silicon 上で Xcode とともに実行されます。

- 8 vCPU、8 GiB RAM（デフォルト）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

### 保証付き CPU {#guaranteed-cpu}

Linux サンドボックスはメモリ 1 GiB あたり vCPU の 4 分の 1 が保証され（例：8 GiB で 2 vCPU）、マシンのアイドル状況に応じて最大 16 vCPU までバーストします。これは主に待機し、ビルド時にバーストするエージェントに適しています。負荷の高いマシンでもビルドにより安定した CPU が必要な場合は、サンドボックス作成時に 1、2、4、または 8 vCPU を保証してください。保証値とメモリに基づく保証値のうち大きい方が適用されます。

| 場所 | 方法 |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API および MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **保証は下限であり、上限ではありません。** 4 vCPU が保証されたサンドボックスでも、コアがアイドル状態であれば 16 vCPU までバーストします。競合時には、各サンドボックスは保証値に比例して CPU を割り当てられます。
- **最小保証分として課金されます。** 稼働中のサンドボックスは使用した CPU に対して課金されますが、保証値を下回ることはありません。
- **サンドボックスの保証は生涯維持されます。** 変更するには、新しいサンドボックスを作成してください。
- **macOS サンドボックスは常に完全なシェイプを持ちます**。そのため、保証は適用されません。

### Xcode の選択 {#xcode}

各 macOS サンドボックスは 1 つの Xcode で実行され、作成時に選択します。その Xcode 用の <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> プロファイルと同じイメージで起動するため、エージェントは CI と同じツールチェーンとシミュレーターでビルドを行います。tuist.dev では現在、以下の macOS サンドボックスを提供しています。

- `26.6`（デフォルト）
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

ランナープロファイルと同様に、正確なバージョンを指定して `xcode_version`（CLI では `--xcode`）で選択してください。

| 場所 | 方法 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API および MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp 用 Tuist Mac プラグイン | `xcode` を指定した `tuist_mac_start` |
| Amp orbs | Orb タイプ `macos-xcode-26-1-1`（<.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link> を参照） |
| Claude Code および Claude Managed Agents | 環境ごとの `xcode_version`、または Managed Agents セッションごと（<.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link> を参照） |

- **バージョンを指定しない場合**、Mac はデフォルトバージョンを使用します。
- **Tuist が提供していないバージョンは拒否されます**。エラーメッセージには選択可能なバージョンが一覧表示されるため、現在利用可能なバージョンを確認できます。
- **Tuist はリポジトリの `.xcode-version` を読み取りません。** バージョンはあなた自身、または Mac を要求するエージェントが選択します。MCP ツールと Tuist Mac プラグインは、プロジェクトでピン留めされたバージョンに一致させるようエージェントに指示します。
- **サンドボックスの Xcode は生涯維持されます。** 別の Xcode でビルドするには、新しいサンドボックスを作成してください。`xcodebuild -version` は、Mac が実行している Xcode のバージョンを表示します。

## セキュリティ {#security}

- 各サンドボックスは独立した仮想マシンです。サンドボックス同士、あるいは CI ジョブとファイルシステム、メモリ、プロセスを共有することはありません。
- サンドボックスはアカウントに属し、そのメンバーは誰でも（統合サービスを提供するサンドボックスを含めて）使用および管理できます。統合サービスの接続は管理者のみが行えます。統合サービスからのセッションは、その統合サービスが接続されているアカウントのサンドボックスにのみアクセスできます。
- Amp プロバイダートークンや Claude 環境キーなど、統合サービスの接続のために Tuist に提供する認証情報は暗号化されて保存され、二度と表示されることはありません。
- サンドボックスはインターネットにアクセスできます。エージェントがそこからアクセスできるものは、CI ジョブと同様に扱ってください。
