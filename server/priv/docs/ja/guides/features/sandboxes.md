---
{
  "title": "サンドボックス",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuistのサンドボックスは、AmpやClaudeなどのコーディングエージェント向けの永続的なLinuxおよびmacOS仮想マシンです。各エージェントセッションには専用のマシンが割り当てられ、アイドル状態になると一時停止し、再開時にはファイルがそのまま残っています。"
}
---
# サンドボックス {#sandboxes}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux と macOS の両方）は、現在キャパシティを拡張中であるため招待制となっています。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。Sandboxes が一般提供開始され次第、価格を発表します。

サンドボックスは、コーディングエージェントがコマンドを実行しファイルを編集するための仮想マシンです。各エージェントセッションには専用のサンドボックスが割り当てられ、セッション中はチェックアウト内容、ビルド成果物、インストール済みツールが保持されます。エージェントがアイドル状態になるとサンドボックスは一時停止し、次のメッセージで中断した箇所から再開されます。

サンドボックスは <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> と同じフリート上で動作し、チームの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> と並んで配置されるため、エージェントによるビルドは CI やローカルマシンと同じキャッシュアーティファクトを利用できます。

サンドボックスは以下の方法で利用できます：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：Amp ワークスペースの Orb を Tuist で実行するか、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> を使用して任意の Amp スレッドに Xcode ビルド用の Mac を提供します。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：Claude Managed Agents セッションおよび Claude Code クラウドセッション（claude.ai、デスクトップおよびモバイルアプリ、`claude --cloud`）を Tuist で実行します。
- **[The Tuist CLI](#cli)**：ターミナルからサンドボックスを作成してコマンドを実行したり、API を介して独自のツールから操作したりできます。

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

Linux の場合は `--platform` を省略してください。特定の [Xcode](#xcode) を搭載した Mac を用意するには、バージョンを指定して `--xcode` を渡します（例：`--xcode 26.1.1`）。これにより `--platform macos` が暗黙的に指定されます。より大きな [シェイプ](#platforms) を選択するには `--vcpus` と `--memory-gb` を渡し、Linux サンドボックスでより多くの [CPU](#guaranteed-cpu) を保証するには `--guaranteed-vcpus` を渡し、より大きなディスク容量には `--workspace-gb` を渡します。サンドボックスは作成時から2時間、また各再開時から2時間実行されます。5分から1日の間で設定するには `--lifetime-minutes` を渡します。有効期限が切れると、実行中のコマンドはキャンセルされ、サンドボックスは一時停止およびアーカイブされてファイルは保持されるため、忘れられたサンドボックスがアカウントのキャパシティを消費し続けることを防ぎます。コマンドはサンドボックスが実行可能になると戻り値を返し、ID を含む詳細情報を出力します。CI ジョブが共有 Mac を使用中など、すべてのホストがビジー状態の場合、サーバーは作成が `fleet_busy` で失敗する前に25秒間待機します。最大5分間（1時間を上限として）試行を続けるには `--wait-timeout 5m` を渡します。この場合、理由は stderr に約1分ごとに繰り返して出力されます。カレントディレクトリの Tuist プロジェクトのアカウントが使用されます。別のアカウントを選択するには `--account` を渡します。

### 3. コマンドを実行 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

コマンドはサンドボックス内で `bash -l` を使用して実行され、一時停止中であればまず再開されます。`tuist` は実行時間がどれだけ長くても出力をストリーミングし、コマンドのステータスで終了します。Ctrl-C でサンドボックス内の処理をキャンセルできます。必要に応じて `--cwd`、`--env NAME=VALUE`、および `--timeout`（最大6時間）を渡します。

コマンドは `tuist` からデタッチされて実行されるため、接続が切断されても継続します。エージェントなど時間制限のあるツール呼び出しの中に長時間のビルドを組み込むには、`--wait <seconds>` を渡します。制限時間が先に経過した場合、`tuist` はコマンドを実行したまま終了コード 75 で終了し、中断した箇所から出力を継続してコマンドのステータスで終了する `tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …` コマンドを出力します。

### よくあるタスク {#cli-tasks}

| タスク | コマンド |
| --- | --- |
| サンドボックスを一覧表示 | `tuist sandbox list` |
| 1つを表示 | `tuist sandbox show <id>` |
| 一時停止または再開 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 有効期限後も実行を継続 | `tuist sandbox extend <id> --lifetime-minutes 240` |
| ローカルの Git ワークツリーのファイルをミラーリング | `tuist sandbox sync <id>` |
| ファイルのコピー（送受信） | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 削除 | `tuist sandbox delete <id> --yes` |
| 使用状況を確認 | `tuist sandbox analytics` |

機械読み取り可能な出力を得るには `--json` を追加します。すべてのオプションについては <.localized_link href="/cli/sandbox">CLI リファレンス</.localized_link> を参照してください。コードからサンドボックスを操作する場合は、`/api/accounts/{account_handle}/sandboxes` 以下の [Tuist API](https://tuist.dev/api/docs) を介して同じ操作を実行するか、エージェントに <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> を介して利用させます。

対話的にログインできないツール（macOS サンドボックスでビルドを行うエージェントプラグインなど）は、代わりに `account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> で認証できます。これはアカウントメンバーと同様に、サンドボックスの作成、コマンドの実行、一時停止、再開、アーカイブ、削除を実行可能です。インテグレーションの設定、およびインテグレーションを提供するサンドボックスでのコマンド実行は、アカウント管理者の権限のままとなります。

### サンドボックス内の Tuist {#tuist-in-sandbox}

macOS サンドボックスには Tuist CLI が付属しています。プロジェクトが mise（`mise.toml` または `.tool-versions`）を通じて Tuist のバージョンを固定している場合、`tuist` はコマンドが必要とした際に初めてインストールされるそのバージョンを実行します。`tuist sandbox exec` で開始するすべてのコマンドでは、mise のシム（`$HOME/.local/share/mise/shims`）が `PATH` の先頭に配置され、イメージに含まれる Tuist が最後になるため、`tuist` および他の mise ツールはコマンド内や Xcode のビルドフェーズ（スキームのポストアクションなど）で実行されます。各 Mac には `/opt/tuist/agent-guide.md` にコーディングエージェント向けのガイドが含まれており、これはイメージから生成されます。ガイドには Xcode とシミュレータ、リポジトリの場所、準備済みのスナップショットの内容が記載されています。Mac 上で実行されている Claude Code、Codex、Amp は、それぞれの指示ファイルからこのガイドを見つけます。

`tuist sandbox exec` で開始するすべてのコマンドは Tuist ランナーと同様の環境を受け取るため、サンドボックス内のビルドは資格情報を渡さなくてもアカウントの <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> を利用できます：

- `TUIST_URL`、および macOS などサンドボックスのホストから到達可能な場合、同じラック内のキャッシュの `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`。そのコマンド用の短命な ID トークンです。Tuist CLI 4.218.0 以降は自動的にこれでサインインします。4.215.0 ～ 4.217.x では、同じコマンド内で最初に `tuist auth login` を実行してください。

トークンはコマンドごとに発行され、そのコマンドの実行中のみ Tuist トークンと交換できるため、サンドボックスが長寿命の資格情報を保持することはありません。トークンは、コマンドを開始した人物またはトークンがキャッシュに対して実行できる操作以上の権限を付与しません。キャッシュ書き込み用トークンのみを持つアカウントメンバーは読み取りアクセスを得て、アカウントトークンがキャッシュを使用するには `ci` などのキャッシュスコープと `account:sandboxes:write` の両方が必要です。`--env` で渡した変数が優先されます。

## コーディングエージェントから Mac でビルド {#coding-agents}

クラウドエージェントセッションなど Linux で実行されるコーディングエージェントは、ファイル編集を実行場所で続けながら、macOS サンドボックス上で Apple プラットフォーム向けコードのビルド、テスト、実行を行えます。Amp では <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac プラグイン</.localized_link> をインストールしてください。Claude Code や Cursor などの他のエージェントの場合：

1. エージェントを Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP サーバー</.localized_link> に接続します。その `create_sandbox` ツールが、エージェントに Mac の操作方法を指示します。
2. エージェントが実行される環境に Tuist CLI をインストールします。例えば、環境のセットアップスクリプトで `mise use -g tuist@latest`、または `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM では `tuist-linux-aarch64`）を実行します。
3. CLI を認証します。MCP サーバーへのサインインは引き継がれないため、アカウントメンバーとして `tuist auth login` を実行するか、`account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> を `TUIST_TOKEN` に設定してください。
4. 環境でネットワークアクセスが制限されている場合は、`tuist.dev` を許可してください。CLI はこれを通じて Mac にファイルをアップロードするため、他のドメインは必要ありません。
5. オプションで、エージェントが毎回確認せずに Mac の作成と削除を行えるようにします。エージェントは `create_sandbox` を呼び出す前に確認を求めます（Mac がアカウントの制限にカウントされるため）し、`delete_sandbox` の前にも確認を求めます（元に戻せないため）。Claude Code では、`.claude/settings.json` 内で両方を許可し、MCP サーバーを登録した名前（ここでは `tuist`）を使用します：

   ```json
   {
     "permissions": {
       "allow": ["mcp__tuist__create_sandbox", "mcp__tuist__delete_sandbox"]
     }
   }
   ```

エージェントにセットアップを行わせるには、次のプロンプトを与えます：

```text
Set up this environment so you can build and test this project on a Tuist macOS sandbox.

Read https://tuist.dev/en/docs/guides/features/sandboxes#coding-agents and follow its "Build on a Mac from a coding agent" section. It's the current Tuist guide for this, so prefer it over anything you remember about Tuist.

You're done when you have created a Mac with create_sandbox, synced this repository to it with tuist sandbox sync, run the project's build there with tuist sandbox exec, and deleted the Mac.

Ask me before anything that needs my login or approval, such as tuist auth login. If a step fails or is blocked, stop and tell me which step you reached and the exact error, without secrets.
```

エージェントはタスクごとに 1 台の Mac を作成し、プロジェクトが指定した [Xcode](#xcode) を使用します。`create_sandbox` は選択可能な Xcode を一覧表示し、エージェントにプロジェクトの指定（例：`.xcode-version`）を読み取るよう指示します。各コマンドの前に `tuist sandbox sync` を実行します。Git が無視しないファイル（コミット済みかどうかに関わらず）をコピーし、その後変更されたファイルのみをコピーします。Mac にはすでに [Tuist](#tuist-in-sandbox)（プロジェクトがバージョンを指定している場合はそのピン留めされたバージョン）がインストールされ、アカウントのキャッシュにサインインしており、エージェントは Mac のガイドを一度読み取ります。その後、エージェントは `tuist sandbox exec` を使って `xcodebuild` などのコマンドを実行し、`tuist sandbox cp` でスクリーンショットやビルド済みアプリなどの結果をコピーバックし、タスクが完了したら Mac を削除します。Mac は最後のコマンドから 10 分間実行状態を維持するため、次のコマンドはすぐに開始されます。`tuist sandbox pause` を使えばより早く返却できます。放置された Mac は一時停止し、2 時間のライフタイム終了時にアーカイブされ、14 日後に削除されます。エージェントは長時間のビルドの前にライフタイムを延長します。

## Linux と macOS {#platforms}

**Linux** サンドボックスは Ubuntu 24.04 で実行されます。すべての Linux サンドボックスは 16 vCPU を持ち、実行マシンのアイドルコアへとバーストするため、シェイプによってメモリが決定されます：

- 2 GiB RAM（`--vcpus 1 --memory-gb 2`）
- 4 GiB RAM（`--vcpus 2 --memory-gb 4`、デフォルト）
- 8 GiB RAM（`--vcpus 4 --memory-gb 8`）
- 16 GiB RAM（`--vcpus 8 --memory-gb 16`）
- 32 GiB RAM（`--vcpus 16 --memory-gb 32`）
- 44 GiB RAM（`--vcpus 16 --memory-gb 44`）

**macOS** サンドボックスは Apple silicon 上で Xcode とともに実行されます：

- 8 vCPU、8 GiB RAM（デフォルト）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

### 保証 CPU {#guaranteed-cpu}

Linux サンドボックスはメモリ 1 GiB あたり 0.25 vCPU が保証され（例：8 GiB で 2 vCPU）、マシンのアイドルコアに応じて最大 16 vCPU までバーストします。これは主に待機し、バースト的にビルドを行うエージェントに適しています。混雑したマシンでもビルドにより安定した CPU が必要な場合は、サンドボックス作成時に 1、2、4、または 8 vCPU を保証します。保証値とメモリに基づく保証値の大きい方が適用されます：

| 場所 | 方法 |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API および MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **保証は下限であり、上限ではありません。** 4 vCPU が保証されたサンドボックスでも、コアがアイドル状態であれば 16 vCPU までバーストします。競合時には、各サンドボックスは保証比例で CPU を取得します。
- **最低保証として課金されます。** 実行中のサンドボックスは使用した CPU に対して課金されますが、保証値を下回ることはありません。
- **サンドボックスの保証はライフタイムを通じて維持されます。** 変更するには、新しいサンドボックスを作成してください。
- **macOS サンドボックスは常に完全なシェイプを持つ**ため、保証を設定しません。

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
| Amp orbs | orb タイプ `macos-xcode-26-1-1`（<.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link> を参照） |
| Claude Code および Claude Managed Agents | 環境ごとの `xcode_version`、または Managed Agents セッションごと（<.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link> を参照） |

- **バージョンを指定しない場合**、Mac はデフォルトの Xcode を使用します。
- **Tuist が提供していないバージョンは拒否されます**。エラーには選択可能なバージョンが一覧表示されるため、現在利用可能なバージョンを確認できます。
- **Tuist はリポジトリの `.xcode-version` を読み取りません。** バージョンはあなた自身、または Mac を要求するエージェントが選択します。MCP ツールおよび Tuist Mac プラグインは、プロジェクトでピン留めされたバージョンに一致するようエージェントに指示します。
- **サンドボックスの Xcode はライフタイムを通じて維持されます。** 別の Xcode でビルドするには、新しいサンドボックスを作成してください。`xcodebuild -version` は Mac が実行している Xcode のバージョンを表示します。

## セキュリティ {#security}

- 各サンドボックスは独立した仮想マシンです。サンドボックス間、または CI ジョブ間でファイルシステム、メモリ、プロセスを共有しません。
- サンドボックスはアカウントに属し、そのメンバー全員が使用および管理できます。Amp orb や Claude Code セッションなどの統合サービスを提供するサンドボックスは、そのセッションの作業内容と認証情報を保持します。メンバーはこれらのサンドボックスを表示、一時停止、再開、アーカイブ、削除できますが、コマンドの実行やファイルのアップロードは管理者のみが行えます。統合サービスの接続も管理者のみが行えます。統合サービスからのセッションは、その統合サービスが接続されているアカウントのサンドボックスにのみアクセスできます。
- 統合サービスの接続のために Tuist に提供する認証情報（Amp プロバイダートークンや Claude 環境キーなど）は暗号化して保存され、二度と表示されることはありません。
- サンドボックスはインターネットにアクセスできます。エージェントがサンドボックスからアクセスできるものは、CI ジョブと同様に扱ってください。
