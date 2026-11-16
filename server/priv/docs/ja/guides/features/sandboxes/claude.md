---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · Features · Guides · Tuist",
  "description": "Tuist Sandboxes（Linux または macOS）で、Claude Managed Agents セッションや Claude Code クラウドセッション（claude.ai、デスクトップおよびモバイルアプリ、claude --cloud）を実行します。"
}
---
# Claude {#claude}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux と macOS の両方）は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。

Anthropic が Claude のエージェントループを実行し、*セルフホスト環境*が Claude のツールを実行する場所を決定します。これを Tuist に接続すると、その中のすべてのセッションが Linux または macOS 上で独自の Tuist <.localized_link href="/guides/features/sandboxes">サンドボックス</.localized_link> を取得します。Tuist はこれらの環境に必要なワーカーとランナーを実行するため、あなた側でホスティングする必要はありません。

環境には 2 種類あり、それぞれ Claude の製品に対応しています：

- **[Claude Managed Agents](#managed-agents)**：Claude API または Tuist の agent-sessions API で開始するセッション。[Claude Console](https://platform.claude.com/environments) で環境（`env_…`）を作成し、各セッションで Linux または macOS を選択できます。
- **[Claude Code](#claude-code)**：開発者が claude.ai、Claude デスクトップおよびモバイルアプリ、`claude --cloud` から開始するクラウドセッション。Claude Team または Enterprise のオーナーが claude.ai の管理設定でプラットフォームごとに環境（`ccpool_…`）を作成し、開発者は環境を選択することで Linux または macOS を選びます。

どちらもアカウント管理者によって Tuist API を介して接続されます。`tuist auth login` で認証してから、以下を実行します：

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 環境の接続 {#managed-agents-connect}

アカウントの **Settings → Integrations → Claude** から接続します。フォームでは、セルフホスト環境と、Tuist がセッションを開始するために使用する認証情報を求められます：

1. **環境を作成します。** Claude Console の [Environments](https://platform.claude.com/environments) ページでセルフホスト環境を作成し、開いて **Generate environment key** をクリックします。Anthropic は Console でのみ環境キーを生成します。
2. フォーム上部のセレクターで **認証情報を選択**します（下記参照）。
3. **環境 ID とキーを貼り付け**、環境のサンドボックスのプラットフォームとシェイプを選択します。

Tuist は保存前に認証情報を使用して環境を取得するため、認証情報、ID、またはワークスペースが間違っているとフォームで失敗します。キーは暗号化して保存され、再度表示されることはありません。1 分以内に、Tuist は環境のセッションの提供を開始します。シェイプについては <.localized_link href="/guides/features/sandboxes#platforms">Linux and macOS</.localized_link> を参照してください。

#### API キーを使用 {#managed-agents-connect-api-key}

デフォルトであり、サンドボックスを試す最も迅速な方法です。環境のワークスペースで開発者ロールを持つ API キーを貼り付けます。統合は API キーを使用する環境にマークを付けますが、それに依存する前に、代わりにフェデレーテッド ID で接続して、Tuist が長寿命のキーを保持しないようにしてください。

#### フェデレーテッド ID を使用 {#managed-agents-connect-federated}

Tuist は Anthropic の [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation) で認証を行うため、Anthropic API キーを提供する必要はありません。Anthropic 組織で管理者ロールが必要です。

1. **Tuist を信頼させます。** フォームにはアカウントの発行元 URL とサブジェクトプレフィックスが表示されます。Claude Console で [Workload identity](https://platform.claude.com/settings/workload-identity-federation) を開き、**Connect workload** をクリックして **Custom OIDC** を選択し、スコープ `workspace:developer` でそれらを入力します。ウィザードが作成するサービスアカウントを環境のワークスペースに追加します。
2. **ID を入力します。** 組織 ID は **Settings → Organization** に、ワークスペース ID は **Settings → Workspaces** にあります。Connect workload が完了するとサービスアカウントとフェデレーションルール ID が表示され、Workload identity のルールページでも再度確認できます。これらは秘密ではありません。Anthropic が Tuist のトークンを拒否した場合、Console の [authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history) に理由が表示されます。

#### API を使用 {#managed-agents-connect-api}

自動化から接続するには、[Claude Console](https://platform.claude.com/environments) でセルフホスト環境を作成し、そのキーを生成して、両方を Tuist に送信します：

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Tuist の API を介してセッションを開始するには、4 つのフェデレーション ID（[Connect without an API key](#managed-agents-federation) を参照）または `anthropic_api_key` のいずれかも送信します。環境は `"platform": "darwin"` を渡さない限り Linux で実行されます。`vcpus`、`memory_mb`、および `workspace_gb` はサンドボックスのシェイプを変更します。

### セッションの開始 {#managed-agents-sessions}

各セッションは、別のプラットフォームを要求しない限り、環境のプラットフォームで実行されます。

**Claude API を使用する場合**、通常どおり環境 ID でセッションを作成し、セッションのメタデータで `tuist_platform` を `macos` または `linux` に設定します：

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

`repository_url` およびオプションで `repository_ref`（ブランチまたはコミット）により、エージェントの最初のターンの前に Tuist がパブリックリポジトリをサンドボックスにクローンします。

**Tuist の agent-sessions API を使用する場合**、Tuist がエージェントとセッションを作成し、Tuist アカウントに接続されているプライベート GitHub リポジトリをクローンします：

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

アカウントに複数の環境がある場合は、`agent_environment_id` を渡します。`GET /agent-sessions/{id}/events` でセッションを追跡し、`POST /agent-sessions/{id}/messages` で返信し、`POST /agent-sessions/{id}/archive` で終了できます。

リポジトリは Linux では `/workspace`、macOS では `/Users/runner/work` にチェックアウトされます。セッションのサンドボックスは、エージェントがターンを終えた後に一時停止し、次のメッセージで再開します。

> [!WARNING]
> 環境を所有する Claude ワークスペースでセッションを作成できる人は誰でも、あなたの Tuist アカウントでセッションを実行でき、セッションメタデータで macOS を要求できます。そのワークスペースへのアクセスを適切に制限してください。

### API キーなしで接続 {#managed-agents-federation}

ダッシュボードがこれを設定します。API を介しても Tuist は同様に動作します。各アカウントには Tuist 上の独自の OpenID Connect 発行元 `https://tuist.dev/oidc/accounts/<account id>` があり、Anthropic への呼び出しごとに短命のトークンに署名し、それを数分間有効な Anthropic アクセストークンと交換します。あなたの発行元を信頼するフェデレーションルールは、Tuist が他のアカウントのために署名したトークンを受け入れません。

- すべてのエージェント環境レスポンスには `federation_issuer_url` と `federation_subject`（`account:123:agent-environment:456`）が含まれます。Console の Custom OIDC ウィザードでは、発行元 URL と、この環境のみを許可するための正確なサブジェクト、またはアカウントのすべての環境を許可するための `account:123:*` のいずれかを使用します。ダッシュボードの設定チェックでは、プレフィックスのみが許可するサブジェクト `account:123:setup` を使用します。スコープ `workspace:developer` を使用してください。
- 作成時または `PATCH /agent-environments/{id}` で、組織、ワークスペース、サービスアカウント、およびルール ID を `anthropic_organization_id`、`anthropic_workspace_id`、`anthropic_service_account_id`、および `anthropic_federation_rule_id` として送信します。環境に ID と API キーの両方がある場合、Tuist はフェデレーションを使用します。

> [!NOTE]
> Anthropic は、公開ホスト名からポート 443 の HTTPS 経由で発行元のキーを取得します。セルフホスト型の Tuist サーバーがインターネットから到達できない場合は、Console で **inline** JWKS ソースを選択し、サーバーが `<issuer>/jwks.json` で提供するキーセットを貼り付けてください。Tuist の署名鍵が変更されるたびに再度貼り付けてください。これは、サーバーの `TUIST_SECRET_KEY_TOKENS`（または設定されていない場合は `TUIST_SECRET_KEY_BASE`）が変更されたときに発生します。

## Claude Code {#claude-code}

Claude Code クラウドセッションは、開発者が [claude.ai/code](https://claude.ai/code)、Claude デスクトップおよびモバイルアプリ、`claude --cloud` から開始するものです。セッションの実行場所は環境によって決定されるため、提供したいプラットフォームごとに 1 つの環境を接続してください。

### 環境の接続 {#claude-code-connect}

1. Claude 組織のオーナーは、[Cloud environments](https://claude.ai/admin-settings/cloud-environments) 管理ページで **Allow self-hosted environments** を有効にします。これには Team または Enterprise プランが必要です。Anthropic の [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) ガイドをご覧ください。
2. 同じページで、各プラットフォーム用にセルフホスト型環境を作成します。開発者に表示される名前（例：**Tuist Linux** や **Tuist macOS**）を付けます。各環境の `ccpool_…` ID と、一度だけ表示される環境キーをコピーしてください。
3. 各環境を Tuist アカウントに接続するには、`kind` を `claude_code` に設定し、プラットフォームを指定します：

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

   もう一方の環境の ID とキーを使用して、`"platform": "linux"` で繰り返します。

1 分以内に、環境はセッションを受け取る準備が整います。アイドル状態のセッションはサンドボックスを 30 分間実行し続け、その後一時停止します。セッションの次のメッセージで同じサンドボックスが再開されます。`max_idle_seconds`（最大 3600）で待機時間を変更できます。

### Linux または macOS の選択 {#claude-code-choose}

開発者はクラウドセッションを開始する際に、環境（ひいてはプラットフォーム）を選択します：

- **claude.ai、デスクトップおよびモバイルアプリ：** 新しいセッションの環境ピッカーで **Tuist Linux** または **Tuist macOS** を選択します。
- **Claude Code CLI：** `claude` で `/remote-env` を実行し、名前で環境を選択します。その後 `claude --cloud "<task>"` がその上で実行されます。単一のセッション用に選択するには、ID を渡します：`claude --cloud "<task>" --environment ccpool_...`。
- **チーム全体またはリポジトリ：** Claude Code の [settings](https://code.claude.com/docs/en/settings) でデフォルト環境の ID を設定します。例えば、リポジトリの `.claude/settings.json` に設定します：

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

これらの環境でのセッションは、通常通り組織の Claude Code 使用量を利用し、そのサンドボックスは Tuist アカウントの使用量としてカウントされます。

### セッション開始とビルドの高速化 {#claude-code-caching}

- **Tuist キャッシュ：** セッションは `TUIST_URL` を取得し、アカウントが同じラックにキャッシュを持っている場合は `TUIST_CACHE_ENDPOINT` も取得します。セッション内の Tuist CLI および `tuist_ex` Mix タスクは、セッションの ID トークンを使用して自動的にサインインします。認証ガイドの <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link> を参照してください。
- **キャッシュされたチェックアウト：** アカウントの Tuist GitHub アプリがセッションのリポジトリを読み取れる場合、新しいセッションは Tuist ランナーが使用するのと同じキャッシュされたチェックアウトから開始されるため、クローンではなく不足しているコミットのみを取得します。セッションが終了すると、デフォルトブランチの最新コミットのオブジェクトを返却するため、Tuist で CI を実行していないリポジトリでもキャッシュされたチェックアウトが最新の状態に保たれます。GitHub がデフォルトブランチに対して報告するコミットのみがこれを更新し、セッション独自のブランチでは更新されません。これを停止するには、サンドボックスを無効にするか、アプリをアンインストールしてください。
- **macOS：** Mac は各 VM で実行される Claude Code ビルドセッションを共有するため、新しいセッションはそれをダウンロードしません。

## 任意の Claude Code セッションから Mac を使用 {#remote-mac}

Anthropic ホスト型環境でのクラウドセッションなど、Linux で実行される Claude Code セッションは、<.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link> で説明されているように、Tuist macOS サンドボックス上で Apple プラットフォームのコードをビルドおよびテストできます。**Tuist macOS** 環境とは異なり、セッションは独自の環境を維持します。

**Tuist Linux** 環境では設定不要です。Tuist CLI と Tuist MCP サーバーはすでにインストールされており、セッションの ID でサインインします。

Anthropic ホスト型環境でのクラウドセッションの場合：

1. Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> をセッションで利用可能にします。claude.ai でコネクタとして `https://tuist.dev/mcp` を追加してセッションで有効にするか、リポジトリのコミット済み `.mcp.json` で宣言します。
2. 環境の [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts) で Tuist CLI をインストールします。例えば `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` を使用します。
3. `account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> を作成し、環境の [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables) に `TUIST_TOKEN` として追加します。環境を使用するすべての人がこれを読み取れるため、キャッシュも使用できる場合を除き、他のスコープを与えないでください。Mac 上のコマンドは、トークンが持つ範囲までしか <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">cache access</.localized_link> を得られないため、Mac 上のビルドがキャッシュを読み書きできるように `ci` を追加してください。
4. 環境が Tuist に到達できるようにします。Anthropic のデフォルトの **Trusted** ネットワークアクセスには `tuist.dev` が含まれていないため、**Custom** を選択し、デフォルトのドメインを維持したまま、**Allowed domains** に `tuist.dev` を追加します。CLI は `tuist.dev` を介してセッションのファイルを Mac にアップロードするため、他のドメインは必要ありません。

最初の同期後、Claude は Mac 上のリポジトリルートで `mise install` を実行してプロジェクトでピン留めされた Tuist をインストールします。Tuist 4.218.0 以降は、各コマンドで自動的にアカウントのキャッシュにサインインします。

タスクが完了すると、Claude は Mac を削除します。置き去りにされた Mac はアイドル時に一時停止し、14 日間一時停止状態が続くと削除されます。この方法で作成された Mac は、他のサンドボックスと同様に Tuist アカウントの使用量としてカウントされます。
