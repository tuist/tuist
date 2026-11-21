---
{
  "title": "サンドボックス",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Sandboxes は、Amp や Claude などのコーディングエージェント向けの永続的な Linux および macOS 仮想マシンです。各エージェントセッションは専用のマシンで実行され、アイドル状態になると一時停止し、ファイルはそのままの状態で再開されます。"
}
---
# サンドボックス {#sandboxes}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux と macOS の両方）は、キャパシティを拡張している間、現在招待制となっています。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。Sandboxes が一般提供開始となった時点で、料金プランを発表します。

サンドボックスは、コーディングエージェントがコマンドを実行し、ファイルを編集するための仮想マシンです。各エージェントセッションには専用のサンドボックスが割り当てられ、セッションの間、チェックアウト状態、ビルド成果物、インストール済みツールが保持されます。エージェントがアイドル状態になるとサンドボックスは一時停止し、次のメッセージで中断した箇所から再開されます。

サンドボックスは <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> と同じフリート上で実行され、チームの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> と隣接しているため、エージェントによるビルドは CI やローカルマシンと同じキャッシュされたアーティファクトを利用できます。

サンドボックスは以下の方法で利用できます：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：Amp ワークスペースの orbs を Tuist で実行するか、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> を使用して任意の Amp スレッドに Xcode ビルド用の Mac を提供します。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：Claude Managed Agents セッションおよび Claude Code クラウドセッション（claude.ai、デスクトップおよびモバイルアプリ、`claude --cloud`）を Tuist で実行します。
- **[The Tuist CLI](#cli)**：ターミナルからサンドボックスを作成してコマンドを実行したり、API を経由して独自のツールから操作したりできます。

## CLI で始める {#cli}

`tuist sandbox` を使用して、ターミナルからサンドボックスを作成し、その中でコマンドを実行します。

### 1. ログイン {#cli-log-in}

アカウントのメンバーであれば誰でも、サンドボックスの作成と管理が可能です：

```bash
tuist auth login
```

### 2. サンドボックスを作成する {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux の場合は `--platform` を省略してください。特定の [Xcode](#xcode) がインストールされた Mac を用意するには、バージョンを指定して `--xcode` を渡します（例：`--xcode 26.1.1`）。これにより `--platform macos` が暗黙的に指定されます。より大きな [シェイプ](#platforms) を選択するには `--vcpus` と `--memory-gb` を渡し、Linux サンドボックスでより多くの [CPU](#guaranteed-cpu) リソースを保証するには `--guaranteed-vcpus` を渡し、より大きなディスク容量が必要な場合は `--workspace-gb` を渡します。コマンドはサンドボックスの実行が開始されると完了し、ID を含む詳細情報を出力します。カレントディレクトリの Tuist プロジェクトのアカウントが使用されます。別のアカウントを選択するには `--account` を渡してください。

### 3. コマンドを実行する {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

コマンドはサンドボックス内で `bash -l` によって実行され、一時停止中であればまず再開されます。`tuist` はコマンドの実行時間がどれだけ長くても出力をストリーミングし、コマンドのステータスコードで終了します。Ctrl-C でサンドボックス内の処理をキャンセルできます。必要に応じて `--cwd`、`--env NAME=VALUE`、および `--timeout`（最大6時間）を渡してください。

コマンドは `tuist` からデタッチされて実行されるため、接続が切断されても継続します。エージェントなど、時間制限のあるツール呼び出しの中に長時間のビルドを組み込む場合は、`--wait <seconds>` を渡してください。タイムアウトが先に発生すると、`tuist` はコマンドを実行したままステータスコード 75 で終了し、中断した箇所から出力を継続してコマンドのステータスコードで終了する `tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …` コマンドを表示します。

### よくあるタスク {#cli-tasks}

| タスク | コマンド |
| --- | --- |
| サンドボックスの一覧表示 | `tuist sandbox list` |
| 1つを表示 | `tuist sandbox show <id>` |
| 一時停止または再開 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| ローカルの Git ワークツリーのファイルをミラーリング | `tuist sandbox sync <id>` |
| ファイルのコピー（送受信） | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 削除 | `tuist sandbox delete <id> --yes` |
| 使用状況を確認 | `tuist sandbox analytics` |

機械読み取り可能な出力を得るには `--json` を追加してください。すべてのオプションについては <.localized_link href="/cli/sandbox">CLI リファレンス</.localized_link> を参照してください。コードからサンドボックスを操作する場合は、`/api/accounts/{account_handle}/sandboxes` 下の [Tuist API](https://tuist.dev/api/docs) を介して同じ操作を実行するか、エージェントに <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> を介して利用させます。

対話的なログインができないツール（macOS サンドボックスでビルドを行うエージェントプラグインなど）は、代わりに `account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> で認証できます。これはアカウントメンバーと同様に、サンドボックスの作成、コマンドの実行、一時停止、再開、アーカイブ、削除を行えます。統合設定はアカウント管理者が管理します。

### サンドボックス内の Tuist {#tuist-in-sandbox}

macOS サンドボックスには Tuist CLI が付属しています。プロジェクトが mise（`mise.toml` または `.tool-versions`）を通じて Tuist のバージョンを固定している場合、`tuist` はそのバージョンを実行します。このバージョンは、コマンドが初めて必要とした際にインストールされます。`tuist sandbox exec` で開始するすべてのコマンドでは、mise の shim（`$HOME/.local/share/mise/shims`）が `PATH` の先頭に配置され、イメージ内の Tuist が最後に配置されるため、`tuist` および他の mise ツールは、コマンド内やスキームの post-actions などの Xcode ビルドフェーズで実行されます。各 Mac には `/opt/tuist/agent-guide.md` にコーディングエージェント向けのガイドが含まれており、これはイメージから生成されます。ガイドには、Xcode とシミュレータ、リポジトリの場所、準備済みスナップショットの内容が記載されています。Mac 上で実行されている Claude Code、Codex、Amp は、それぞれの指示ファイルからこのガイドを検索します。

`tuist sandbox exec` で開始するすべてのコマンドは、Tuist ランナーと同じ環境を受け取るため、サンドボックス内のビルドは資格情報を渡すことなくアカウントの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> を利用できます：

- `TUIST_URL`、およびサンドボックスのホストから到達可能な場合（macOS など）、同じラック内のキャッシュの `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`。これはそのコマンド用の短命な ID トークンです。Tuist CLI 4.218.0 以降は自動的にこれでサインインします。4.215.0 ～ 4.217.x では、同じコマンド内で最初に `tuist auth login` を実行してください。

トークンはコマンドごとに発行され、そのコマンドの実行中のみ Tuist トークンと交換できるため、サンドボックスが長寿命の資格情報を保持することはありません。トークンは、コマンドを開始した人物またはトークンがキャッシュに対して実行できる権限を超える権限を付与しません。キャッシュ書き込みトークンのみを持つアカウントメンバーは読み取りアクセス権を取得し、アカウントトークンがキャッシュを使用するには、`account:sandboxes:write` とともに `ci` などのキャッシュスコープが必要です。`--env` で渡した変数が優先されます。

## コーディングエージェントから Mac でビルドする {#coding-agents}

クラウドエージェントセッションなど、Linux で実行されるコーディングエージェントは、実行場所でファイルを編集し続けながら、macOS サンドボックス上で Apple プラットフォーム向けコードのビルド、テスト、実行を行えます。Amp では、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> をインストールしてください。Claude Code や Cursor などの他のエージェントの場合：

1. エージェントを Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP サーバー</.localized_link> に接続します。その `create_sandbox` ツールが、エージェントに Mac の操作方法を指示します。
2. エージェントが実行される環境に Tuist CLI をインストールします。例えば、環境のセットアップスクリプトで `mise use -g tuist@latest` を実行するか、`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` を実行します（ARM の場合は `tuist-linux-aarch64`）。
3. CLI を認証します。MCP サーバーのサインインは引き継がれないため、アカウントメンバーとして `tuist auth login` を実行するか、`TUIST_TOKEN` に `account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> を設定してください。
4. 環境がネットワークアクセスを制限している場合は、`tuist.dev` を許可してください。CLI はこれを通じて Mac にファイルをアップロードするため、他のドメインは不要です。

エージェントはタスクごとに 1 台の Mac を作成し、プロジェクトがピン留めした [Xcode](#xcode) を使用します。`create_sandbox` は選択可能な Xcode の一覧を表示し、エージェントにプロジェクトのピン（例：`.xcode-version`）を読み取るよう指示します。各コマンドの実行前に `tuist sandbox sync` を実行します。Git が無視しないファイル（コミット済みかどうかを問わず）をコピーし、その後に変更されたファイルのみをコピーします。Mac にはすでに [Tuist](#tuist-in-sandbox)（プロジェクトがバージョンをピン留めしている場合はそのバージョン）がインストールされ、アカウントのキャッシュにサインイン済みであり、エージェントは Mac のガイドを一度読み取ります。その後、エージェントは `tuist sandbox exec` を使用して `xcodebuild` などのコマンドを実行し、`tuist sandbox cp` を使用してスクリーンショットやビルド済みアプリなどの結果をコピーバックし、タスク完了後に Mac を削除します。Mac は最後のコマンド実行後 10 分間実行状態を維持するため、次のコマンドはすぐに開始されます。`tuist sandbox pause` を使用すれば、より早くリソースを返却できます。放置された Mac は一時停止し、14 日間一時停止状態が続くと削除されます。

## Linux と macOS {#platforms}

**Linux** サンドボックスは Ubuntu 24.04 で実行されます。すべての Linux サンドボックスは 16 vCPU を持ち、実行マシンのアイドルコアへバーストするため、シェイプによってメモリ容量が決まります：

- 2 GiB RAM (`--vcpus 1 --memory-gb 2`)
- 4 GiB RAM (`--vcpus 2 --memory-gb 4`、デフォルト)
- 8 GiB RAM (`--vcpus 4 --memory-gb 8`)
- 16 GiB RAM (`--vcpus 8 --memory-gb 16`)
- 32 GiB RAM (`--vcpus 16 --memory-gb 32`)
- 44 GiB RAM (`--vcpus 16 --memory-gb 44`)

**macOS** サンドボックスは Apple Silicon 上で Xcode とともに実行されます：

- 8 vCPU、8 GiB RAM（デフォルト）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

### 保証 CPU {#guaranteed-cpu}

Linux サンドボックスは、メモリ 1 GiB あたり vCPU の 4 分の 1 を保証されます（例：8 GiB で 2 vCPU）。マシンのアイドル状態に応じて最大 16 vCPU まで追加使用できます。これは、主に待機しバースト的にビルドを行うエージェントに適しています。混雑したマシンでもビルドにより安定した CPU が必要な場合は、サンドボックス作成時に 1、2、4、または 8 vCPU を保証してください。サンドボックスは、その値とメモリによる保証値のうち大きい方を取得します：

| 場所 | 方法 |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API および MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **保証は下限であり、上限ではありません。** 4 vCPU を保証されたサンドボックスでも、コアがアイドル状態であれば 16 vCPU までバーストします。競合状态下では、各サンドボックスは保証値に比例して CPU を取得します。
- **最小値として課金されます。** 実行中のサンドボックスは使用した CPU に対して課金されますが、保証値を下回ることはありません。
- **サンドボックスは作成から削除まで保証値を維持します。** 変更するには、新しいサンドボックスを作成してください。
- **macOS サンドボックスは常に完全なシェイプを持ちます**。したがって、保証を設定しません。

### Xcode の選択 {#xcode}

各 macOS サンドボックスは 1 つの Xcode で実行され、作成時に選択します。その Xcode に対応する <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> プロファイルと同じイメージで起動するため、エージェントは CI と同じツールチェーンとシミュレーターでビルドを行います。tuist.dev では現在、macOS サンドボックスで以下を提供しています：

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
| Amp orbs | Orb タイプ `macos-xcode-26-1-1`（<.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link> を参照） |
| Claude Code および Claude Managed Agents | 環境ごとの `xcode_version`、または Managed Agents セッションごと（<.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link> を参照） |

- **バージョンを指定しない場合**、Mac はデフォルト値を使用します。
- **Tuist が提供していないバージョンは拒否されます**。エラーには選択可能なバージョンが一覧表示されるため、現在利用可能なバージョンを確認できます。
- **Tuist はリポジトリの `.xcode-version` を読み取りません。** バージョンはあなた自身、または Mac を要求するエージェントが選択します。MCP ツールと Tuist Mac プラグインは、プロジェクトでピン留めされたバージョンに一致させるようエージェントに指示します。
- **サンドボックスは作成から削除まで Xcode を維持します。** 別の Xcode でビルドするには、新しいサンドボックスを作成してください。`xcodebuild -version` は Mac で実行されている Xcode を示します。

## セキュリティ {#security}

- 各サンドボックスは独立した仮想マシンです。サンドボックス同士、または CI ジョブ間でファイルシステム、メモリ、プロセスを共有することはありません。
- サンドボックスはアカウントに属し、そのメンバーは誰でも統合サービスを提供するサンドボックスを含めて使用および管理できます。統合の接続は管理者のみが行えます。統合からのセッションは、その統合が接続されているアカウントのサンドボックスにのみアクセスできます。
- Amp プロバイダートークンや Claude 環境キーなど、統合の接続のために Tuist に提供する認証情報は暗号化されて保存され、二度と表示されることはありません。
- サンドボックスはインターネットにアクセスできます。エージェントがそこからアクセスできるものは、CI ジョブと同様に扱ってください。
