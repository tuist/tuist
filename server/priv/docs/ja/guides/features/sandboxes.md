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
> Tuist Sandboxes（LinuxおよびmacOS）は、現在キャパシティを拡充中であり、招待制となっています。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティSlack](https://slack.tuist.dev)でご連絡ください。Sandboxesが一般公開される際に、料金プランを発表します。

サンドボックスは、コーディングエージェントがコマンドを実行し、ファイルを編集するための仮想マシンです。各エージェントセッションには独自のサンドボックスが割り当てられ、セッションの間、チェックアウト状態、ビルド成果物、インストール済みツールが保持されます。エージェントがアイドル状態になるとサンドボックスは一時停止し、次のメッセージで中断した箇所から再開します。

サンドボックスは<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>と同じフリート上で実行され、チームの<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>と並んで配置されるため、エージェントのビルドはCIやローカルマシンと同じキャッシュされたアーティファクトを利用できます。

サンドボックスは以下の方法で利用できます。

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：AmpワークスペースのOrbをTuist上で実行するか、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Macプラグイン</.localized_link>を使用して任意のAmpスレッドにXcodeビルド用のMacを提供します。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：Claude Managed AgentsセッションおよびClaude Codeクラウドセッション（claude.ai、デスクトップおよびモバイルアプリ、`claude --cloud`）をTuist上で実行します。
- **[The Tuist CLI](#cli)**：ターミナルからサンドボックスを作成してコマンドを実行するか、APIを通じて独自のツールから操作します。

## CLIで始める {#cli}

`tuist sandbox`を使用して、ターミナルからサンドボックスを作成し、その中でコマンドを実行します。

### 1. ログイン {#cli-log-in}

サンドボックスの管理にはアカウント管理者が必要です。

```bash
tuist auth login
```

### 2. サンドボックスを作成 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linuxの場合は`--platform`を省略します。より大きな[シェイプ](#platforms)には`--vcpus`と`--memory-gb`を指定し、より大きなディスクには`--workspace-gb`を指定します。コマンドはサンドボックスが実行状態になると戻り、IDを含む詳細情報を出力します。カレントディレクトリのTuistプロジェクトのアカウントを使用します。別のアカウントを選択するには`--account`を指定してください。

### 3. コマンドを実行 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

コマンドはサンドボックス内で`bash -l`として実行され、一時停止中の場合はまず再開されます。`tuist`は実行時間に関わらず出力をストリーミングし、コマンドのステータスで終了します。Ctrl-Cでサンドボックス内の処理をキャンセルできます。必要に応じて`--cwd`、`--env NAME=VALUE`、および`--timeout`（最大6時間）を指定してください。

### 一般的なタスク {#cli-tasks}

| タスク | コマンド |
| --- | --- |
| サンドボックスを一覧表示 | `tuist sandbox list` |
| 1つを表示 | `tuist sandbox show <id>` |
| 一時停止または再開 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| ローカルのGitワークツリーのファイルを同期 | `tuist sandbox sync <id>` |
| ファイルのコピー（出し入れ） | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 削除 | `tuist sandbox delete <id> --yes` |
| 使用状況を確認 | `tuist sandbox analytics` |

機械可読な出力を得るには`--json`を追加します。すべてのオプションについては<.localized_link href="/cli/sandbox">CLIリファレンス</.localized_link>をご覧ください。コードからサンドボックスを操作する場合は、`/api/accounts/{account_handle}/sandboxes`下の[Tuist API](https://tuist.dev/api/docs)を通じて同じ操作を行うか、エージェントに<.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>を通じて使用させます。

対話的にログインできないツール（macOSサンドボックスでビルドを行うエージェントプラグインなど）は、代わりに`account:sandboxes:write`スコープを持つ<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>で認証できます。これにより、アカウントメンバーと同様に、サンドボックスの作成、コマンドの実行、一時停止、再開、削除が可能です。AmpまたはClaude統合、アナリティクス、統合設定を提供するサンドボックスの管理権限はアカウント管理者に残ります。

### サンドボックス内のTuist {#tuist-in-sandbox}

サンドボックスイメージにはTuist CLIが含まれていないため、プロジェクトでピン留めされたバージョンが実行されます。最初の`tuist sandbox sync`の後、サンドボックス上のリポジトリルートで`mise install`を実行します（`mise`および`brew`がインストールされています）。その後、miseを通じて`tuist`を実行します。例えば、`PATH`上に`$HOME/.local/share/mise/shims`を追加する方法があります。

`tuist sandbox exec`で開始するすべてのコマンドは、Tuistランナーと同じ環境を受け取るため、サンドボックス内のビルドは資格情報を渡すことなくアカウントの<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>を利用できます。

- `TUIST_URL`、およびmacOSなどサンドボックスのホストから到達可能な場所では、同じラック内にあるキャッシュの`TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`。これはそのコマンド用の短命なIDトークンです。Tuist CLI 4.218.0以降は自動的にこれでサインインします。4.215.0から4.217.xでは、同じコマンド内でまず`tuist auth login`を実行してください。

トークンは各コマンドごとに発行され、そのコマンドの実行中のみTuistトークンと交換できるため、サンドボックスが長期間有効な資格情報を保持することはありません。コマンドを開始した人物またはトークンがキャッシュに対して実行できる操作を超える権限が付与されることはありません。キャッシュ書き込みトークンのみを持つアカウントメンバーは読み取りアクセスを得られ、サンドボックスがキャッシュを利用するには、アカウントトークンに`account:sandboxes:write` alongside `ci`などのキャッシュスコープが必要です。`--env`で渡した変数が優先されます。

## コーディングエージェントからMacでビルド {#coding-agents}

Linux上で動作するコーディングエージェント（クラウドエージェントセッションなど）は、実行場所でファイルを編集し続けながら、macOSサンドボックス上でAppleプラットフォーム向けコードのビルド、テスト、実行を行えます。Ampでは、<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Macプラグイン</.localized_link>をインストールします。Claude CodeやCursorなどの他のエージェントの場合：

1. エージェントをTuist <.localized_link href="/guides/features/agentic-coding/mcp">MCPサーバー</.localized_link>に接続します。その`create_sandbox`ツールが、エージェントにMacを操作する方法を指示します。
2. エージェントが実行される環境にTuist CLIをインストールします。例えば、環境のセットアップスクリプトで`mise use -g tuist@latest`、または`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARMの場合は`tuist-linux-aarch64`）を実行します。
3. CLIを認証します。MCPサーバーのサインイン状態は引き継がれないため、アカウントメンバーとして`tuist auth login`を実行するか、`account:sandboxes:write`スコープを持つ<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を`TUIST_TOKEN`に設定します。
4. 環境がネットワークアクセスを制限している場合は、`tuist.dev`を許可してください。CLIはこのドメイン経由でMacにファイルをアップロードするため、他のドメインは不要です。

エージェントはタスクごとに1台のMacを作成し、各コマンドの実行前に`tuist sandbox sync`を実行します。Gitが無視しないファイル（コミット済みかどうかを問わず）をコピーし、以降は変更されたファイルのみをコピーします。初回の同期後、Mac上のリポジトリルートで`mise install`を実行するため、[プロジェクトでピン留めされたTuist](#tuist-in-sandbox)が利用可能になり、アカウントのキャッシュにサインインした状態になります。その後、エージェントは`tuist sandbox exec`を使って`xcodebuild`などのコマンドを実行し、`tuist sandbox cp`でスクリーンショットやビルド済みアプリなどの結果をコピーして戻し、タスクが完了するとMacを削除します。Macは最後のコマンド実行後10分間稼働し続けるため、次のコマンドはすぐに開始されます。`tuist sandbox pause`を使えば、より早くリソースを返却できます。放置されたMacは一時停止し、14日間一時停止状態が続くと削除されます。

## LinuxとmacOS {#platforms}

**Linux**サンドボックスはUbuntu 24.04で動作します：

- 2 vCPU、4 GiB RAM（デフォルト）
- 4 vCPU、8 GiB RAM
- 8 vCPU、16 GiB RAM

**macOS**サンドボックスはAppleシリコン上でXcodeとともに動作します：

- 8 vCPU、8 GiB RAM（デフォルト）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

## セキュリティ {#security}

- 各サンドボックスは独立した仮想マシンです。サンドボックス同士、またはCIジョブとファイルシステム、メモリ、プロセスを共有しません。
- サンドボックスはアカウントに属しており、その管理者のみが管理できます。統合からのセッションは、その統合が接続されているアカウントのサンドボックスにのみアクセスできます。
- AmpプロバイダートークンやClaude環境キーなど、統合の接続のためにTuistに提供した資格情報は暗号化されて保存され、再度表示されることはありません。
- サンドボックスはインターネットにアクセスできます。エージェントがそこからアクセスできるものは、CIジョブと同様に扱ってください。
