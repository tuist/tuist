---
{
  "title": "サンドボックス",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist サンドボックスは、Amp や Claude などのコーディングエージェント向けの永続的な Linux および macOS 仮想マシンです。各エージェントセッションには専用のマシンが割り当てられ、アイドル状態になると一時停止し、ファイルはそのままの状態で再開します。"
}
---
# サンドボックス {#sandboxes}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（LinuxおよびmacOS）は、キャパシティ拡張中の現在、招待制となっています。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティSlack](https://slack.tuist.dev)でご連絡ください。Sandboxesが一般公開される際に、料金プランを発表します。

サンドボックスは、コーディングエージェントがコマンドを実行し、ファイルを編集する仮想マシンです。各エージェントセッションには独自のサンドボックスが割り当てられ、セッションの有効期間中、チェックアウト、ビルド成果物、インストール済みツールを保持します。エージェントがアイドル状態になるとサンドボックスは一時停止し、次のメッセージで中断した箇所から再開します。

サンドボックスは<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>と同じフリート上で実行され、チームの<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>と隣接しているため、エージェントのビルドはCIやローカルマシンと同じキャッシュされたアーティファクトを利用できます。

サンドボックスは以下の方法で利用できます。

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：AmpワークスペースのOrbをTuist上で実行するか、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Macプラグイン</.localized_link>を使用して任意のAmpスレッドにXcodeビルド用のMacを提供します。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：Claude Managed AgentsセッションおよびClaude Codeクラウドセッション（claude.ai、デスクトップおよびモバイルアプリ、`claude --cloud`）をTuist上で実行します。
- **[The Tuist CLI](#cli)**：ターミナルからサンドボックスを作成してコマンドを実行するか、APIを通じて独自のツールから操作します。

## CLIでの始め方 {#cli}

`tuist sandbox`を使用して、ターミナルからサンドボックスを作成し、その中でコマンドを実行します。

### 1. ログイン {#cli-log-in}

サンドボックスの管理にはアカウント管理者が必要です。

```bash
tuist auth login
```

### 2. サンドボックスの作成 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linuxの場合は`--platform`を省略します。特定の[Xcode](#xcode)を搭載したMac用には、バージョンを指定して`--xcode`を渡します（例：`--xcode 26.1.1`）。これにより`--platform macos`が暗黙的に指定されます。より大きな[シェイプ](#platforms)には`--vcpus`と`--memory-gb`を、より大きなディスクには`--workspace-gb`を指定します。コマンドはサンドボックスが実行可能になると戻り、IDを含む詳細情報を出力します。カレントディレクトリのTuistプロジェクトのアカウントを使用します。別のアカウントを選択するには`--account`を指定してください。

### 3. コマンドの実行 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

コマンドはサンドボックス内で`bash -l`として実行され、一時停止中であればまず再開されます。`tuist`は実行時間がどれだけ長くても出力をストリーミングし、コマンドのステータスで終了します。Ctrl-Cでサンドボックス内の処理をキャンセルできます。必要に応じて`--cwd`、`--env NAME=VALUE`、および`--timeout`（最大6時間）を指定します。

### よくあるタスク {#cli-tasks}

| タスク | コマンド |
| --- | --- |
| サンドボックスの一覧表示 | `tuist sandbox list` |
| 1つを表示 | `tuist sandbox show <id>` |
| 一時停止または再開 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| ローカルのGitワークツリーのファイルをミラーリング | `tuist sandbox sync <id>` |
| ファイルのコピー（出し入れ） | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 削除 | `tuist sandbox delete <id> --yes` |
| 使用状況の確認 | `tuist sandbox analytics` |

機械可読な出力を得るには`--json`を追加します。すべてのオプションについては<.localized_link href="/cli/sandbox">CLIリファレンス</.localized_link>をご覧ください。コードからサンドボックスを操作する場合は、`/api/accounts/{account_handle}/sandboxes`下の[Tuist API](https://tuist.dev/api/docs)を通じて同じ操作を行うか、エージェントに<.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>を通じて利用させます。

対話的なログインができないツール（macOSサンドボックスでビルドするエージェントプラグインなど）は、代わりに`account:sandboxes:write`スコープを持つ<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>で認証できます。アカウントメンバーと同様に、サンドボックスの作成、コマンドの実行、一時停止、再開、削除が可能です。AmpまたはClaude統合、アナリティクス、統合設定を提供するサンドボックスの管理権限はアカウント管理者に残ります。

### サンドボックス内のTuist {#tuist-in-sandbox}

サンドボックスイメージにはTuist CLIが含まれていないため、プロジェクトでピン留めされたバージョンが実行されます。最初の`tuist sandbox sync`の後、サンドボックス上のリポジトリルートで`mise install`を実行します（`mise`と`brew`はインストール済み）。その後、mise経由で`tuist`を実行します。例えば、`PATH`上に`$HOME/.local/share/mise/shims`を追加する方法があります。

`tuist sandbox exec`で開始するすべてのコマンドはTuistランナーと同じ環境を取得するため、サンドボックス内のビルドは資格情報を渡さなくてもアカウントの<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>を利用できます。

- `TUIST_URL`、およびmacOSなどサンドボックスのホストから到達可能な場合、同じラック内のキャッシュの`TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`（そのコマンド用の短命なIDトークン）。Tuist CLI 4.218.0以降は自動的にこれでサインインします。4.215.0～4.217.xでは、同じコマンド内でまず`tuist auth login`を実行します。

トークンはコマンドごとに発行され、そのコマンドの実行中のみTuistトークンと交換できるため、サンドボックスが長寿命の資格情報を保持することはありません。コマンドを開始した人物またはトークンがキャッシュに対して実行できる権限を超えることは決してありません。キャッシュ書き込み専用トークンしか持たないアカウントメンバーは読み取りアクセスを得ており、サンドボックスがキャッシュを利用するには、`account:sandboxes:write`に加えて`ci`などのキャッシュスコープを持つアカウントトークンが必要です。`--env`で渡した変数が優先されます。

## コーディングエージェントからMacでビルド {#coding-agents}

クラウドエージェントセッションなどLinux上で実行されるコーディングエージェントは、実行場所でファイルを編集し続けながら、macOSサンドボックス上でAppleプラットフォーム向けコードのビルド、テスト、実行を行えます。Ampでは、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Macプラグイン</.localized_link>をインストールします。Claude CodeやCursorなどの他のエージェントの場合：

1. エージェントをTuist <.localized_link href="/guides/features/agentic-coding/mcp">MCPサーバー</.localized_link>に接続します。その`create_sandbox`ツールが、エージェントにMacを操作する方法を指示します。
2. エージェントが実行される場所にTuist CLIをインストールします。例えば、環境のセットアップスクリプトで`mise use -g tuist@latest`、または`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARMの場合は`tuist-linux-aarch64`）を実行します。
3. CLIを認証します。MCPサーバーのサインイン状態は引き継がれないため、アカウントメンバーとして`tuist auth login`を実行するか、`account:sandboxes:write`スコープを持つ<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を`TUIST_TOKEN`に設定します。
4. 環境がネットワークアクセスを制限している場合は、`tuist.dev`を許可してください。CLIはこれを通じてMacにファイルをアップロードするため、他のドメインは必要ありません。

エージェントはタスクごとに1台のMacを作成し、プロジェクトがピン留めした[Xcode](#xcode)を使用します。`create_sandbox`は選択可能なXcodeを一覧表示し、エージェントにプロジェクトのピン（例：`.xcode-version`）を読み取るよう指示します。各コマンドの前に、`tuist sandbox sync`を実行します。Gitが無視しないファイル（コミット済みかどうかに関わらず）をコピーし、その後は変更されたファイルのみをコピーします。初回同期後、Mac上のリポジトリルートで`mise install`を実行するため、[プロジェクトがピン留めしたTuist](#tuist-in-sandbox)が配置され、アカウントのキャッシュにサインインした状態になります。その後、エージェントは`tuist sandbox exec`を使って`xcodebuild`などのコマンドを実行し、`tuist sandbox cp`でスクリーンショットやビルド済みアプリなどの結果をコピーバックし、タスク完了時にMacを削除します。Macは最後のコマンド実行後10分間稼働し続けるため、次のコマンドはすぐに開始されます。`tuist sandbox pause`を使えばより早く返却できます。放置されたMacは一時停止し、14日間一時停止状態が続くと削除されます。

## LinuxとmacOS {#platforms}

**Linux**サンドボックスはUbuntu 24.04で動作します：

- 2 vCPU、4 GiB RAM（デフォルト）
- 4 vCPU、8 GiB RAM
- 8 vCPU、16 GiB RAM

**macOS**サンドボックスはAppleシリコン上でXcodeとともに動作します：

- 8 vCPU、8 GiB RAM（デフォルト）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

### Xcodeを選択する {#xcode}

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
| Amp orbs | orbタイプ`macos-xcode-26-1-1`（<.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>を参照） |
| Claude CodeおよびClaude Managed Agents | 環境またはManaged Agentsセッションごとの`xcode_version`（<.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>を参照） |

- **バージョンを指定しない場合**、Macはデフォルト値を使用します。
- **Tuistが提供していないバージョンは拒否され**、エラーメッセージに選択可能なバージョンが一覧表示されるため、現在利用可能なものがわかります。
- **Tuistはリポジトリの`.xcode-version`を読み取りません。** バージョンはあなた自身、またはMacを要求するエージェントが選択します。MCPツールとTuist Macプラグインは、エージェントにプロジェクトがピン留めしたバージョンと一致させるよう指示します。
- **サンドボックスはそのXcodeを終生保持します。** 別のXcodeでビルドするには、新しいサンドボックスを作成してください。`xcodebuild -version`はMacが実行しているXcodeを示します。

## セキュリティ {#security}

- 各サンドボックスは独立した仮想マシンです。サンドボックス同士、またはCIジョブ間でファイルシステム、メモリ、プロセスを共有しません。
- サンドボックスはアカウントに属し、その管理者のみが管理できます。統合からのセッションは、統合が接続されているアカウントのサンドボックスにのみアクセスできます。
- 統合を接続するためにTuistに提供する資格情報（AmpプロバイダートークンやClaude環境キーなど）は暗号化されて保存され、再度表示されることはありません。
- サンドボックスはインターネットにアクセスできます。エージェントがそこからアクセスできるものは、CIジョブと同様に扱ってください。
