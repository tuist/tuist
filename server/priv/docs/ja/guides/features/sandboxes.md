---
{
  "title": "サンドボックス",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist サンドボックスは、Amp や Claude などのコーディングエージェント向けの永続的な Linux および macOS 仮想マシンです。各エージェントセッションには専用のマシンが割り当てられ、アイドル状態になると一時停止し、ファイルはそのままで再開します。"
}
---
# サンドボックス {#sandboxes}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（LinuxおよびmacOS）は、キャパシティ拡張中は現在招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティSlack](https://slack.tuist.dev)でご連絡ください。Sandboxesが一般提供開始され次第、価格を発表します。

サンドボックスは、コーディングエージェントがコマンドを実行しファイルを編集するための仮想マシンです。各エージェントセッションには独自のサンドボックスが割り当てられ、セッション存续期间中、チェックアウト、ビルド成果物、インストール済みツールを保持します。エージェントがアイドル状態になるとサンドボックスは一時停止し、次のメッセージで中断した箇所から再開します。

サンドボックスは<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>と同じフリート上で動作し、チームの<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>の隣に配置されるため、エージェントのビルドはCIやローカルマシンと同じキャッシュアーティファクトを利用できます。

サンドボックスは以下の方法で利用できます：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：AmpワークスペースのorbをTuist上で実行するか、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Macプラグイン</.localized_link>を使用して任意のAmpスレッドにXcodeビルド用のMacを提供します。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：Claude Managed AgentsセッションおよびClaude Codeクラウドセッション（claude.ai、デスクトップおよびモバイルアプリ、`claude --cloud`）をTuist上で実行します。
- **[Tuist CLI](#cli)**：ターミナルからサンドボックスを作成してコマンドを実行するか、APIを通じて独自のツールから操作します。

## CLIではじめる {#cli}

`tuist sandbox`を使用して、ターミナルからサンドボックスを作成し、その中でコマンドを実行します。

### 1. ログイン {#cli-log-in}

アカウントのメンバーであれば誰でも、サンドボックスの作成と管理が可能です：

```bash
tuist auth login
```

### 2. サンドボックスを作成 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linuxの場合は`--platform`を省略してください。特定の[Xcode](#xcode)を搭載したMac用には、バージョン（例：`--xcode 26.1.1`）を指定して`--xcode`を渡します。これにより`--platform macos`が暗黙的に指定されます。より大きな[シェイプ](#platforms)を選ぶには`--vcpus`と`--memory-gb`を、Linuxサンドボックスにより多くの[CPU](#guaranteed-cpu)を保証するには`--guaranteed-vcpus`を、より大きなディスク容量には`--workspace-gb`を指定します。サンドボックスは作成時から2時間、また再開ごとに2時間動作します。5分から1日の間で設定するには`--lifetime-minutes`を指定します。有効期限が切れると、実行中のコマンドはキャンセルされ、サンドボックスは一時停止およびアーカイブされてファイルは保持されるため、忘れられたサンドボックスがアカウントのキャパシティを消費し続けることはありません。コマンドはサンドボックスが起動すると戻り、IDを含む詳細情報を出力します。すべてのホストがビジー状態の場合（例えばCIジョブが共有Macを占有している間など）、サーバーは作成が`fleet_busy`で失敗する前に25秒間待ちます。`--wait-timeout 5m`を指定すると、最大5分（最大1時間）まで再試行を続け、理由がstderrに約1分ごとに繰り返して表示されます。カレントディレクトリのTuistプロジェクトのアカウントを使用します。別のアカウントを選ぶには`--account`を指定してください。

### 3. コマンドを実行 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

コマンドはサンドボックス内で`bash -l`として実行され、一時停止中であればまず再開されます。`tuist`は実行時間がどれだけ長くても出力をストリーミングし、コマンドのステータスで終了します。Ctrl-Cでサンドボックス内のコマンドをキャンセルできます。必要に応じて`--cwd`、`--env NAME=VALUE`、および`--timeout`（最大6時間）を指定します。

コマンドは`tuist`からデタッチして実行されるため、接続が切断されても継続します。エージェントなど時間制限のあるツール呼び出し内に長時間のビルドを収めるには、`--wait <seconds>`を指定します。制限時間が先に経過すると、`tuist`はコマンドを実行したままステータス75で終了し、出力を中断した箇所から継続してコマンドのステータスで終了する`tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …`コマンドを出力します。

### よくあるタスク {#cli-tasks}

| タスク | コマンド |
| --- | --- |
| サンドボックスの一覧表示 | `tuist sandbox list` |
| 1件を表示 | `tuist sandbox show <id>` |
| 一時停止または再開 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 有効期限後も実行を継続 | `tuist sandbox extend <id> --lifetime-minutes 240` |
| ローカルのGitワークツリーのファイルをミラーリング | `tuist sandbox sync <id>` |
| 起動済みのiOS SimulatorまたはmacOSサンドボックスの画面全体をスクリーンショット | `tuist sandbox screenshot <id> --out shot.png`, `tuist sandbox screenshot <id> --screen --out screen.png` |
| ファイルのコピー（出し入れ） | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 削除 | `tuist sandbox delete <id> --yes` |
| 使用状況を確認 | `tuist sandbox analytics` |

機械可読な出力を得るには`--json`を追加します。すべてのオプションについては<.localized_link href="/cli/sandbox">CLIリファレンス</.localized_link>をご覧ください。コードからサンドボックスを操作する場合は、`/api/accounts/{account_handle}/sandboxes`下の[Tuist API](https://tuist.dev/api/docs)を通じて同じ操作を行うか、エージェントに<.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>を通じて利用させます。

対話的にログインできないツール（macOSサンドボックスでビルドを行うエージェントプラグインなど）は、代わりに`account:sandboxes:write`スコープを持つ<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>で認証できます。アカウントメンバーと同様に、サンドボックスの作成、コマンドの実行、一時停止、再開、アーカイブ、削除が可能です。統合の設定、および統合を提供するサンドボックスでのコマンド実行は、アカウント管理者のみが行えます。

### サンドボックス内のTuist {#tuist-in-sandbox}

macOSサンドボックスにはTuist CLIが含まれています。プロジェクトがmise（`mise.toml`または`.tool-versions`）を通じてTuistをピン留めしている場合、`tuist`はそのバージョンを実行します。このバージョンは、コマンドが初めて必要とした際にインストールされます。`tuist sandbox exec`で開始するすべてのコマンドでは、miseのシム（`$HOME/.local/share/mise/shims`）が`PATH`の先頭に配置され、イメージのTuistが最後になるため、`tuist`およびその他のmiseツールは、コマンド内およびスキームのpost-actionsなどのXcodeビルドフェーズで実行されます。各Macには`/opt/tuist/agent-guide.md`にコーディングエージェント向けガイドがあり、イメージから生成されます。このガイドには、XcodeとSimulator、リポジトリの場所、準備済みスナップショットの内容が記載されています。Mac上で実行されているClaude Code、Codex、Ampは、それぞれの指示ファイルからこのガイドを見つけます。

`tuist sandbox exec`で開始するすべてのコマンドは、Tuistランナーと同じ環境を受け取るため、サンドボックス内のビルドは資格情報を渡すことなくアカウントの<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>を利用できます：

- `TUIST_URL`、およびサンドボックスのホストから到達可能な場合（macOSなど）、同じラック内のキャッシュの`TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`。これはそのコマンド用の短命なIDトークンです。Tuist CLI 4.218.0以降はこれを使用して自動的にサインインします。4.215.0から4.217.xでは、同じコマンド内でまず`tuist auth login`を実行してください。

トークンはコマンドごとに発行され、そのコマンドの実行中のみTuistトークンと交換できるため、サンドボックスが長寿命の資格情報を保持することはありません。このトークンは、コマンドを開始した人物またはトークンがキャッシュに対して実行できる権限を超えて付与されることはありません。キャッシュ書き込みトークンのみを持つアカウントメンバーは読み取りアクセスを得て、サンドボックスがキャッシュを利用するには、アカウントトークンに`ci`などのキャッシュスコープと`account:sandboxes:write`が必要です。`--env`で渡した変数が優先されます。

## コーディングエージェントからMacでビルド {#coding-agents}

Linux上で動作するコーディングエージェント（クラウドエージェントセッションなど）は、ファイル編集を実行場所で継続しながら、macOSサンドボックス上でAppleプラットフォーム向けコードのビルド、テスト、実行が可能です。Ampでは、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Macプラグイン</.localized_link>をインストールします。Claude CodeやCursorなどの他のエージェントの場合：

1. エージェントをTuistの<.localized_link href="/guides/features/agentic-coding/mcp">MCPサーバー</.localized_link>に接続します。その`create_sandbox`ツールは、Macを操作する方法をエージェントに指示します。
2. エージェントが実行される環境でTuist CLIをインストールします。例えば、環境のセットアップスクリプトで`mise use -g tuist@latest`、または`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARMの場合は`tuist-linux-aarch64`）を実行します。
3. CLIを認証します。MCPサーバーのサインイン状態は引き継がれないため、アカウントメンバーとして`tuist auth login`を実行するか、`TUIST_TOKEN`を`account:sandboxes:write`スコープを持つ<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>に設定してください。
4. 環境でネットワークアクセスが制限されている場合は、`tuist.dev`を許可してください。CLIはこれを通じてMacへファイルをアップロードするため、他のドメインは必要ありません。
5. オプションで、毎回確認せずにエージェントがMacを作成・削除できるようにします。エージェントは、Macがアカウントの制限にカウントされるため`create_sandbox`を呼び出す前に、また元に戻せないため`delete_sandbox`の前に確認を求めます。Claude Codeでは、登録したMCPサーバー名（ここでは`tuist`）を使用して、`.claude/settings.json`で両方を許可します：

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

エージェントはタスクごとに1台のMacを作成し、プロジェクトが指定した[Xcode](#xcode)を使用します。`create_sandbox`は選択可能なXcodeの一覧を表示し、`.xcode-version`などのプロジェクトの指定バージョンを読み取るようエージェントに指示します。各コマンドの実行前に、`tuist sandbox sync`を実行します。Gitが無視しないファイル（コミット済みかどうかに関わらず）をコピーし、その後に変更されたファイルのみをコピーします。Macにはすでに[Tuist](#tuist-in-sandbox)（プロジェクトがバージョンを指定している場合はその pinned バージョン）がインストールされ、アカウントのキャッシュにサインイン済みの状態であり、エージェントはMacのガイドを一度読み込みます。その後、エージェントは`tuist sandbox exec`を使って`xcodebuild`などのコマンドを実行し、Simulatorでアプリを起動してMCPサーバーの`get_sandbox_screenshot`または`tuist sandbox screenshot`であなたに表示し、`tuist sandbox cp`でビルド済みアプリなどの結果をコピーバックし、タスク完了後にMacを削除します。Macは最後のコマンド実行後10分間稼働し続けるため、次のコマンドはすぐに開始されます。`tuist sandbox pause`を実行すればより早く返却できます。放置されたMacは一時停止し、2時間の有効期限終了時にアーカイブされ、14日後に削除されます。エージェントは長時間のビルド前に有効期限を延長します。

## LinuxとmacOS {#platforms}

**Linux**サンドボックスはUbuntu 24.04で動作します。すべてのLinuxサンドボックスは16 vCPUを持ち、実行マシンのアイドルコアへバーストするため、シェイプによってメモリ容量が決まります：

- 2 GiB RAM (`--vcpus 1 --memory-gb 2`)
- 4 GiB RAM (`--vcpus 2 --memory-gb 4`、デフォルト)
- 8 GiB RAM (`--vcpus 4 --memory-gb 8`)
- 16 GiB RAM (`--vcpus 8 --memory-gb 16`)
- 32 GiB RAM (`--vcpus 16 --memory-gb 32`)
- 44 GiB RAM (`--vcpus 16 --memory-gb 44`)

**macOS**サンドボックスはAppleシリコン上でXcodeとともに動作します：

- 8 vCPU、8 GiB RAM（デフォルト）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

### 保証CPU {#guaranteed-cpu}

Linuxサンドボックスは、メモリ1 GiBあたり0.25 vCPU（例：8 GiBで2 vCPU）が保証され、マシンのアイドル状態に応じて最大16 vCPUまでバーストします。これは、主に待機状態でバースト的にビルドを行うエージェントに適しています。混雑したマシンでも安定したCPUが必要なビルドの場合、サンドボックス作成時に1、2、4、または8 vCPUを保証できます。サンドボックスは、その値とメモリによる保証値の大きい方を受け取ります：

| 場所 | 方法 |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| APIおよびMCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **保証は下限であり、上限ではありません。** 4 vCPUが保証されたサンドボックスでも、コアがアイドル状態であれば16 vCPUまでバーストします。競合時には、各サンドボックスは保証値に比例してCPUを取得します。
- **最小保証分として課金されます。** 稼働中のサンドボックスは使用したCPUに対して課金されますが、保証値を下回ることはありません。
- **サンドボックスの保証は生涯維持されます。** 変更するには、新しいサンドボックスを作成してください。
- **macOSサンドボックスは常に完全なシェイプを持つ**ため、保証を設定しません。

### Xcodeの選択 {#xcode}

各macOSサンドボックスは1つのXcodeで動作し、作成時に選択します。そのXcode用の<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>プロファイルと同じイメージで起動するため、エージェントはCIと同じツールチェーンとシミュレーターでビルドを行います。tuist.devでは現在、以下のmacOSサンドボックスを提供しています：

- `26.6`（デフォルト）
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

ランナープロファイルと同様に、正確なバージョンを指定して`xcode_version`（CLIでは`--xcode`）で選択します：

| 場所 | 方法 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| APIおよびMCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp用Tuist Macプラグイン | `xcode`付きの`tuist_mac_start` |
| Amp orbs | Orbタイプ`macos-xcode-26-1-1`（<.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>を参照） |
| Claude CodeおよびClaude Managed Agents | 環境上の`xcode_version`、またはManaged Agentsセッションごと（<.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>を参照） |

- **バージョンを指定しない場合**、Macはデフォルトを受け取ります。
- **Tuistが提供していないバージョンは拒否されます**。エラーには選択可能なバージョンが一覧表示されるため、現在利用可能なものがわかります。
- **Tuistはリポジトリの`.xcode-version`を読み取りません。** バージョンはあなた自身、またはMacを要求するエージェントが選択します。MCPツールとTuist Macプラグインは、プロジェクトでピン留めされたバージョンに一致させるようエージェントに指示します。
- **サンドボックスのXcodeは生涯維持されます。** 別のXcodeでビルドするには、新しいサンドボックスを作成してください。`xcodebuild -version`はMacが実行しているXcodeを示します。

## セキュリティ{#security}

- 各サンドボックスは独自の仮想マシンです。サンドボックス間で、またCIジョブとファイルシステム、メモリ、プロセスを共有しません。
- サンドボックスはアカウントに属し、そのメンバーは誰でも使用および管理できます。Amp orbやClaude Codeセッションなどの統合を提供するサンドボックスは、そのセッションの作業内容と認証情報を保持します。メンバーはそれらの表示、一時停止、再開、アーカイブ、削除を行えますが、コマンドの実行やファイルのアップロードができるのは管理者のみです。統合の接続も管理者のみが行えます。統合からのセッションは、その統合が接続されているアカウントのサンドボックスにのみアクセスできます。
- AmpプロバイダートークンやClaude環境キーなど、統合の接続のためにTuistに提供した認証情報は暗号化されて保存され、二度と表示されることはありません。
- サンドボックスはインターネットにアクセスできます。エージェントがそこからアクセスできるものは、CIジョブと同様に扱ってください。
