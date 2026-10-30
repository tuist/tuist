---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · エージェントによるコーディング · 機能 · ガイド · Tuist",
  "description": "Tuist の MCP エンドポイント経由で、AI エージェントにテストの洞察などへのアクセスを提供します。"
}
---
# モデルコンテキストプロトコル

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro)は、AIエージェントが外部サービスやデータソースと対話できるようにするオープンスタンダードです。[Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/)などのアプリケーションや、[Zed](https://zed.dev)、[Cursor](https://www.cursor.com)、[Visual Studio Code](https://code.visualstudio.com)などのエディタをTuistと相互運用可能にします。

TuistはサーバーサイドのModel Context Protocolエンドポイントを`https://tuist.dev/mcp`でホストしています。クライアントをこれに接続することで、エージェントはテストインサイト、flakyテスト分析などを含むTuistプロジェクトデータにアクセスできます。ほとんどのツールは読み取り専用で、認証されたTuistプロジェクトデータにスコープされています。アカウント設定ツールは、認証済みユーザーに必要な権限がある場合、アカウントの一覧表示、組織の作成、プロジェクトの作成、既存ユーザーの組織への追加が可能です。すべてのツールは、読み取り専用かどうか、元に戻しにくい変更を引き起こす可能性があるかどうか、パブリックなインターネット状態を変更できるかどうかを示すアノテーションを公開します。アカウント設定ツールにはユーザー認証が必要です。プロジェクトトークンや通常のアカウントトークンでは利用できません。ユーザーがブラウザでクライアントを承認するか、`auth.md`登録をクレームすると、Tuistはその認証情報をModel Context Protocolエンドポイントでのみユーザーに関連付け、設定ツールが要求されたワークフローを完了できるようにします。

Tuistは[2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)を実装しています。リクエストはステートレスです。クライアントは各リクエストとともにプロトコルメタデータを送信し、初期化なしで直接ツールを呼び出すことができます。`server/discover`はサーバーの識別情報、機能、サポートされているバージョン、および手順を返します。セッション識別子や独立したイベントストリームはありません。2025-06-18または2025-03-26の初期化フローを使用するクライアントも引き続きサポートされており、それらもサーバーセッションなしで動作します。

## Model Context Protocol対スキル

Model Context Protocolツールと<.localized_link href="/guides/features/agentic-coding/skills">スキル</.localized_link>は、その機能において重複する可能性があります。現在の重複を考慮し、ワークフローごとに一つのアプローチを選択し、同じフロー内で両方を混在させるのではなく一貫して使用してください。

プラグインインストールをサポートするクライアントの場合、<.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link>を使用して両方を一緒にインストールしてください。

## 設定

クライアントのリモートModel Context Protocolサーバーとして`https://tuist.dev/mcp`を追加してください。サーバーの初期化手順とパブリックサーバーカードは、動的クライアント登録を伴うOAuth 2.0と標準的なブラウザ認証フローをインラインで説明しており、エージェントに外部の認証ドキュメントを取得したり従ったりすることを求めません。これらのサーバー全体の指示により、ワークフローガイダンスは汎用的に保たれます。ツール認証はローカルのコマンドラインツールやビルドシステム統合を認証せず、エージェントは関連するTuistツールを通じて要求された変更を検証する必要があります。ビルドシステム固有の設定と認証チェックは、統合ガイドとプロンプトに記載されています。Tuistは依然として[Open Authorization](https://oauth.net/2/)ディスカバリーメタデータと現在の[auth.md protocol](https://workos.com/auth-md)を`https://tuist.dev/auth.md`で個別に公開しています。

このエンドポイントは、古いセッションベースのライフサイクル alongside、ステートレスな`2026-07-28` Model Context Protocolリクエストライフサイクル（`server/discover`を含む）を受け入れます。既存のクライアントは現在の接続方法を继续使用できます。

Model Context Protocolイベントをサポートするクライアントは、プロジェクトイベントをサブスクライブできます。利用可能なイベントと配信要件については[Events](#events)を参照してください。

すでにリモートブラウザ認証をサポートしているクライアントは、ブラウザでの認証を続けることができます。`auth.md`をサポートするクライアントとエージェントは、匿名で登録したり、信頼されたプロバイダーのIDアサーションを提示したり、サービス認証されたメールクレームを開始したりできます。登録によりTuist署名付きのIDアサーションが返され、エージェントはこれを標準のトークンエンドポイントで1時間有効のアクセストークンと交換します。Tuistは公開署名鍵を公開し、標準的なトークン失効とプロバイダーのセキュリティイベント配信をサポートしています。

認証されていないエージェントは、Model Context Protocolエンドポイントから返される`WWW-Authenticate`ヘッダーを読み取り、保護リソースメタデータを取得し、認証サーバーメタデータを取得して、その`agent_auth.skill` URLに従う必要があります。Tuistは許可されていないレスポンスボディにも同じローカル`auth_md` URLを返し、言語モデル駆動型クライアントがネイティブクライアント統合に頼らずにフローを発見できるようにします。デプロイメントローカルドキュメントは、エンドポイント名、リクエストボディ、クレームポーリング、およびアサーション交換に関する信頼できる情報源です。

エージェントがメールクレームを開始する前に、ユーザーにTuistアカウントのメールアドレスを確認してもらう必要があります。そのアドレスをプロバイダープロフィール、Git設定、環境変数、またはセッションメタデータから推測してはいけません。

このエンドポイントは`mcp`スコープグループを使用します。匿名の事前クレーム資格情報は機能を発見し、パブリックな統合ガイダンスを読み取ることができますが、サインインしたユーザーとしては扱われません。ブラウザ承認またはクレーム後、資格情報はユーザースコープとなり、各ツールはダッシュボードと同じ認可チェックを適用します。詳細については<.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>を参照してください。

ツールは、認証済みユーザーがすでに読み取り可能なプロジェクトに解決されます。XcodeおよびGradleビルドツールは、ビルドUUIDまたはダッシュボードURLを受け入れます。UUIDは正確に1つのプロジェクトを識別する必要があります。複数のプロジェクトに表示される場合、ツールは別のプロジェクトのレポートを選択する代わりに「not found」を返します。プロジェクトスコープのダッシュボードおよびAPI読み取りは利用可能です。報告されたアクター識別子は未検証のラベルであり、資格情報や追加のアクセス権ではありません。

ビルド一覧および詳細ツールは、オプションの`tuist_version`メタデータを公開します。XcodeおよびCargoの場合は報告元のTuist CLI、Gradleの場合はTuist Gradleプラグイン、Mixの場合は`tuist_ex`ライブラリです。Xcodeは、リンクされたプロジェクト生成イベントから`tuist_generation_version`も公開しますが、これはアップロードに使用したCLIと異なる場合があります。欠測値はnullであり、サーバーや他のレポートから推論されることはありません。Bazelは既存の`bazel_version`を使用し、Onceの実行詳細は`once_version`を公開します。これらのフィールドは報告されたバージョンを示すものであり、検証済みのIDやワイヤー契約のバージョンではありません。RESTビルドエンドポイントも同じメタデータを公開します。既存の統合スキルおよびflaky-testスキルはバージョンフィールドに依存せず、ワークフローの変更は不要です。

Tuistオペレーターが顧客のアカウントを調査する際は、すべての呼び出しを記録するTuistの内部運用ツールを使用します。このエンドポイントへの直接接続では、ユーザー自身のメンバーシップを超えるアクセス権は付与されません。

<details>
<summary>Claude Code</summary>

実行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

ヘッドレスなClaude Codeクライアントがモデルに対してネイティブサーバー接続の失敗を公開しない場合、エージェントはホストされたドキュメントを検索したりプロジェクトを編集したりする前に、構成済みエンドポイントの認証されていない[Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP)レスポンスを検査する必要があります。ブラウザ認証が利用できない場合でも、このレスポンスはモデルをデプロイメントローカルの`auth.md`ドキュメントへ誘導します。

</details>


<details>
<summary>Codex</summary>

実行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

新しい`codex exec`実行を開始する前に、ブラウザでのログインを完了してください。Codexは初期化中にTuistサーバーの指示を読み取るため、Gradle最適化リクエストは自動的に認証および検証ワークフローを受け取ります。

</details>


<details>
<summary>Claude Desktop</summary>

**Settings → Connectors → Add custom connector**を開き、以下を設定します：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

プロンプトが表示されたら、ブラウザで[Open Authorization](https://oauth.net/2/)を完了してください。

</details>


<details>
<summary>Pi</summary>

PiにはModel Context Protocolクライアントが含まれていません。ソースコードとセキュリティへの影響を確認した後、サードパーティ製の[`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter)拡張機能をインストールできます：

```bash
pi install npm:pi-mcp-adapter
```

プロジェクトレベルの`.mcp.json`ファイルを追加します：

```json
{
  "mcpServers": {
    "tuist": {
      "url": "https://tuist.dev/mcp",
      "auth": false
    }
  }
}
```

`auth`を`false`に設定すると、アダプターのブラウザ認証ハンドラーがTuistの未承認レスポンスを隠すのを防ぎます。これにより、ヘッドレスエージェントは返された`auth_md` URLを読み取り、Tuistの登録、IDアサーション交換、およびクレームポーリングフローに従うことができます。交換されたアクセストークンをBearerトークンとして構成するか、エージェントが直接認証済みModel Context Protocol呼び出しを行うようにします。

ブラウザ認証を希望する場合は、`auth`を`"oauth"`に設定してください。そのフローの場合、認証が完了するまでPiの[remote procedure call mode](https://pi.dev/docs/latest/rpc)で1つのプロセスを生かしておきます：

```bash
pi --mode rpc
```

コールバック状態を所有するプロセスが終了しているため、保留中のブラウザ認証を別々の`pi --print`呼び出しに分割しないでください。

</details>


<details>
<summary>OpenCode</summary>

Tuist Model Context Protocolサーバーを`opencode.json`に追加します：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "tuist": {
      "type": "remote",
      "url": "https://tuist.dev/mcp"
    }
  }
}
```

次に、サーバーを認証します：

```bash
opencode mcp auth tuist
```

</details>


<details>
<summary>Cursor</summary>

**Cursor Settings → Tools & Integrations → Model Context Protocol Tools**を開き、以下を追加します：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

**Command Palette → MCP: Add Server**を使用し、以下の設定で[Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP)サーバーを構成します：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Agent panel → Settings → Add Custom Server**を開き、以下を設定します：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

エージェントが`auth.md`をサポートしている場合、ブラウザを開かずに匿名で開始できます。信頼できるプロバイダーIDがすでにリンクされている場合、ブラウザなしで完了することも可能です。サービス認証メール、匿名クレーム、または初回プロバイダーリンクの場合、エージェントはTuist検証リンクと6桁のコードを表示します。リンクを開き、サインインして、Tuistページでエージェントのコードを入力してください。コードをエージェントに送り返さないでください。Tuistの認証サーバーメタデータは、デプロイメント独自の`/auth.md`を直接指しており、そこには正確なリクエストおよびポーリングの形式が含まれています。

## ビルドシステム統合には2つの資格情報を使用

Model Context Protocolツールで使用される資格情報は、GradleプラグインやBazelのリモートサービスを認証しません。エージェントがGradleまたはBazelの統合を編集または検証する前に、以下を実行する必要があります：

```bash
tuist auth whoami --url https://tuist.dev
```

そのコマンドが認証されていない場合、エージェントは停止し、ユーザーに以下を実行するよう依頼する必要があります：

```bash
tuist auth login --url https://tuist.dev
```

ローカルまたはセルフホスト型デプロイメントの場合、両方のコマンドおよび`tuist.toml`内のURLを置き換えてください。ホスト名の表記はすべて同一に保ってください。例えば、`localhost`と`127.0.0.1`は別々の保存済み資格情報を使用します。


## 機能

### ツール

以下のツールは、Tuist Model Context Protocolサーバーを通じて利用可能です：

各ツールは、人間が読める説明と明示的な入出力スキーマを公開します。正常な呼び出しは、公表された出力スキーマに準拠した構造化コンテンツを返し、さらに構造化コンテンツをまだ消費できないクライアント向けに、同じ結果をテキストとしてシリアライズして返します。

`build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id`、または`cache_run_id`など、単一レコードの識別子を受け取るツールは、そのレコードのTuistダッシュボードURLも受け付けます。識別子を抽出するのではなく、ブラウザからURLを直接貼り付けてください。

#### ドキュメントおよびコミュニティ検索

この読み取り専用ツールは、ドキュメントウェブサイトと同じ検索エンジンを使用して、Tuistのドキュメント、[アプリケーションプログラミングインターフェース](https://en.wikipedia.org/wiki/API)リファレンス、GitHubリリース、コミュニティフォーラム、およびGitHubイシューを検索します。リリース結果には、製品、バージョン、公開日、プレリリースステータスが含まれます。デフォルトでは安定版リリースが検索され、`include_prereleases`を使用するとプレリリースを含めることができます。このツールは、`https://tuist.dev/mcp`にあるTuistホスト型サーバーでのみ利用可能です。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `search_tuist` | 公開されているTuistドキュメント、アプリケーションプログラミングインターフェースリファレンス、GitHubリリース、コミュニティディスカッション、およびGitHubイシューを検索します。オプションで、1つの`source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）に制限できます。 | `query` |

#### ソースに基づく回答

これらの読み取り専用ツールにより、エージェントは、ホスト型サーバーとともにデプロイされた正確な公開Tuistソースリビジョンを、現在の動作に依存する回答の信頼できる情報源として使用できます。これらは`https://tuist.dev/mcp`でのみ利用可能です。

互換性のあるクライアントは、初期化中に、インラインOAuth認証情報とともに、ツールのソースリビジョン、リンク、および結果制限に関する事実上の説明を受け取ります。これらの説明は、回答スタイルや検証ワークフローを規定するものではありません。ユーザーは、まず`ask_tuist`プロンプトを呼び出さずに直接質問を行うことができます。このプロンプトは、明示的なソースに基づくワークフローのために引き続き利用可能です。

すべての操作には、並行性、期間、トラバース、読み取りバイト数、およびレスポンスサイズに対する固定制限があります。検索および一覧結果には、`truncated`および`truncation_reason`フィールドが含まれます。結果が切り捨てられた場合は、結果を完全なものとして扱うのではなく、パス、ファイルパターン、または検索語句を狭めてください。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `search_tuist_code` | ソースファイルを検索することで、現在の動作、デフォルト、構成、機能ゲート、エラー処理、または文書化されていない詳細に関する質問に回答します。結果には、周辺の行、リビジョン固定ソースリンク、およびスキャン統計が含まれます。 | `pattern` |
| `list_tuist_files` | 関連するパスが不明な場合に、ソースサブシステムまたは近くのテストを発見します。一覧表示には、深度と結果数の上限があります。 | なし |
| `read_tuist_file` | 関連するパスを見つけた後、実装ファイル、呼び出しサイト、またはテスト内の特定の行範囲を検査します。切り捨てられたレスポンスには、継続のための`next_start_line`が提供されます。 | `path` |

#### プロジェクト

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_accounts` | 認証済みユーザーが利用可能な個人アカウントおよび組織アカウントのハンドルを一覧表示します。各アカウントがプロジェクトを作成できるかどうかも含まれます。 | なし |
| `get_organization` | 組織のメンバーディレクトリを取得します。保留中の招待には、ダッシュボードと同じ管理者権限が必要です。招待受諾トークンは決して返されません。 | `account_handle` |
| `create_organization` | 認証済みユーザーのためにTuist組織を作成します。 | `handle` |
| `create_project` | 認証済みユーザーがアクセスできるアカウントの下にTuistプロジェクトを作成します。 | `account_handle`, `project_handle` |
| `add_organization_member` | 既存のTuistユーザーを組織に追加するか、既存のメンバーの役割を更新します。`user`（デフォルト）、`admin`、または`viewer`を受け入れます。ビューアーはダッシュボードと実行を読み取ることができますが、何も変更することはできません。 | `organization_handle`, `email` |
| `invite_organization_member` | 既存のTuistユーザーに属しているかどうかにかかわらず、メールアドレスを組織に招待します。Tuistは14日後に期限切れになる受諾リンクをメールで送信します。サーバーがメールを送信できない場合、`email_sent`は`false`となり、リンクはダッシュボードからコピーする必要があります。`user`（デフォルト）、`admin`、または`viewer`を受け入れます。組織管理者権限が必要です。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 保留中の組織招待をキャンセルし、そのリンクを受諾できなくします。組織管理者権限が必要です。 | `organization_handle`, `email` |
| `list_projects` | 認証済みユーザーがアクセスできるすべてのプロジェクトを一覧表示します。 | なし |
| `get_project` | プロジェクトの構成と接続されたリポジトリURLを取得します。 | `account_handle`, `project_handle` |
| `connect_project_repository` | プロジェクトを、アカウントのGitHub AppインストールがアクセスできるGitHubリポジトリにリンクします。プロジェクトはリポジトリのデフォルトブランチを採用します。プロジェクト管理者権限が必要です。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | プロジェクトのGitHubリポジトリへのリンクを削除します。プロジェクト管理者権限が必要です。 | `account_handle`, `project_handle` |

#### アカウントトークン

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_account_tokens` | トークンの値を公開せずに、アカウントトークンのメタデータを一覧表示します。 | `account_handle` |
| `get_account_token` | トークンの値を公開せずに、アカウントトークンのメタデータを取得します。 | `account_handle`, `token_id` |
| `list_project_tokens` | トークンの値を公開せずに、プロジェクトトークンのメタデータを一覧表示します。 | `account_handle`, `project_handle` |

#### CIランナー

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_runner_jobs` | アカウントのCIランナージョブを一覧表示します。 | `account_handle` |
| `get_runner_job` | CIランナージョブを取得します。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | CIランナージョブに記録されたステップを一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | CIランナージョブに記録されたマシンメトリクスを一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | CIランナージョブのキャプチャされたログ行を最大500件まで一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | アカウントのCIワークフロー集計を一覧表示します。 | `account_handle` |
| `list_runner_profiles` | アカウントのCIランナープロファイルと、各プロファイルの`runs-on`ラベルを一覧表示します。 | `account_handle` |
| `get_runner_catalog` | ランナープロファイルが使用できるマシンシェイプとXcodeバージョンを一覧表示します。 | `account_handle` |
| `create_runner_profile` | プラットフォーム、マシンシェイプ、およびmacOSではXcodeバージョンを指定してランナープロファイルを作成します。オプションで、キャッシュボリュームを保存するブランチを設定できます。アカウント管理権限または`account:runners:write`スコープが必要です。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | ランナープロファイルのマシンシェイプ、Xcodeバージョン、またはカスタムキャッシュボリュームの変更を保存するブランチを変更します。省略されたフィールドは既存の値を維持します。アカウント管理権限または`account:runners:write`スコープが必要です。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | ユーザーの確認後にランナープロファイルを削除します。デフォルトプロファイルは削除できません。アカウント管理権限または`account:runners:write`スコープが必要です。 | `account_handle`, `profile_name` |

ランナーボリュームツールは、Volumesダッシュボードと同じデータを公開します。読み取りツールにはランナーへのアクセス権が必要で、クリア操作にはアカウント管理権限または`account:runners:write`スコープ、およびユーザーの確認が必要です。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_runner_volumes` | 名前とリポジトリでフィルタリングし、ボリュームを並べ替えてページネーションします。 | `account_handle` |
| `get_runner_volume` | リポジトリ、プラットフォーム、容量、使用済みスペース、最終使用日時。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | ページネーションされたジョブおよびワークフロー参照、キャッシュステータス、ヒット結果、マウント時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | ジョブによってマウントされたボリューム。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | ストレージ時系列、ジョブ実行、ヒット率、トレンド。オプションの`volume_id`、`start`、`end`（ISO 8601）。デフォルトは7日間、最大90日間。 | `account_handle` |
| `clear_runner_volume` | 保存された内容をクリアします。実行中のジョブはプライベートコピーを保持しますが、保存はできません。後続のジョブは空の状態から開始されます。 | `account_handle`, `volume_id` |

リストは`page`および`page_size`（最大100）を受け入れます。ボリュームインベントリは、`name`および`repository`（完全一致、AND条件で結合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）、`sort_order`（`asc`、`desc`）も受け入れます。不明な測定値とヒット結果は`null`のままです。キャッシュステータスは、ボリュームの変更が保存されたかどうかを示し、ジョブの成功を示すものではありません。

#### Webhook

Webhookツールは、ダッシュボードと同じ管理者専用権限を使用します。配信試行にはエンドポイントに記録されたリクエストおよびレスポンスデータが含まれますが、エンドポイントの署名シークレットは含まれません。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_webhook_endpoints` | アカウントのWebhookエンドポイントを一覧表示します。 | `account_handle` |
| `get_webhook_endpoint` | Webhookエンドポイントを取得します。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | エンドポイントの配信試行を一覧表示します。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 配信試行を取得します。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcodeビルド

Xcode、Gradle、Bazel、Mix、Cargoのビルド詳細ツールは、既存の`custom_metadata: {tags, values}`構造を公開し、報告されたインフラストラクチャ観測値を含みます。値は文字列のまま保持され、不明なキーも保存されます。例えば、`tuist.cpu.available_processors`はランタイムで利用可能な論理プロセッサ数を示し、`tuist.gradle.max_workers`はGradleのワーカ制限、`tuist.jvm.max_heap_bytes`はJVMヒープ制限（ホストメモリではありません）を示します。これらは信頼されていないクライアント観測値であり、検証済みのランナーIDではありません。欠落している観測値は欠落したままとなり、インポートされたログや古いクライアントにはインフラストラクチャメタデータが含まれていない場合があります。Onceメタデータは、クライアントとプロトコルの協調更新を待っています。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_xcode_builds` | プロジェクトのXcodeビルド実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 特定のXcodeビルド実行に関する詳細情報を取得します。これには、生の`.xcactivitylog`を含むアーカイブの一時ダウンロードURLが含まれます。 | `build_run_id` |
| `list_xcode_build_targets` | 特定のXcodeビルド実行のビルドターゲットを一覧表示します。 | `build_run_id` |
| `list_xcode_build_files` | 特定のXcodeビルド実行のコンパイル済みファイルを一覧表示します。 | `build_run_id` |
| `list_xcode_build_steps` | ログテキストを除き、タイミングと結果付きで記録されたビルドステップを一覧表示します。 | `build_run_id` |
| `get_xcode_build_step` | ログと切り捨てフラグを含む、記録されたビルドステップを1つ取得します。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 特定のビルド実行のビルド問題（警告とエラー）を一覧表示します。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 特定のXcodeビルド実行のキャッシュ可能タスク（キャッシュヒット/ミス）を一覧表示します。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 特定のXcodeビルド実行の[コンテンツアドレサブルストレージ](https://en.wikipedia.org/wiki/Content-addressable_storage)出力を一覧表示します。 | `build_run_id` |

`list_xcode_build_steps`はデフォルトで20ステップのページを返します（`page_size`経由で最大100）。ナビゲーションには`page`と`pagination_metadata`を使用します。`search`を使用してタイトル、プロジェクト、またはターゲットを一致させるか、正確な`project`、`target`、`category`（例：`swiftCompilation`）、および`status`（`success`または`failure`）でフィルタリングします。`duration_ms`で並べ替えると最も遅いものが先頭に表示され（デフォルト）、`start_ms`で並べ替えると時系列順になります。ステップIDは同順位を解消し、64ビット精度を完全に保持するために10進数文字列として返されます。IDはビルドごとにスコープされており、ビルド間で一致させてはいけません。

オプションの`start_ms`と`end_ms`は、ビルド開始からのミリ秒単位の時間範囲と重なるステップを選択します（終了時間は除外されます）。どちらのツールも、ビルドUUIDまたはダッシュボードURLを`build_run_id`として受け入れます。返されたステップ`id`を変更せずに`step_id`として渡し、そのログを取得します。ログはステップあたり最大64 KiBまで保持され、`log_truncated`によって省略された出力が示されます。

Xcodeビルドが処理されると、デフォルトでステップが収集されます。記録されたステップデータは90日間保持されます。リストレスポンスには`availability`が含まれます。記録されたステップが存在する場合は`available`（フィルタに一致するものがなくても）、ビルドがまだ処理中でステップがない場合は`processing`、ステップが記録されていないか期限切れの場合は`unavailable`となります。

同じ操作はHTTP APIの`GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps`および`GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}`で利用可能で、同じフィルタとページネーションをサポートします。どちらもビルドのプロジェクトへの読み取りアクセス権が必要です。

#### Gradleビルド

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 完全な認証、プロジェクト設定、Gradleプラグイン、キャッシュポリシー、および2回ビルドによる検証ワークフローを返します。エージェントは、既存のAndroidまたはGradleプロジェクトを編集する前にこれを呼び出す必要があります。 | なし |
| `list_gradle_builds` | プロジェクトのGradleビルド実行をカスタムメタデータを含めて一覧表示します。オプションの`tag`パラメータを使用してカスタムタグでフィルタリングします。 | `account_handle`, `project_handle` |
| `get_gradle_build` | ビルドメタデータとタスク/キャッシュのカウントを取得します。 | `build_run_id` |
| `list_gradle_build_tasks` | タスクの結果、複合ビルドID、キャッシュ可能性、および増分ステータスを一覧表示します。 | `build_run_id` |
| `list_gradle_build_steps` | 検索、メタデータ、および重複する時間フィルタを使用して、時間計測されたタスク、構成、および変換を一覧表示します。 | `build_run_id` |
| `get_gradle_build_step` | 不透明なIDによって記録されたステップメタデータを検査します。ステップごとのログは利用できません。 | `build_run_id`, `step_id` |

GradleおよびBazelのステップリストはデフォルトで20件の結果を返し（最大100件）、`search`、正確な`project`、`target`、`category`、`status`、重複する`start_ms` / `end_ms`フィルタ（終了は除外）、および`duration_ms`または`start_ms`での並べ替えをサポートします。返されたIDは変更せずに渡してください。これらはビルドごとにスコープされています。リストは`time_origin`と`coverage`を公開します。古いGradleレポートは、ビルド開始がアップロードされていないため`first_recorded_timestamp`を使用します。Bazelプロファイルは、`trace_profile`カバレッジと時間原点としての`profile_start`を使用して、記録されたすべての間隔を公開します。古いビルドは保持されたBEPサマリーにフォールバックします。ソースレコードは90日後に期限切れになります。Bazelの詳細には、公開された場合にサニタイズされたアクションログが含まれます。Gradleの詳細`log`はnullです。`compare_builds`プロンプトはこのカバレッジを使用して、完全なBazelトレースと保持されたサマリーを区別し、より広範な呼び出し出力を確認する前に、エージェントをアクションの結果とログのためのステップ詳細へ誘導します。

保持されたサマリーから返されたBazelステップIDは、リスト表示とステップ取得の間に完全なプロファイルが到着した場合でも読み取り可能です。ステップデータが期限切れになったインデックス付きプロファイルは、利用不可と報告されます。Gradleステップリストには、ゼロ時間のキャッシュ済みおよびスキップされた操作が含まれます。

#### Bazel呼び出し

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 認証、プロジェクト設定、Bazel構成、および検証ワークフローを返します。 | なし |
| `list_bazel_invocations` | プロジェクトの完了した[Bazel Build Event Protocol](https://bazel.build/remote/bep)呼び出しを、ビルドメトリクス、限定された実行タイムライン、クリティカルパス診断、および相関するリモートキャッシュ合計とともに一覧表示します。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | ビルドメトリクス、限定された実行タイムライン、クリティカルパス診断、および相関するリモートキャッシュ合計を含む、完了したBazel呼び出しを1つ取得します。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | フィルタと明示的なカバレッジを使用して、記録されたBazelプロファイル間隔を一覧表示します。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 記録されたBazelステップと、公開されたアクション結果およびサニタイズされたログを検査します。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | Bazel呼び出しに対してキャプチャされたサニタイズされたテストログを、実行順に一覧表示します。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bazel呼び出しに対してキャプチャされたサニタイズされたテストログを1つ取得します。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 操作、エンドポイント、観測時刻を含む生のBazelリモートキャッシュ観測を一覧表示します。呼び出し、結果、または操作に絞り込むこともできます。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 生のBazelリモートキャッシュ観測を1つ取得します。 | `account_handle`, `project_handle`, `cache_event_id` |

#### Cargoビルド

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_cargo_builds` | プロジェクトのCargoビルドを新しい順に一覧表示します。`git_branch`、`status`、`is_ci`、または`command`でフィルタリングできます。個々のテスト実行は、このビルド一覧ではなくテストツールから利用できます。 | `account_handle`, `project_handle` |
| `get_cargo_build` | ヒット、タスクミス、ヒットレートなど、ビルドメタデータと集計キャッシュカウンターを取得します。 | `account_handle`, `project_handle`, `build_id` |

#### Mixビルド

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_mix_builds` | プロジェクトのMix（Elixir）コンパイルビルドを新しい順に一覧表示し、カスタムメタデータを含めます。`git_branch`、`status`、`is_ci`、または`mix_env`でフィルタリングできます。 | `account_handle`, `project_handle` |
| `get_mix_build` | ビルドメタデータ、診断カウント、および依存関係キャッシュのサマリーを取得します。 | `account_handle`, `project_handle`, `build_id` |

#### Once実行

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_once_runs` | プロジェクトのOnce実行を新しい順に一覧表示します。`kind`（`build`、`test`、または`generic`）、`status`、`is_ci`、または`git_branch`でフィルタリングできます。完了していない実行のステータスは`in_progress`です。 | `account_handle`, `project_handle` |
| `get_once_run` | アクション合計、キャッシュサマリー、およびテスト実行の場合はテスト合計を含む実行を取得します。 | `account_handle`, `project_handle`, `run_id` |

Cargoビルド、Mixビルド、およびOnce実行のIDはプロジェクト内で一意です。同じ読み取りはHTTP APIの`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds`、および`.../once/runs`で利用でき、それぞれに1つのID用の詳細エンドポイントがあります。

#### タスク、アクション、モジュール、ファイル

これらのプロジェクトスコープのツールは、実行間での永続的なビルド識別子を検査します。`list_build_entities`から開始し、返された安定した`id`と同じ`kind`を`get_build_entity`または`list_build_entity_history`に渡し、`account_handle`と`project_handle`も一緒に指定します。ビルドまたは呼び出し識別子は必要ありません。

| ツール | 説明 | 必須パラメーター |
| --- | --- | --- |
| `list_build_entities` | プロジェクトのビルド全体で確認される、ある種類のタスク、モジュール、アクション、またはファイルを一覧表示します。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 選択した期間のネイティブ識別子と分析情報を含むビルドエンティティを1つ取得します。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | あるビルドエンティティの記録された実行、コンパイル、またはキャッシュイベントを新しい順に一覧表示します。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | ツールチェーン | 履歴リスト |
| --- | --- | --- |
| `bazel_actions` | Bazelアクション | BEP報告されたアクション実行 |
| `gradle_tasks` | Gradleタスク | タスク実行 |
| `xcode_modules` | Xcodeモジュール | コンパイルとモジュールキャッシュイベント |
| `once_actions` | Onceアクション | 実行 |
| `mix_files` | Mixコンパイル済みファイル | コンパイル |
| `mix_modules` | Mixコンパイル済みモジュール | コンパイル |

これらのツールは段階的にロールアウトされており、有効化されているプロジェクトのデータのみを返します。それ以外のプロジェクトでは、空の結果ではなくエラーを返します。種類は、そのビルドツールチェーンを使用しているプロジェクトでのみ利用可能です。ツールは範囲指定された`start_at`/`end_at`フィルター、`environment`（`any`、`ci`、または`local`）、および完全一致の`branch`を受け入れます。`list_build_entities`は`q`を受け付けます。`list_build_entity_history`は不透明な`after`/`before`カーソルをサポートします。不明なタイミングまたはキャッシュ観測は、ゼロやミスとして扱われるのではなく、利用不可のままとなります。履歴は、既存の実行ツールを使用したドリルダウンのために、記録された親およびネイティブ実行を参照します。

`get_build_entity`メトリクスには、タイミングが記録された観測数である`duration_samples`が含まれます。実際のゼロ持続時間はカウントされますが、タイミングが欠落している場合はカウントされません。この数は観測数より少なくなる可能性があります。利用できない持続時間統計はnullのままです。

Xcodeモジュールの持続時間は、ビルドログで測定されたターゲットコンパイルから取得されます。モジュールキャッシュの解決およびコンパイル作業のないターゲットは、持続時間サンプルに貢献しません。コンパイル観測はXcodeビルドを参照し、キャッシュイベントは生成またはキャッシュコマンドを参照します。

Bazelアクションは、ターゲットラベル、ニーモニック、および構成された主要出力によって識別され、入力依存のキャッシュダイジェストに頼ることなく、個別のアクションと構成を区別します。履歴は、キャッシュルックアップやトレースプロファイルフェーズではなく、BEP報告された実行を記録します。完全な実行カバレッジには`--build_event_publish_all_actions`が必要です。アーティファクト配信はベストエフォートであるため、観測の欠落は作業が行われなかった証拠ではありません。安定した識別子または実行開始情報を持たない古いKuraペイロードは受け入れられますが、インデックスされません。終了時間の測定値がない場合は利用不可のままとなり、実際のゼロ持続時間はカウントされます。

Mixモジュールの持続時間は、含まれるファイルのコンパイルを測定するものであり、独立して測定されたモジュール作業ではありません。Onceアクションは、クライアントがターゲットマッピングを報告した際に宣言されたターゲット/ケイパビリティ/インデックススロットを使用します。診断ラベルだけでは安定した識別子になりません。既存のクライアントおよび実行レベルのツールは変更なくサポートされます。

分析読み取りにはメモリと実行時間の上限があります。クエリがこれらの制限を超えると、ツールは空の結果を捏造する代わりにエラーを返します。

新しい観測はデプロイ後にインデックスされます。この機能は既存の実行テレメトリをバックフィルしません。識別子メタデータは、<.localized_link href="/guides/server/data-retention">データ保持ポリシー</.localized_link>の下で個々の観測よりも長く存続します。

#### テスト

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_test_runs` | プロジェクトのテスト実行を一覧表示します。`query`フィールドは`git_branch`、`scheme`、および`status`です。`field:"value"`は完全一致、`field~"value"`は大文字小文字を区別しない部分文字列一致、先頭の`-`はいずれかの演算子を否定します。例えば、`-git_branch~"gh-readonly-queue"`はマージキューブランチを除外します。空白で区切られたクエリフィルターと明示的な引数はANDセマンティクスで結合されます。 | `account_handle`, `project_handle` |
| `get_test_run` | 結果バンドル（`.xcresult`）およびセッションアーカイブの一時的なダウンロードURLを含む、テスト実行の詳細メトリクスを取得します。 | `test_run_id` |
| `list_test_module_runs` | 特定のテスト実行のテストモジュール実行を一覧表示します。 | `test_run_id` |
| `list_test_suite_runs` | 特定のテスト実行のテストスイート実行を一覧表示します。オプションでモジュールによるフィルタリングが可能です。 | `test_run_id` |
| `list_test_cases` | プロジェクトのテストケースを一覧表示します（`flaky`などのフィルターをサポート）。 | `account_handle`, `project_handle` |
| `get_test_case` | 信頼性レート、不安定性レート、および実行回数を含む、テストケースの詳細メトリクスを取得します。 | `test_case_id`または`identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | テストケース実行を一覧表示します。オプションでテストケースまたはテスト実行によるフィルタリングが可能です。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 特定のテストケース実行の失敗詳細および繰り返しを取得します。 | `test_case_run_id` |
| `list_test_case_run_attachments` | テストケース実行の添付ファイルを一覧表示します。各添付ファイルには一時的なダウンロードURLが含まれます。 | `test_case_run_id` |
| `list_test_case_events` | ミュートやスキップなど、テストケースの状態変化を一覧表示します。 | `test_case_id` |
| `update_test_case` | テストケースの状態または不安定分類を更新します。変更により、外部サービスを含む構成済みのWebhookエンドポイントにイベントがディスパッチされる場合があります。 | `test_case_id`または`identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | テスト実行の選択的テストターゲット結果を一覧表示します。 | `test_run_id` |
| `get_coverage` | コミットまたはブランチの最新完全コミットにおける、プロジェクトとそのターゲットのコードカバレッジを取得します。`git_commit_sha`または`branch`がない場合、デフォルトブランチを読み取ります。 | `account_handle`, `project_handle` |
| `list_coverage_files` | コミットまたはブランチの最新完全コミットにおいて、コミットのコードカバレッジが測定したファイルとその行カバレッジを一覧表示します。`search`、並べ替え、およびページネーションをサポートします。 | `account_handle`, `project_handle` |
| `get_coverage_file` | コミットまたはブランチの最新完全コミットにおける、ファイルのコードカバレッジとその関数を取得します。各行の実行回数を取得するには`include_lines`を設定します。 | `account_handle`, `project_handle`, `path` |

コードカバレッジツールは、コードカバレッジが有効になっているアカウントで利用できます。

#### バンドル

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_bundles` | プロジェクトのバンドル（アプリバイナリ）を一覧表示します。 | `account_handle`, `project_handle` |
| `get_bundle` | 特定のバンドルに関する詳細情報を取得します。 | `bundle_id` |
| `get_bundle_artifact_tree` | パスで並べ替えられたフラットリストとして、バンドルの完全なアーティファクトツリーを取得します。 | `bundle_id` |

#### ジェネレーション

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_generations` | プロジェクトのジェネレーション実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_generation` | 特定のジェネレーション実行に関する詳細情報を取得します。 | `generation_id` |

#### キャッシュ実行

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_cache_runs` | プロジェクトのキャッシュ実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_cache_run` | 特定のキャッシュ実行に関する詳細情報を取得します。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | ジェネレーションまたはキャッシュ実行のモジュールキャッシュターゲットを一覧表示し、追加のハッシュ入力を含む、ターゲットごとのキャッシュヒット/ミスステータスと診断コンポーネントハッシュを表示します。 | `run_id` |

#### プレビュー

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_previews` | プロジェクトの共有可能なアプリプレビューを一覧表示します。 | `account_handle`, `project_handle` |
| `get_preview` | プレビューとそのビルドの一時的なダウンロードURLを取得します。 | `preview_id` |
| `get_latest_preview` | 実行中のアプリバイナリの最新プレビューを検索します。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### オートメーション

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_automation_alerts` | プロジェクトのオートメーションアラートを一覧表示します。 | `account_handle`, `project_handle` |
| `get_automation_alert` | オートメーションアラートを取得します。 | `alert_id` |
| `list_automation_alert_revisions` | オートメーションアラートのリビジョン履歴を一覧表示します。アクション認証情報は伏字処理されます。 | `alert_id` |
| `list_project_notification_alerts` | プロジェクト通知アラートルールを一覧表示します。ダッシュボード設定ページと同じ管理者権限が必要です。Webhookアドレスは伏字処理されます。 | `account_handle`, `project_handle` |

### イベント

ステートレスな`2026-07-28` Model Context Protocolライフサイクルを使用するクライアントは、`events/list`を呼び出してイベントとそのペイロードスキーマを発見できます：

| イベント | 送信タイミング | サブスクリプションフィルター |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | テストケースが不安定でない状態から不安定な状態に変更されます。 | `account_handle`, `project_handle` |
| `build.failed` | ローカルまたは継続的インテグレーションのXcode、Gradle、またはBazelビルドが失敗して完了します。 | `account_handle`, `project_handle` |
| `test_run.failed` | ローカルまたは継続的インテグレーションのテスト実行が失敗して完了します。マージされたシャーディング実行または放棄された実行も含みます。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuistランナーのジョブが失敗して完了します。 | `account_handle` |

サブスクライブするには、クライアントはイベント名、上記の`arguments`にリストされているハンドル、および`https://`コールバックURLと`whsec_`署名シークレットを含む`webhook`配信を使用して`events/subscribe`を呼び出します。プロジェクトイベントにはアカウントメンバーシップと対応するテストまたはビルドデータへの読み取りアクセスが必要です。ランナーのジョブイベントにはアカウントメンバーシップとランナーの読み取りアクセスが必要です。[`auth.md`](https://workos.com/auth-md)アクセストークン、アカウントトークン、およびブラウザ承認グラントはサブスクリプションを作成できます。関連する認証情報がアクティブでなくなると、配信は停止します。各ユーザーは最大25件のアクティブなサブスクリプションを保持できます。Tuistはサブスクリプションを保存する前に、コールバックに検証チャレンジを送信します。コールバックは同じ`challenge`値を含むオブジェクトを返す必要があります。サブスクリプションのデフォルト有効期限は7日で、再度サブスクライブすることで更新でき、ユーザーのアクセスまたは認証情報が削除されると配信を停止します。オプションの`ttlMs`は1時間から30日の間で制限されます。Tuistはタイムアウトしたコールバックを再試行し、5分間にわたる少なくとも3回連続のタイムアウト後にサブスクリプションを解除します。コールバックを復旧した後に再度サブスクライブしてください。

イベントが発生すると、Tuistはそのリソース識別子とダッシュボードURLをコールバックに送信します。ビルドおよびテスト実行の失敗には`is_ci`と`git_branch`も含まれるため、クライアントはローカルの失敗を無視したり、ブランチでフィルタリングしたりできます。ビルドイベントには`build_system`が含まれます。ランナーのジョブイベントには`workflow_job_id`と`workflow_run_id`の両方が含まれます。リクエストにはサブスクリプション識別子と[Standard Webhooks](https://www.standardwebhooks.com/)署名ヘッダーが含まれており、クライアントは送信元を検証できます。Tuistは配信失敗を再試行するため、クライアントは安定した`eventId`を使用して重複を除外する必要があります。ペイロードにはテスト名、ログ、および失敗メッセージは含まれません。クライアントは上記のツールを通じてこれらの詳細を取得し、チームに通知するかデバッグを開始するかを決定できます。クライアントは`events/unsubscribe`を使用して配信を停止できます。

### プロンプト

| プロンプト | 説明 |
|--------|-------------|
| `fix_flaky_test` | 失敗パターンを分析し、根本原因を特定して、対象を絞った修正を適用することで、不安定なテストの修正をガイドします。 |
| `compare_builds` | 2つのビルド実行を比較して、パフォーマンスの劣化、キャッシュの変更、およびビルドの問題を特定する手順をガイドします。XcodeプロジェクトとGradleプロジェクトの両方で動作します。 |
| `compare_test_runs` | 2つのテスト実行を比較して、回帰、新しい失敗、および不安定なテストを特定する手順をガイドします。 |
| `compare_bundles` | 2つのバンドルを比較して、アーティファクトツリー全体でのサイズ変更を特定する手順をガイドします。 |
| `compare_test_case` | 2つのブランチまたは期間にわたるテストケースの動作を比較する手順をガイドします。 |
| `compare_generations` | 2つの生成実行を比較して、パフォーマンスの劣化とモジュールキャッシュの変更を特定する手順をガイドします。 |
| `compare_cache_runs` | 2つのキャッシュ実行を比較して、キャッシュの有効性の変化とターゲットレベルの回帰を特定する手順をガイドします。 |
| `integrate_gradle_project` | 既存のGradleプロジェクトにTuistを統合する手順をガイドします。個別のツールとGradleの認証、アカウントの検出、プロジェクトの作成、リモートキャッシュポリシー、ビルドインサイト、および読み戻し検証が含まれます。 |
| `integrate_bazel_project` | Bazelプロジェクトの作成または選択、コマンドラインの認証、リモートキャッシュとビルドインサイトの構成、およびTuistビルドデータによる統合の検証を行う手順をガイドします。 |
| `integrate_xcode_project` | 既存のXcodeプロジェクトにTuistを統合する手順をガイドします。Xcodeキャッシュ、ビルドインサイト、テストインサイト、およびテストシャーディングをサポートします。 |
| `ask_tuist` | 公開資料をコンテキストとして使用し、焦点を当てた実装とテスト証拠を現在の動作の信頼できる情報源として、Tuistに関する質問に回答します。`question`が必要であり、リビジョン固定の証拠を引用します。 |

プロジェクトデータのプ​​ロンプトは、調査を特定のプロジェクトに限定するために`account_handle`と`project_handle`を受け入れます。比較プロンプトは、比較する2つの項目（ID、ダッシュボードURL、またはブランチ名で指定）を指定するための`base`引数と`head`引数も受け入れます。`ask_tuist`はプロジェクトパラメータの代わりに`question`を受け入れます。`integrate_gradle_project`は、適用するGradle統合のカンマ区切りリストである`features`も受け入れます：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests`、および`test_sharding`。`integrate_bazel_project`は、セルフホスト型またはローカルインストール用のオプションの`server_url`を受け入れます。`integrate_xcode_project`は、`xcode_cache`、`build_insights`、`test_insights`、および`test_sharding`を含む`features`を受け入れます。

#### Gradle統合プロンプトの機能

`integrate_gradle_project`プロンプトと`get_gradle_integration_guide`ツールは、完全なセットアップワークフローを文書化しています。このツールはサーバーの初期化指示でも参照されており、プロンプトを列挙しないエージェントでも検出可能になります。

| 機能 | エージェントが構成する内容 |
|---------|---------------------------|
| `remote_cache` | Gradleのビルドキャッシュを有効にし、Tuistのリモートキャッシュアップロードポリシーを構成し、ローカルでの読み取り専用使用を持つ継続的インテグレーションランナーからのみアップロードすることを推奨します。 |
| `build_insights` | Tuist Gradleプラグインを適用し、必要に応じてビルド分析のアップロード動作を構成します。 |
| `test_insights` | Tuist Gradleプラグインを適用し、Gradleの`Test`タスクの結果が自動的にアップロードされるようにします。 |
| `flaky_tests` | 不安定なテストの検出、オプションのGradle Test Retryプラグインの使用、およびテスト検疫の構成のためのセットアップをガイドします。 |
| `test_sharding` | `tuistPrepareTestShards`、シャードマトリックスの生成、および`TUIST_SHARD_INDEX`に基づくテスト実行のための継続的インテグレーションワークフローを追加します。 |

`features`が省略されている場合、プロンプトはエージェントに、ユーザーが希望する統合を明確にするか、Gradleプロジェクトを編集する前にリクエストから最小限の有用なセットを推測するように求めます。

#### Xcode統合プロンプトの機能

`integrate_xcode_project`プロンプトは、TuistがサポートするすべてのXcode統合を文書化しています：

| 機能 | エージェントが構成する内容 |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`、生成されたプロジェクトのキャッシュ設定、手動のXcodeキャッシュビルド設定、および継続的インテグレーションランナーに限定されたアップロードポリシーを構成します。 |
| `build_insights` | `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath`、および`tuist setup insights`を通じたオプションのマシンメトリクスを構成します。 |
| `test_insights` | `tuist inspect test`、スキームテストのポストアクション、および継続的インテグレーションのテスト実行用の結果バンドル生成を構成します。 |
| `test_sharding` | `TUIST_SHARD_INDEX`を使用したXcodeまたは生成されたプロジェクトのシャード計画およびシャード実行ワークフローを追加します。 |

`features`が省略されている場合、プロンプトはエージェントに、ユーザーが希望する統合を明確にするか、Xcodeプロジェクトを編集する前にリクエストから最小限の有用なセットを推測するように求めます。
