---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · Features · Guides · Tuist",
  "description": "Tuist Sandboxes（LinuxまたはmacOS）で、Claude Managed AgentsセッションやClaude Codeクラウドセッション（claude.ai、デスクトップおよびモバイルアプリ、およびclaude --cloud）を実行します。"
}
---
# Claude {#claude}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux と macOS の両方）は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev)でご連絡ください。

Anthropic が Claude のエージェントループを実行し、*セルフホスト環境*が Claude のツールを実行する場所を決定します。これを Tuist に接続すると、その環境内のすべてのセッションが、Linux または macOS 上で独自の Tuist <.localized_link href="/guides/features/sandboxes">サンドボックス</.localized_link>を取得します。Tuist はそれらの環境に必要なワーカーとランナーを実行するため、あなたは何もホストする必要はありません。

環境には 2 種類あり、それぞれ Claude の製品に対応しています：

- **[Claude Managed Agents](#managed-agents)**：Claude API または Tuist の agent-sessions API を使用して開始するセッションです。[Claude Console](https://platform.claude.com/environments)で環境（`env_…`）を作成し、各セッションで Linux または macOS を選択できます。
- **[Claude Code](#claude-code)**：開発者が claude.ai、Claude デスクトップおよびモバイルアプリ、`claude --cloud`から開始するクラウドセッションです。Claude Team または Enterprise のオーナーが claude.ai の管理設定でプラットフォームごとに環境（`ccpool_…`）を作成し、開発者は環境を選択することで Linux または macOS を選びます。

どちらもアカウント管理者によって Tuist API を介して接続されます。`tuist auth login`で認証してから、以下を実行してください：

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 環境を接続する {#managed-agents-connect}

1. [Claude Console](https://platform.claude.com/environments)で**環境を作成**をクリックし、**ホスティング**の下で**セルフホスト**を選択します。環境を開き、**環境キーを生成**をクリックして、環境の`env_…` ID とキーをコピーします。詳細については、Anthropic の[セルフホストサンドボックス](https://platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes)ガイドをご覧ください。
2. これをあなたの Tuist アカウントに接続します：

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "anthropic_environment_id": "env_...",
       "environment_key": "<environment key>",
       "anthropic_api_key": "<Anthropic API key>"
     }'
   ```

   `anthropic_api_key`はオプションです。これにより、後述するように Tuist の API を介してセッションを開始できます。Tuist は両方のキーを暗号化して保存し、返すことはありません。

1 分以内に、Tuist は環境のセッションの提供を開始します。環境は、`"platform": "darwin"`を渡さない限り Linux で実行されます。`vcpus`、`memory_mb`、および`workspace_gb`を渡してサンドボックスの形状を変更することもできます。<.localized_link href="/guides/features/sandboxes#platforms">Linux と macOS</.localized_link>を参照してください。

### セッションを開始する {#managed-agents-sessions}

各セッションは、別のプラットフォームを要求しない限り、環境のプラットフォームで実行されます。

**Claude API を使用する場合**、通常どおり環境の ID を指定してセッションを作成し、セッションのメタデータで`tuist_platform`を`macos`または`linux`に設定します：

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

`repository_url`およびオプションで`repository_ref`（ブランチまたはコミット）を指定すると、エージェントの最初のターン前に Tuist がパブリックリポジトリをサンドボックスにクローンします。

**Tuist の agent-sessions API を使用する場合**、Tuist がエージェントとセッションを作成し、あなたの Tuist アカウントに接続されているプライベート GitHub リポジトリをクローンします：

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

アカウントに複数の環境がある場合は、`agent_environment_id`を渡してください。`GET /agent-sessions/{id}/events`でセッションを追跡し、`POST /agent-sessions/{id}/messages`で返信し、`POST /agent-sessions/{id}/archive`で終了できます。

リポジトリは Linux では`/workspace`、macOS では`/Users/runner/work`にチェックアウトされます。セッションのサンドボックスは、エージェントがターンを終えると一時停止し、次のメッセージで再開します。

> [!WARNING]
> 環境を所有する Claude ワークスペースでセッションを作成できるユーザーは誰でも、あなたの Tuist アカウントでセッションを実行でき、セッションメタデータを使用して macOS を要求できます。そのワークスペースへのアクセスを適切に制限してください。

## Claude Code {#claude-code}

Claude Code クラウドセッションは、開発者が[claude.ai/code](https://claude.ai/code)、Claude デスクトップおよびモバイルアプリ、`claude --cloud`から開始するものです。セッションの実行場所は環境によって選択されるため、提供したいプラットフォームごとに 1 つの環境を接続します。

### 環境を接続する {#claude-code-connect}

1. Claude 組織のオーナーは、[Cloud environments](https://claude.ai/admin-settings/cloud-environments)管理ページで**セルフホスト環境を許可**を有効にします。これには Team または Enterprise プランが必要です。Anthropic の[セルフホスト環境](https://code.claude.com/docs/en/self-hosted-environments)ガイドを参照してください。
2. 同じページで、各プラットフォームのセルフホスト環境を開発者に表示される名前（例：**Tuist Linux**および**Tuist macOS**）で作成します。各環境の`ccpool_…` ID と、一度だけ表示される環境キーをコピーします。
3. `kind`を`claude_code`に設定し、プラットフォームを指定して、各環境を Tuist アカウントに接続します：

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

   `"platform": "linux"`と他の環境の ID およびキーを使用して繰り返します。

1 分以内に、環境はセッションを受け取る準備が整います。アイドル状態のセッションはサンドボックスを 30 分間実行し続け、その後一時停止します。セッションの次のメッセージで同じサンドボックスが再開されます。`max_idle_seconds`（最大 3600）を使用して待機時間を変更できます。

### Linux または macOS を選択する {#claude-code-choose}

開発者はクラウドセッションを開始する際に環境を選び、それに伴ってプラットフォームも選択します：

- **claude.ai、デスクトップおよびモバイルアプリ：** 新しいセッションの環境ピッカーで**Tuist Linux**または**Tuist macOS**を選択します。
- **Claude Code CLI：**`claude`で`/remote-env`を実行し、名前で環境を選択します。その後、`claude --cloud "<task>"`がその環境で実行されます。単一のセッション用に 1 つを選ぶには、その ID を渡します：`claude --cloud "<task>" --environment ccpool_...`。
- **チーム全体またはリポジトリ：** Claude Code の[設定](https://code.claude.com/docs/en/settings)でデフォルト環境の ID を設定します。例えば、リポジトリの`.claude/settings.json`で設定します：

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

これらの環境でのセッションは、通常どおり組織の Claude Code 使用量を使用し、そのサンドボックスは Tuist アカウントの使用量に計上されます。
