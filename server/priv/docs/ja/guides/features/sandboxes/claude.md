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
> Tuist Sandboxes（Linux と macOS の両方）は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)するか、[コミュニティ Slack](https://slack.tuist.dev)でメッセージを送ってください。

Anthropic が Claude のエージェントループを実行し、*セルフホスト環境*が Claude のツールを実行する場所を決定します。これを Tuist に接続すると、その環境内のすべてのセッションが、Linux または macOS 上で独自の Tuist <.localized_link href="/guides/features/sandboxes">サンドボックス</.localized_link>を取得します。Tuist はこれらの環境に必要なワーカーとランナーを実行するため、あなた側でホスティングする必要はありません。

環境には 2 種類あり、Claude の製品ごとに 1 つずつあります。

- **[Claude Managed Agents](#managed-agents)**：Claude API または Tuist の agent-sessions API で開始するセッション。[Claude Console](https://platform.claude.com/environments)で環境（`env_…`）を作成し、各セッションで Linux または macOS を選択できます。
- **[Claude Code](#claude-code)**：開発者が claude.ai、Claude デスクトップおよびモバイルアプリ、`claude --cloud`から開始するクラウドセッション。Claude Team または Enterprise のオーナーが claude.ai の管理設定でプラットフォームごとに環境（`ccpool_…`）を作成し、開発者は環境を選択することで Linux または macOS を選びます。

どちらもアカウント管理者によって Tuist API を介して接続されます。`tuist auth login`で認証してから、以下を実行してください。

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 環境を接続する {#managed-agents-connect}

アカウントの**Settings → Integrations → Claude**から接続します。フォームでは、セルフホスト環境と、Tuist がセッションを開始するために使用するクレデンシャルを求められます。

1. **環境を作成します。** Claude Console の[Environments](https://platform.claude.com/environments)ページでセルフホスト環境を作成し、開いて**Generate environment key**をクリックします。Anthropic は Console でのみ環境キーを生成します。
2. フォーム上部のセレクターで**クレデンシャルを選択**します（下記参照）。
3. **環境 ID とキーを貼り付け**、環境のサンドボックスのプラットフォームとシェイプを選択します。

Tuist は保存前にクレデンシャルを使用して環境を取得するため、クレデンシャル、ID、またはワークスペースが間違っているとフォームで失敗します。キーは暗号化して保存され、再度表示されることはありません。1 分以内に、Tuist は環境のセッションの提供を開始します。シェイプについては<.localized_link href="/guides/features/sandboxes#platforms">Linux と macOS</.localized_link>を参照してください。

#### API キーを使用 {#managed-agents-connect-api-key}

デフォルトであり、サンドボックスを試す最も迅速な方法です。環境のワークスペースで開発者ロールを持つ API キーを貼り付けます。統合機能は API キーを使用する環境にマークを付けます。依存する前に、代わりにフェデレーティッドアイデンティティで接続し、Tuist が長寿命のキーを保持しないようにしてください。

#### フェデレーティッドアイデンティティを使用 {#managed-agents-connect-federated}

Tuist は Anthropic の[Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)で認証を行うため、Anthropic API キーを提供する必要はありません。Anthropic 組織で管理者ロールが必要です。

1. **Tuist を信頼させます。** フォームにはアカウントの発行者 URL とサブジェクトプレフィックスが表示されます。Claude Console で[Workload identity](https://platform.claude.com/settings/workload-identity-federation)を開き、**Connect workload**をクリックして**Custom OIDC**を選択し、スコープ`workspace:developer`とともにそれらを入力します。ウィザードが作成したサービスアカウントを環境のワークスペースに追加します。
2. **ID を入力します。** 組織 ID は**Settings → Organization**の下に、ワークスペース ID は**Settings → Workspaces**の下にあります。Connect workload が完了すると、サービスアカウントとフェデレーションルール ID が表示され、Workload identity のルールページでも再度表示されます。これらは秘密情報ではありません。Anthropic が Tuist のトークンを拒否した場合、Console の[authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history)に理由が表示されます。

#### API を使用 {#managed-agents-connect-api}

自動化から接続するには、[Claude Console](https://platform.claude.com/environments)でセルフホスト環境を作成し、そのキーを生成して、両方を Tuist に送信します。

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Tuist の API を介してセッションを開始するには、4 つのフェデレーション ID（[API キーなしで接続](#managed-agents-federation)を参照）または`anthropic_api_key`のいずれかも送信します。環境は`"platform": "darwin"`を渡さない限り Linux で実行されます。`vcpus`、`memory_mb`、および`workspace_gb`はサンドボックスのシェイプを変更し、`xcode_version`は macOS サンドボックスの[Xcode](#xcode)を変更します。

### セッションを開始 {#managed-agents-sessions}

各セッションは、別のプラットフォームを要求しない限り、環境のプラットフォームで実行されます。

**Claude API を使用**する場合、通常どおり環境 ID でセッションを作成し、セッションのメタデータで`tuist_platform`を`macos`または`linux`に設定します。

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

`repository_url`およびオプションで`repository_ref`（ブランチまたはコミット）により、エージェントの最初のターンの前に Tuist がパブリックリポジトリをサンドボックスにクローンします。

**Tuist の agent-sessions API を使用**する場合、Tuist がエージェントとセッションを作成し、Tuist アカウントに接続されているプライベート GitHub リポジトリをクローンします。

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

リポジトリは Linux では`/workspace`、macOS では`/Users/runner/work`にチェックアウトされます。セッションのサンドボックスは、エージェントがターンを終えた後に一時停止し、次のメッセージで再開します。

### セッションの Xcode を選択 {#managed-agents-xcode}

セッションの Mac は Claude がツールを実行する前に起動するため、Claude は独自の Xcode を選択できません。セッションを作成する人が、macOS を選択するのと同じ方法で Xcode を選択します。Tuist は設定されている以下の最初の項目を使用します。

1. Tuist の agent-sessions API で`platform`の隣にある`xcode_version`。Tuist が提供していないバージョンは、セッション作成時に拒否され、選択可能なバージョンのリストが表示されます。
2. Claude API でセッションを作成する際、セッションのメタデータ内の`tuist_xcode_version`。

   ```json
   "metadata": { "tuist_platform": "macos", "tuist_xcode_version": "26.1.1" }
   ```

3. セッションが環境のプラットフォームで実行される場合、環境の`xcode_version`。
4. デフォルトの Xcode。

プラットフォームなしの Xcode は macOS を要求します。知っておくべきこと：

- **セッションはその Xcode を維持します。** サンドボックスは一度だけ起動し、後のメッセージや変更されたメタデータによって移動することはありません。別の Xcode を使用する場合は、新しいセッションを使用してください。
- **Tuist は最初のターンが到着したときにメタデータを確認します。**`tuist_xcode_version`が Tuist が提供していない Xcode を指定している場合、Tuist はサンドボックスを起動せずにそのターンを停止し、選択可能なバージョンをログに記録します。セッション作成時にエラーを取得するには、Tuist の agent-sessions API を使用してください。
- **macOS 環境では、Tuist は推測せずに待機します。** Tuist が新しいセッションのメタデータを読み取れない場合、環境の Xcode を起動する代わりにターンを保留し、再試行します。

> [!WARNING]
> 環境を所有する Claude ワークスペースでセッションを作成できる人は誰でも、あなたの Tuist アカウントでセッションを実行でき、セッションメタデータを使用して macOS とその Xcode を要求できます。それに応じて、そのワークスペースへのアクセスを制限してください。

### API キーなしで接続 {#managed-agents-federation}

ダッシュボードがこれを設定します。API を介して、Tuist も同様に動作します。各アカウントには Tuist 上の独自の OpenID Connect イシューアー `https://tuist.dev/oidc/accounts/<account id>` があり、Anthropic への呼び出しごとに短命のトークンに署名し、それを数分間有効な Anthropic アクセストークンと交換します。あなたのイシューアーを信頼するフェデレーションルールは、Tuist が他のアカウントのために署名したトークンを決して受け入れません。

- すべてのエージェント環境レスポンスには `federation_issuer_url` と `federation_subject`（`account:123:agent-environment:456`）が含まれます。コンソールの Custom OIDC ウィザードで、イシューアー URL と、この環境のみを許可するための正確なサブジェクト、またはアカウントのすべての環境を許可するための `account:123:*` のいずれかを使用します。ダッシュボードのセットアップチェックでは、プレフィックスのみが許可するサブジェクト `account:123:setup` を使用します。スコープ `workspace:developer` を使用してください。
- 作成時または `PATCH /agent-environments/{id}` で、組織、ワークスペース、サービスアカウント、およびルールの ID を `anthropic_organization_id`、`anthropic_workspace_id`、`anthropic_service_account_id`、`anthropic_federation_rule_id` として送信します。環境に ID と API キーの両方がある場合、Tuist はフェデレーションを使用します。

> [!NOTE]
> Anthropic は、公開ホスト名からポート 443 の HTTPS 経由でイシューアーのキーを取得します。セルフホスト型の Tuist サーバーがインターネットから到達できない場合は、コンソールで **インライン** JWKS ソースを選択し、サーバーが `<issuer>/jwks.json` で提供しているキーセットを貼り付けます。Tuist の署名キーが変更されるたびに再度貼り付けてください。これは、サーバーの `TUIST_SECRET_KEY_TOKENS`（または設定されていない場合は `TUIST_SECRET_KEY_BASE`）が変更されたときに発生します。

## Claude Code {#claude-code}

Claude Code クラウドセッションは、開発者が [claude.ai/code](https://claude.ai/code)、Claude デスクトップおよびモバイルアプリ、`claude --cloud` から開始するものです。セッションの実行場所は環境によって選択されるため、提供したいプラットフォームごとに 1 つの環境を接続します。

### 環境を接続 {#claude-code-connect}

1. Claude 組織のオーナーは、[Cloud environments](https://claude.ai/admin-settings/cloud-environments) 管理ページで **Allow self-hosted environments** を有効にします。これには Team または Enterprise プランが必要です。Anthropic の [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) ガイドをご覧ください。
2. 同じページで、各プラットフォーム用のセルフホスト型環境を開発者に表示される名前で作成します。例えば **Tuist Linux** や **Tuist macOS** です。各環境の `ccpool_…` ID と、一度だけ表示される環境キーをコピーします。
3. `kind` を `claude_code` およびそのプラットフォームに設定して、各環境を Tuist アカウントに接続します。

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

   `"platform": "linux"` と他の環境の ID およびキーで繰り返します。

1 分以内に、環境はセッションを受け取る準備が整います。アイドル状態のセッションはサンドボックスを 30 分間実行し続け、その後一時停止します。セッションの次のメッセージで同じサンドボックスが再開されます。`max_idle_seconds`（最大 3600）で待機時間を変更します。

### Linux または macOS を選択 {#claude-code-choose}

開発者はクラウドセッションを開始する際に環境、ひいてはプラットフォームを選択します。

- **claude.ai、デスクトップおよびモバイルアプリ：** 新しいセッションの環境ピッカーで **Tuist Linux** または **Tuist macOS** を選択します。
- **Claude Code CLI：**`claude` で `/remote-env` を実行し、名前で環境を選択します。その後 `claude --cloud "<task>"` がその上で実行されます。単一のセッション用に 1 つを選択するには、その ID を渡します：`claude --cloud "<task>" --environment ccpool_...`。
- **チーム全体またはリポジトリ：** Claude Code の [settings](https://code.claude.com/docs/en/settings) でデフォルト環境の ID を設定します。例えば、リポジトリの `.claude/settings.json` などです。

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

これらの環境でのセッションは通常通り組織の Claude Code 使用量を利用し、そのサンドボックスは Tuist アカウントの使用量に計上されます。

### Xcode を選択 {#xcode}

各 macOS 環境は 1 つの <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link> を起動します。`xcode_version` で接続しない限りデフォルトになります。例えば `"xcode_version": "26.1.1"` です。複数を提供するには、それぞれに対して環境を接続し、それに合わせて名前を付けます。例えば **Tuist macOS · Xcode 26.1.1** です。開発者は環境を選択することで Xcode を選びます。

環境を別の Xcode に移動するには、更新します。

```bash
curl -X PATCH "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments/<id>" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{ "xcode_version": "27.0" }'
```

新しいセッションは新しい Xcode を取得し、すでにサンドボックスを持っているセッションはそのまま維持します。`null` はデフォルトに戻ります。これは Managed Agents 環境にも適用され、そのセッションも [独自のものを選択](#managed-agents-xcode)できます。

### セッションの開始とビルドの高速化 {#claude-code-caching}

- **Tuist キャッシュ：** セッションは `TUIST_URL` を取得し、アカウントが同じラックにキャッシュを持っている場合は `TUIST_CACHE_ENDPOINT` も取得します。セッション内の Tuist CLI と `tuist_ex` Mix タスクは、セッションの ID トークンを使用して自動的にサインインします。認証ガイドの <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link> を参照してください。
- **キャッシュされたチェックアウト：** アカウントの Tuist GitHub アプリがセッションのリポジトリを読み取れる場合、新しいセッションは Tuist ランナーが使用するのと同じキャッシュされたチェックアウトから開始されるため、クローンではなく欠けているコミットのみを取得します。セッションが終了すると、デフォルトブランチの最新コミットのオブジェクトを返却するため、Tuist で CI を実行していないリポジトリでもキャッシュされたチェックアウトが最新の状態に保たれます。GitHub がデフォルトブランチについて報告するコミットのみがそれを更新し、セッション独自のブランチが行うことはありません。これを停止するには、サンドボックスを無効にするか、アプリをアンインストールします。
- **macOS：** Mac は各 VM で実行される Claude Code ビルドセッションを共有するため、新しいセッションはそれをダウンロードしません。

## 任意の Claude Code セッションから Mac を使用 {#remote-mac}

Anthropic ホスト環境でのクラウドセッションなど、Linux で実行される Claude Code セッションは、<.localized_link href="/guides/features/sandboxes#coding-agents">コーディングエージェントから Mac でビルド</.localized_link> で説明されているように、Tuist macOS サンドボックスで Apple プラットフォームのコードをビルドおよびテストできます。**Tuist macOS** 環境とは異なり、セッションは独自の環境を維持します。

**Tuist Linux** 環境では設定する必要はありません。Tuist CLI と Tuist MCP サーバーはすでにインストールされており、セッションの ID でサインインします。

Anthropic ホスト環境でのクラウドセッションの場合：

1. Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP サーバー</.localized_link> をセッションで利用可能にします。claude.ai で `https://tuist.dev/mcp` をコネクタとして追加し、セッションで有効にするか、リポジトリのコミット済み `.mcp.json` で宣言します。
2. 環境の [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts) に Tuist CLI をインストールします。例えば `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` を使用します。
3. <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を `account:sandboxes:write` スコープで作成し、環境の [環境変数](https://code.claude.com/docs/en/cloud-environments#set-environment-variables) に `TUIST_TOKEN` として追加します。環境を使用するすべての人がこれを読み取れるため、キャッシュも使用できる場合を除き、他のスコープは付与しないでください。Mac のコマンドが <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">キャッシュへのアクセス</.localized_link> を得られるのはトークンが許可する範囲までであるため、Mac でのビルドがキャッシュを読み書きできるように `ci` を追加します。
4. 環境から Tuist にアクセスできるようにします。Anthropic のデフォルトの **Trusted** ネットワークアクセスには `tuist.dev` が含まれていないため、**Custom** を選択し、デフォルトのドメインを維持したまま `tuist.dev` を **Allowed domains** に追加します。CLI は `tuist.dev` を介してセッションのファイルを Mac にアップロードするため、他のドメインは必要ありません。

最初の同期後、Claude は Mac 上のリポジトリルートで `mise install` を実行してプロジェクトでピン留めされた Tuist をインストールします。Tuist 4.218.0 以降では、各コマンドで自動的にアカウントのキャッシュにサインインします。

タスクが完了すると、Claude は Mac を削除します。残された Mac はアイドル状態になると一時停止し、14 日間一時停止した後に削除されます。この方法で作成された Mac は、他のサンドボックスと同様に Tuist アカウントの利用枠にカウントされます。
