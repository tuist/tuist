---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · Features · Guides · Tuist",
  "description": "Tuist Sandboxes（Linux または macOS）で Claude Managed Agents セッションと Claude Code クラウドセッション（claude.ai、デスクトップおよびモバイルアプリ、claude --cloud）を実行します。"
}
---
# Claude {#claude}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（LinuxとmacOSの両方）は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティSlack](https://slack.tuist.dev)でご連絡ください。

AnthropicがClaudeのエージェントループを実行し、*セルフホスト型環境*がClaudeのツールを実行する場所を決定します。これをTuistに接続すると、その環境内のすべてのセッションが、LinuxまたはmacOS上で独自のTuist <.localized_link href="/guides/features/sandboxes">サンドボックス</.localized_link>を取得します。Tuistはこれらの環境に必要なワーカーとランナーを実行するため、あなたは何もホストする必要がありません。

環境には2種類あり、それぞれClaude製品に対応しています：

- **[Claude Managed Agents](#managed-agents)**：Claude APIまたはTuistのagent-sessions APIを使用して開始するセッション。[Claude Console](https://platform.claude.com/environments)で環境（`env_…`）を作成し、各セッションでLinuxまたはmacOSを選択できます。
- **[Claude Code](#claude-code)**：開発者がclaude.ai、Claudeのデスクトップおよびモバイルアプリ、`claude --cloud`から開始するクラウドセッション。Claude TeamまたはEnterpriseのオーナーがclaude.aiの管理設定でプラットフォームごとに環境（`ccpool_…`）を作成し、開発者は環境を選択することでLinuxまたはmacOSを選びます。

どちらもアカウント管理者によってTuist APIを通じて接続されます。`tuist auth login`で認証してから、以下を実行してください：

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 環境を接続する {#managed-agents-connect}

アカウントの**Settings → Integrations → Claude**から接続します。フォームでは、セルフホスト型環境と、Tuistがセッションを開始するために使用する資格情報を求められます：

1. **環境を作成します。** Claude Consoleの[Environments](https://platform.claude.com/environments)ページでセルフホスト型環境を作成し、開いて**Generate environment key**をクリックします。AnthropicはConsoleでのみ環境キーを生成します。
2. フォーム上部のセレクターで**資格情報を選択**します（下記参照）。
3. **環境IDとキーを貼り付け**、環境のサンドボックスのプラットフォームとシェイプを選択します。

Tuistは保存前に資格情報を使って環境を取得するため、資格情報、ID、またはワークスペースが間違っているとフォームで失敗します。キーは暗号化して保存され、二度と表示されません。1分以内に、Tuistは環境のセッションの提供を開始します。シェイプについては<.localized_link href="/guides/features/sandboxes#platforms">LinuxとmacOS</.localized_link>を参照してください。

#### APIキーを使用する場合 {#managed-agents-connect-api-key}

デフォルトであり、サンドボックスを試す最も迅速な方法です。環境のワークスペースで開発者ロールを持つAPIキーを貼り付けます。統合機能はAPIキーを使用する環境をマークします。依存する前に、代わりにフェデレーテッドアイデンティティで接続し、Tuistが長寿命のキーを保持しないようにしてください。

#### フェデレーテッドアイデンティティを使用する場合 {#managed-agents-connect-federated}

TuistはAnthropicの[Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)で認証を行うため、Anthropic APIキーを提供する必要はありません。Anthropic組織で管理者ロールが必要です。

1. **Tuistを信頼します。** フォームにはアカウントのissuer URLとsubject prefixが表示されます。Claude Consoleで[Workload identity](https://platform.claude.com/settings/workload-identity-federation)を開き、**Connect workload**をクリックして**Custom OIDC**を選択し、スコープ`workspace:developer`とともにそれらを入力します。ウィザードが作成するサービスアカウントを環境のワークスペースに追加します。
2. **IDを入力します。** 組織IDは**Settings → Organization**の下に、ワークスペースIDは**Settings → Workspaces**の下にあります。Connect workloadが完了すると、サービスアカウントとフェデレーションルールIDが表示され、Workload identityのルールページでも再度表示されます。これらはすべて秘密ではありません。AnthropicがTuistのトークンを拒否した場合、Consoleの[authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history)に理由が表示されます。

#### APIを使用する場合 {#managed-agents-connect-api}

自動化から接続するには、[Claude Console](https://platform.claude.com/environments)でセルフホスト型環境を作成し、そのキーを生成して、両方をTuistに送信します：

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

TuistのAPIを通じてセッションを開始するには、4つのフェデレーションID（[APIキーなしで接続](#managed-agents-federation)を参照）または`anthropic_api_key`のいずれかも送信します。環境は`"platform": "darwin"`を渡さない限りLinux上で実行されます。`vcpus`、`memory_mb`、`workspace_gb`はサンドボックスのシェイプを変更し、`xcode_version`はmacOSサンドボックスの[Xcode](#xcode)を変更します。

### セッションを開始する {#managed-agents-sessions}

各セッションは、セッションが別のプラットフォームを要求しない限り、環境のプラットフォーム上で実行されます。

**Claude APIを使用する場合**、通常通り環境のIDでセッションを作成し、セッションのメタデータで`tuist_platform`を`macos`または`linux`に設定します：

```bash
curl https://api.anthropic.com/v1/sessions \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -H "content-type: application/json" \
  -d '{
    "agent": "agent_...",
    "environment_id": "env_...",
    "metadata": {
      "tuist_platform": "macos",
      "repository_url": "https://github.com/my-org/my-app"
    }
  }'
```

`repository_url`およびオプションで`repository_ref`（ブランチまたはコミット）により、エージェントの最初のターン前にTuistがパブリックリポジトリをサンドボックスにクローンします。

**Tuistのagent-sessions APIを使用する場合**、Tuistがエージェントとセッションを作成し、Tuistアカウントに接続されているプライベートGitHubリポジトリをクローンします：

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-sessions" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "prompt": "Fix the failing snapshot tests",
    "platform": "darwin",
    "repository_url": "https://github.com/my-org/my-app",
    "repository_ref": "main"
  }'
```

アカウントに複数の環境がある場合は、`agent_environment_id`を渡します。`GET /agent-sessions/{id}/events`でセッションを追跡し、`POST /agent-sessions/{id}/messages`で返信し、`POST /agent-sessions/{id}/archive`で終了できます。

リポジトリはLinuxでは`/workspace`、macOSでは`/Users/runner/work`にチェックアウトされます。セッションのサンドボックスは、エージェントがターンを終えると一時停止し、次のメッセージで再開します。

### セッションのXcodeを選択する {#managed-agents-xcode}

セッションのMacはClaudeがツールを実行する前に起動するため、Claudeは自身のXcodeを選択できません。セッションを作成する人が、macOSを選択するのと同じ方法でXcodeを選択します。Tuistは、設定されている以下の最初の項目を使用します：

1. Tuistのagent-sessions APIで、`platform`の隣にある`xcode_version`。Tuistが提供していないバージョンは、セッション作成時に拒否され、選択可能なバージョンのリストが表示されます。
2. Claude APIでセッションを作成する際、セッションのメタデータ内の`tuist_xcode_version`：

   ```json
   "metadata": { "tuist_platform": "macos", "tuist_xcode_version": "26.1.1" }
   ```

3. セッションが環境のプラットフォームで実行される場合、環境の`xcode_version`。
4. デフォルトのXcode。

プラットフォーム指定のないXcodeはmacOSを要求します。知っておくべき点：

- **セッションはXcodeを維持します。** サンドボックスは一度だけ起動し、後続のメッセージや変更されたメタデータによって移動することはありません。別のXcodeを使用するには、新しいセッションを使用してください。
- **Tuistは最初のターン到達時にメタデータを確認します。**`tuist_xcode_version`がTuistが提供していないXcodeを指定している場合、Tuistはそのターンをサンドボックス起動なしで停止し、選択可能なバージョンをログに記録します。セッション作成時にエラーを取得するには、Tuistのagent-sessions APIを使用してください。
- **macOS環境では、Tuistは推測せずに待機します。** Tuistが新しいセッションのメタデータを読み取れない場合、環境のXcodeを起動する代わりにターンを保留し、再試行します。

> [!WARNING]
> 環境を所有するClaudeワークスペースでセッションを作成できる人は誰でも、あなたのTuistアカウントでセッションを実行でき、セッションメタデータを使用してmacOSとそのXcodeを要求できます。そのワークスペースへのアクセスを適切に制限してください。

### APIキーなしで接続する {#managed-agents-federation}

ダッシュボードがこれを設定してくれます。API経由でもTuistは同様に動作します：各アカウントにはTuist上の独自のOpenID Connect発行者`https://tuist.dev/oidc/accounts/<account id>`があり、Anthropicへの呼び出しごとに短命トークンに署名し、それを数分間有効なAnthropicアクセストークンと交換します。あなたの発行者を信頼するフェデレーションルールは、Tuistが他のアカウントのために署名したトークンを決して受け入れません。

- すべてのエージェント環境レスポンスには`federation_issuer_url`と`federation_subject`（`account:123:agent-environment:456`）が含まれます。コンソールのCustom OIDCウィザードでは、発行者URLを使用し、この環境のみを許可するにはその正確なサブジェクトを、アカウントのすべての環境を許可するには`account:123:*`を使用してください。ダッシュボードの設定チェックでは、プレフィックスのみが許可するサブジェクト`account:123:setup`を使用します。スコープ`workspace:developer`を使用してください。
- 作成時または`PATCH /agent-environments/{id}`で、組織、ワークスペース、サービスアカウント、およびルールIDを`anthropic_organization_id`、`anthropic_workspace_id`、`anthropic_service_account_id`、および`anthropic_federation_rule_id`として送信します。環境にIDとAPIキーの両方がある場合、Tuistはフェデレーションを使用します。

> [!NOTE]
> Anthropicは、公開ホスト名からポート443のHTTPS経由で発行者のキーを取得します。セルフホストされたTuistサーバーがインターネットから到達できない場合は、コンソールで**インライン**JWKSソースを選択し、サーバーが`<issuer>/jwks.json`で提供するキーセットを貼り付けてください。Tuistの署名キーが変更されるたびに再度貼り付けてください。これは、サーバーの`TUIST_SECRET_KEY_TOKENS`（または未設定の場合は`TUIST_SECRET_KEY_BASE`）が変更されたときに発生します。

## Claude Code {#claude-code}

Claude Codeクラウドセッションは、開発者が[claude.ai/code](https://claude.ai/code)、Claudeデスクトップおよびモバイルアプリ、および`claude --cloud`から開始するものです。セッションの実行場所は環境によって選択されるため、提供したいプラットフォームごとに1つの環境を接続します。

### 環境を接続する {#claude-code-connect}

1. Claude組織のオーナーは、[Cloud environments](https://claude.ai/admin-settings/cloud-environments)管理ページで**Allow self-hosted environments**を有効にします。これにはTeamまたはEnterpriseプランが必要です。Anthropicの[self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments)ガイドをご覧ください。
2. 同じページで、各プラットフォーム用にセルフホスト環境を作成し、開発者に表示される名前（例：**Tuist Linux**および**Tuist macOS**）を付けます。各環境の`ccpool_…` IDと、一度しか表示されない環境キーをコピーしてください。
3. `kind`を`claude_code`およびそのプラットフォームに設定して、各環境をTuistアカウントに接続します：

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "kind": "claude_code",
       "platform": "darwin",
       "name": "Tuist macOS",
       "anthropic_environment_id": "ccpool_...",
       "environment_key": "<environment key>"
     }'
   ```

   `"platform": "linux"`および他の環境のIDとキーを使用して繰り返します。

1分以内に、環境はセッションを受け取る準備ができます。アイドル状態のセッションはサンドボックスを30分間実行し続け、その後一時停止します。セッションの次のメッセージで同じサンドボックスが再開されます。`max_idle_seconds`（最大3600）で待機時間を変更できます。

### LinuxまたはmacOSを選択する {#claude-code-choose}

開発者はクラウドセッションを開始する際に環境、ひいてはプラットフォームを選択します：

- **claude.ai、デスクトップおよびモバイルアプリ：** 新しいセッションの環境ピッカーで**Tuist Linux**または**Tuist macOS**を選択します。
- **Claude Code CLI：**`claude`で`/remote-env`を実行し、名前で環境を選択します。`claude --cloud "<task>"`はその後そこで実行されます。単一セッション用に1つを選択するには、そのIDを渡します：`claude --cloud "<task>" --environment ccpool_...`。
- **チーム全体またはリポジトリ：** Claude Codeの[settings](https://code.claude.com/docs/en/settings)でデフォルト環境のIDを設定します。例えば、リポジトリの`.claude/settings.json`で：

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

これらの環境でのセッションは、通常通り組織のClaude Code使用量を利用し、そのサンドボックスはTuistアカウントのカウントに含まれます。

### Xcodeを選択する {#xcode}

各macOS環境は1つの<.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>を起動します。`xcode_version`で接続しない限りデフォルトになります。例えば`"xcode_version": "26.1.1"`。複数提供するには、それぞれ用に環境を接続し、それに合わせて名前を付けます。例えば**Tuist macOS · Xcode 26.1.1**。開発者は環境を選択することでXcodeを選びます。

環境を別のXcodeに移行するには、更新します：

```bash
curl -X PATCH "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments/<id>" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{ "xcode_version": "27.0" }'
```

新しいセッションは新しいXcodeを取得し、すでにサンドボックスを持つセッションは既存のものを使用します。`null`はデフォルトに戻ります。これは、セッションが独自に[選択できる](#managed-agents-xcode)Managed Agents環境にも適用されます。

### セッションの開始とビルドを高速化 {#claude-code-caching}

- **Tuistキャッシュ：** セッションは`TUIST_URL`を取得し、アカウントが同じラックにキャッシュを持っている場合は`TUIST_CACHE_ENDPOINT`も取得します。セッション内のTuist CLIと`tuist_ex` Mixタスクは、セッションのIDトークンを使用して自動的にサインインします。認証ガイドの<.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link>をご覧ください。
- **キャッシュされたチェックアウト：** アカウントのTuist GitHubアプリがセッションのリポジトリを読み取れる場合、新しいセッションはTuistランナーが使用するのと同じキャッシュされたチェックアウトから開始されるため、クローンではなく欠けているコミットのみを取得します。セッション終了時、デフォルトブランチの最新コミットのオブジェクトを返却するため、TuistでCIを実行していないリポジトリでもキャッシュされたチェックアウトが最新の状態に保たれます。GitHubがデフォルトブランチに対して報告するコミットのみが更新を引き起こし、セッション独自のブランチは更新しません。これを停止するには、サンドボックスを無効にするか、アプリをアンインストールしてください。
- **macOS：** Macは各VMで実行されるClaude Codeビルドセッションを共有するため、新しいセッションはそれをダウンロードしません。

## 任意のClaude CodeセッションからMacを使用する {#remote-mac}

Anthropicホスト環境でのクラウドセッションなど、Linuxで実行されるClaude Codeセッションは、<.localized_link href="/guides/features/sandboxes#coding-agents">コーディングエージェントからMacでビルド</.localized_link>で説明されているように、Tuist macOSサンドボックスでAppleプラットフォームコードのビルドとテストを引き続き実行できます。**Tuist macOS**環境とは異なり、セッションは独自の環境を維持します。

**Tuist Linux**環境では設定不要です。Tuist CLIとTuist MCPサーバーはすでにインストールされており、セッションのIDでサインインします。

Anthropicホスト環境でのクラウドセッションの場合：

1. Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCPサーバー</.localized_link>をセッションで利用可能にします：claude.aiでコネクタとして`https://tuist.dev/mcp`を追加し、セッションで有効にするか、リポジトリのコミット済み`.mcp.json`で宣言します。
2. 環境の[setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts)にTuist CLIをインストールします。例えば`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`を使用します。
3. <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を`account:sandboxes:write`スコープで作成し、環境の[環境変数](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)に`TUIST_TOKEN`として追加します。環境を利用するすべてのユーザーがこれを読み取れるため、キャッシュも利用する可能性がある場合を除き、他のスコープは付与しないでください。Mac上のコマンドはトークンが持つ範囲でのみ<.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">キャッシュアクセス</.localized_link>を得られるため、Macでのビルドがキャッシュの読み書きを行えるよう`ci`を追加してください。
4. 環境からTuistにアクセスできるようにします。Anthropicのデフォルトである**Trusted**ネットワークアクセスには`tuist.dev`が含まれていないため、**Custom**を選択し、デフォルトのドメインを維持したまま`tuist.dev`を**Allowed domains**に追加します。CLIは`tuist.dev`経由でセッションのファイルをMacにアップロードするため、他のドメインは必要ありません。

MacにはTuist CLIがインストールされており、miseでバージョンを固定している場合はプロジェクト固有のバージョンを実行します。Tuist 4.218.0以降では、各コマンド実行時に自動的にアカウントのキャッシュにサインインします。

### 準備済みのMac {#remote-mac-snapshots}

**Tuist Linux**環境では、これらのMacを事前に準備できます。APIを使用してmacOSセットアップスクリプトを設定します（`PATCH /api/accounts/{account}/sandboxes/agent-environments/{id}`における`macos_setup_script`）。例：

```bash
mise install
tuist install
tuist generate --no-open
xcodebuild build -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 17'
```

ClaudeがTuistプロジェクトのいずれかに接続されたリポジトリ用のMacを作成すると、`create_sandbox`がリポジトリを取得し、MacはそのリポジトリのスナップショットからXcode用に起動します。デフォルトブランチは`~/work/<name>`にクローンされ、スクリプトがそこで実行済みであり、ビルド成果物が配置されています。最初の`tuist sandbox sync`ではそのコミットと異なるファイルのみを送信するため、Xcodeは変更された部分のみを再ビルドします。リポジトリとXcodeの組み合わせにおける最初のMacは空の状態から起動し、後続のMacのために最大1時間アイドル状態のMacでスナップショットがビルドされます。スクリプト、Xcode、またはイメージを変更すると、再度ビルドが行われます。

タスク完了時、ClaudeはMacを削除します。残されたMacはアイドル状態で一時停止し、14日間一時停止状態が続くと削除されます。この方法で作成されたMacは、他のサンドボックスと同様にTuistアカウントの利用枠に含まれます。
