---
{
  "title": "サンドボックス",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuistサンドボックスは、AmpやClaudeなどのコーディングエージェント向けの永続的なLinuxおよびmacOS仮想マシンです。各エージェントセッションには専用のマシンが割り当てられ、アイドル状態になると一時停止し、ファイルはそのままで再開します。"
}
---
# サンドボックス {#sandboxes}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux と macOS の両方）は、キャパシティを拡張している間、現在招待制となっています。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。Sandboxes が一般公開される際に、料金プランを発表します。

サンドボックスは、コーディングエージェントがコマンドを実行し、ファイルを編集する仮想マシンです。各エージェントセッションには独自のサンドボックスが割り当てられ、セッションの間、チェックアウト、ビルド成果物、インストール済みツールが保持されます。エージェントがアイドル状態になるとサンドボックスは一時停止し、次のメッセージで中断した箇所から再開されます。

サンドボックスは <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> と同じフリート上で実行され、チームの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> の隣に配置されるため、エージェントのビルドは CI やローカルマシンと同じキャッシュされたアーティファクトを利用できます。

サンドボックスは以下の方法で利用できます：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：Amp ワークスペースの orb を Tuist で実行するか、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> を使用して任意の Amp スレッドに Xcode ビルド用の Mac を提供します。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：Claude Managed Agents セッションと Claude Code クラウドセッション（claude.ai、デスクトップおよびモバイルアプリ、および `claude --cloud`）を Tuist で実行します。
- **[The Tuist CLI](#cli)**：ターミナルからサンドボックスを作成してコマンドを実行するか、API を介して独自のツールから操作します。

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

Linux の場合は `--platform` を省略してください。特定の [Xcode](#xcode) がインストールされた Mac が必要な場合は、`--xcode` にバージョン（例：`--xcode 26.1.1`）を指定します。これにより `--platform macos` が暗黙的に指定されます。より大きな [シェイプ](#platforms) を選択するには `--vcpus` と `--memory-gb` を指定し、Linux サンドボックスでより多くの [CPU](#guaranteed-cpu) を保証するには `--guaranteed-vcpus` を指定し、より大きなディスク容量には `--workspace-gb` を指定します。サンドボックスは作成時から2時間実行され、再開ごとに再度2時間実行されます。5分から1日の間で設定するには `--lifetime-minutes` を指定します。有効期限が切れると、実行中のコマンドはキャンセルされ、サンドボックスは一時停止されてアーカイブされます（ファイルは保持されます）。これにより、忘れられたサンドボックスがアカウントのキャパシティを消費し続けるのを防ぎます。コマンドはサンドボックスが実行状態になると戻り、ID を含む詳細情報を出力します。カレントディレクトリの Tuist プロジェクトのアカウントが使用されます。別のアカウントを選択するには `--account` を指定してください。

### 3. コマンドを実行 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

コマンドはサンドボックス内で `bash -l` を使用して実行され、一時停止されている場合はまず再開されます。`tuist` はコマンドの実行時間がどれだけ長くても出力をストリーミングし、コマンドのステータスで終了します。Ctrl-C でサンドボックス内のコマンドをキャンセルできます。必要に応じて `--cwd`、`--env NAME=VALUE`、および `--timeout`（最大6時間）を指定してください。

コマンドは `tuist` からデタッチして実行されるため、接続が切断されても継続します。エージェントなど時間制限のあるツール呼び出しで長時間のビルドを実行するには、`--wait <seconds>` を指定します。この制限が先に経過すると、`tuist` はコマンドを実行したまま終了コード 75 で終了し、中断した箇所から出力を継続してコマンドのステータスで終了する `tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …` コマンドを出力します。

### よくあるタスク {#cli-tasks}

| タスク | コマンド |
| --- | --- |
| サンドボックスの一覧表示 | `tuist sandbox list` |
| 1つを表示 | `tuist sandbox show <id>` |
| 一時停止または再開 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 有効期限を超えて実行を継続 | `tuist sandbox extend <id> --lifetime-minutes 240` |
| ローカルの Git ワークツリーのファイルをミラーリング | `tuist sandbox sync <id>` |
| ファイルのコピー（送受信） | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 削除 | `tuist sandbox delete <id> --yes` |
| 使用状況を確認 | `tuist sandbox analytics` |

機械読み取り可能な出力を得るには `--json` を追加してください。すべてのオプションについては <.localized_link href="/cli/sandbox">CLI リファレンス</.localized_link> を参照してください。コードからサンドボックスを操作する場合は、`/api/accounts/{account_handle}/sandboxes` 下の [Tuist API](https://tuist.dev/api/docs) を介して同じ操作を行うか、エージェントに <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> を介して使用させます。

対話的なログインができないツール（macOS サンドボックスでビルドするエージェントプラグインなど）は、代わりに `account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> で認証できます。これはアカウントメンバーと同様の操作（サンドボックスの作成、コマンドの実行、一時停止、再開、アーカイブ、削除）を実行できます。統合設定はアカウント管理者が管理します。

### サンドボックス内の Tuist {#tuist-in-sandbox}

macOS サンドボックスには Tuist CLI が含まれています。プロジェクトが mise（`mise.toml` または `.tool-versions`）を通じて Tuist のバージョンを固定している場合、`tuist` はコマンドが初めて必要としたときにインストールされたそのバージョンを実行します。`tuist sandbox exec` で開始するすべてのコマンドでは、mise のシム（`$HOME/.local/share/mise/shims`）が `PATH` の先頭に配置され、イメージの Tuist が最後になるため、`tuist` や他の mise ツールはコマンド内や Xcode のビルドフェーズ（スキームのポストアクションなど）で実行されます。各 Mac には `/opt/tuist/agent-guide.md` にコーディングエージェント向けのガイドがあり、これはイメージから生成されます。このガイドには、Xcode とシミュレータ、リポジトリの場所、準備済みスナップショットの内容が含まれています。Mac 上で実行されている Claude Code、Codex、Amp は、指示ファイルからこのガイドを見つけます。

`tuist sandbox exec` で開始するすべてのコマンドは、Tuist ランナーと同様の環境を受け取るため、サンドボックス内のビルドは資格情報を渡さなくてもアカウントの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> を利用できます：

- `TUIST_URL`、およびサンドボックスのホストから到達可能な場合（macOS など）、同じラック内のキャッシュの `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`。これはそのコマンド用の短命な ID トークンです。Tuist CLI 4.218.0 以降は自動的にこれでサインインします。4.215.0 ～ 4.217.x では、同じコマンド内で最初に `tuist auth login` を実行してください。

トークンはコマンドごとに発行され、そのコマンドの実行中のみ Tuist トークンと交換できるため、サンドボックスが長寿命の資格情報を保持することはありません。このトークンは、コマンドを開始した人物またはトークンがキャッシュに対して実行できる操作を超える権限を付与しません。キャッシュトークンの書き込みのみが許可されているアカウントのメンバーは読み取りアクセス権限を得て、サンドボックスがキャッシュを使用するには、アカウントトークンに `account:sandboxes:write` と併せて `ci` などのキャッシュスコープが必要です。`--env` で渡した変数が優先されます。

## コーディングエージェントから Mac でビルド {#coding-agents}

クラウドエージェントセッションなど Linux で実行されるコーディングエージェントは、ファイル編集を実行場所で続けながら、macOS サンドボックス上で Apple プラットフォーム向けコードのビルド、テスト、実行を行えます。Amp では、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> をインストールしてください。Claude Code や Cursor などの他のエージェントの場合：

1. エージェントを Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP サーバー</.localized_link> に接続します。その `create_sandbox` ツールが、エージェントに Mac の操作方法を指示します。
2. エージェントが実行される環境に Tuist CLI をインストールします。例えば、環境のセットアップスクリプトで `mise use -g tuist@latest` を実行するか、`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` を実行します（ARM の場合は `tuist-linux-aarch64`）。
3. CLI を認証します。MCP サーバーへのサインイン状態は引き継がれないため、アカウントメンバーとして `tuist auth login` を実行するか、`TUIST_TOKEN` に `account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> を設定してください。
4. 環境でネットワークアクセスが制限されている場合は、`tuist.dev` へのアクセスを許可してください。CLI はこれ経由で Mac にファイルをアップロードするため、他のドメインは必要ありません。
5. オプションで、エージェントが毎回確認せずに Mac の作成と削除を行えるようにします。エージェントは `create_sandbox` を呼び出す前に確認を求めます（Mac がアカウントの制限数にカウントされるため）し、`delete_sandbox` の前にも確認を求めます（元に戻せないため）。Claude Code では、`.claude/settings.json` で両方を許可し、MCP サーバーを登録した名前（ここでは `tuist`）を使用します：

   ```json
   {
     "permissions": {
       "allow": ["mcp__tuist__create_sandbox", "mcp__tuist__delete_sandbox"]
     }
   }
   ```

エージェントにセットアップを実行させるには、次のプロンプトを与えます：

```text
Set up this environment so you can build and test this project on a Tuist macOS sandbox.

Read https://tuist.dev/en/docs/guides/features/sandboxes#coding-agents and follow its "Build on a Mac from a coding agent" section. It's the current Tuist guide for this, so prefer it over anything you remember about Tuist.

You're done when you have created a Mac with create_sandbox, synced this repository to it with tuist sandbox sync, run the project's build there with tuist sandbox exec, and deleted the Mac.

Ask me before anything that needs my login or approval, such as tuist auth login. If a step fails or is blocked, stop and tell me which step you reached and the exact error, without secrets.
```

エージェントはタスクごとに 1 台の Mac を作成し、プロジェクトがピン留めした [Xcode](#xcode) を使用します。`create_sandbox` は選択可能な Xcode バージョンの一覧を表示し、エージェントにプロジェクトのピン（例：`.xcode-version`）を読み取るよう指示します。各コマンドの実行前に `tuist sandbox sync` を実行します。Git が無視しないファイル（コミット済みかどうかに関わらず）をコピーし、以降は変更されたファイルのみをコピーします。Mac にはすでに [Tuist](#tuist-in-sandbox)（プロジェクトがバージョンをピン留めしている場合はそのバージョン）がインストールされ、アカウントのキャッシュにサインイン済みの状態であり、エージェントは Mac のガイドを一度読み取ります。その後、エージェントは `tuist sandbox exec` を使用して `xcodebuild` などのコマンドを実行し、`tuist sandbox cp` を使用してスクリーンショットやビルド済みアプリなどの結果をコピーバックし、タスク完了後に Mac を削除します。Mac は最後のコマンド実行後 10 分間稼働し続けるため、次のコマンドはすぐに開始されます。`tuist sandbox pause` を使用すればより早く返却できます。放置された Mac は一時停止し、2 時間の有効期限終了時にアーカイブされ、14 日後に削除されます。エージェントは長時間のビルドの前に有効期限を延長します。

## Linux と macOS {#platforms}

**Linux** サンドボックスは Ubuntu 24.04 で実行されます。すべての Linux サンドボックスは 16 vCPU を持ち、実行マシンのアイドルコアへバーストするため、シェイプによってメモリ容量が決まります：

- 2 GiB RAM（`--vcpus 1 --memory-gb 2`）
- 4 GiB RAM（`--vcpus 2 --memory-gb 4`、デフォルト）
- 8 GiB RAM（`--vcpus 4 --memory-gb 8`）
- 16 GiB RAM（`--vcpus 8 --memory-gb 16`）
- 32 GiB RAM（`--vcpus 16 --memory-gb 32`）
- 44 GiB RAM（`--vcpus 16 --memory-gb 44`）

**macOS** サンドボックスは Apple Silicon 上で Xcode とともに実行されます：

- 8 vCPU、8 GiB RAM（デフォルト）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

### 保証 CPU {#guaranteed-cpu}

Linux サンドボックスは、メモリ 1 GiB あたり 0.25 vCPU が保証されます（例：8 GiB で 2 vCPU）。さらに、マシンのアイドルコアを最大 16 vCPU まで使用できます。これは、主に待機状態でありバースト的にビルドを行うエージェントに適しています。負荷の高いマシンでもビルドにより安定した CPU が必要な場合は、サンドボックス作成時に 1、2、4、または 8 vCPU を保証してください。保証値とメモリに基づく保証値のうち、大きい方が適用されます：

| 場所 | 方法 |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API および MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **保証は下限であり、上限ではありません。** 4 vCPU が保証されたサンドボックスでも、コアがアイドル状態であれば 16 vCPU までバーストします。競合発生時は、各サンドボックスは保証値に応じて CPU を配分されます。
- **最小保証分として課金されます。** 稼働中のサンドボックスは使用した CPU に対して課金されますが、保証値を下回ることはありません。
- **サンドボックスの保証は生涯維持されます。** 変更するには、新しいサンドボックスを作成してください。
- **macOS サンドボックスは常に完全なシェイプを持ちます**。そのため、保証を設定しません。

### Xcode の選択 {#xcode}

各 macOS サンドボックスは 1 つの Xcode で実行され、作成時に選択します。その Xcode に対応する <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> プロファイルと同じイメージで起動するため、エージェントは CI と同じツールチェーンとシミュレーターでビルドを行います。tuist.dev では現在、以下の macOS サンドボックスを提供しています：

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

- **バージョンを指定しない場合**、Mac はデフォルトの Xcode を使用します。
- **Tuist が提供していないバージョンは拒否されます**。エラーには選択可能なバージョンが一覧表示されるため、現在利用可能なバージョンを確認できます。
- **Tuist はリポジトリの `.xcode-version` を読み取りません。** バージョンはあなた自身、または Mac を要求するエージェントが選択します。MCP ツールと Tuist Mac プラグインは、プロジェクトでピン留めされているバージョンと一致させるようエージェントに指示します。
- **サンドボックスの Xcode は生涯維持されます。** 別の Xcode でビルドするには、新しいサンドボックスを作成してください。`xcodebuild -version` は、Mac が実行している Xcode を示します。

## セキュリティ {#security}

- 各サンドボックスは独立した仮想マシンです。サンドボックス間、および CI ジョブ間で、ファイルシステム、メモリ、プロセスを共有しません。
- サンドボックスはアカウントに属しており、そのメンバーはすべて、統合サービスを提供するサンドボックスを含めて、サンドボックスを使用および管理できます。統合サービスの接続は管理者のみが行えます。統合サービスからのセッションは、その統合サービスが接続されているアカウントのサンドボックスにのみアクセスできます。
- Amp プロバイダートークンや Claude 環境キーなど、統合サービスの接続のために Tuist に提供する認証情報は、暗号化されて保存され、再度表示されることはありません。
- サンドボックスはインターネットにアクセスできます。エージェントがそこからアクセスできるものは、CI ジョブと同様に扱ってください。
