---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · エージェントによるコーディング · 機能 · ガイド · Tuist",
  "description": "TuistのMCPエンドポイントを通じて、AIエージェントにテストインサイトなどへのアクセスを提供します。"
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro)は、人工知能エージェントが外部サービスやデータソースと対話できるようにするオープンスタンダードです。[Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/)などのアプリケーションや、[Zed](https://zed.dev)、[Cursor](https://www.cursor.com)、[Visual Studio Code](https://code.visualstudio.com)などのエディタをTuistと相互運用可能にします。

Tuistは`https://tuist.dev/mcp`でサーバーサイドのModel Context Protocolエンドポイントをホストしています。クライアントをこれに接続することで、エージェントはテストインサイト、flaky test分析などを含むTuistプロジェクトデータにアクセスできます。ほとんどのツールは読み取り専用で、認証されたTuistプロジェクトデータにスコープされています。アカウント設定ツールは、認証済みユーザーに必要な権限がある場合、アカウントの一覧表示、組織の作成、プロジェクトの作成、既存ユーザーの組織への追加を行えます。各ツールは、読み取り専用かどうか、元に戻すのが困難な変更を引き起こす可能性があるかどうか、公開インターネットの状態を変更できるかどうかを示すアノテーションを広告します。アカウント設定ツールにはユーザー認証が必要です。プロジェクトトークンや通常のアカウントトークンでは利用できません。ユーザーがブラウザでクライアントを承認するか、`auth.md`登録を要求すると、Tuistはその資格情報をModel Context Protocolエンドポイント上でのみユーザーに関連付け、設定ツールが要求されたワークフローを完了できるようにします。

Tuistは[2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)を実装しています。リクエストはステートレスです。クライアントは各リクエストでプロトコルメタデータを送信し、初期化なしでツールを直接呼び出すことができます。`server/discover`はサーバーの識別情報、機能、サポートされているバージョン、および手順を返します。セッション識別子や独立したイベントストリームはありません。2025-06-18または2025-03-26の初期化フローを使用するクライアントも引き続きサポートされており、それらもサーバーセッションなしで動作します。

## Model Context Protocolとskillsの比較

Model Context Protocolツールと<.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link>は、その機能において重複する可能性があります。現在の両者の重複を考慮し、同じフロー内で両方を混在させるのではなく、ワークフローごとに1つのアプローチを選択し、一貫して使用してください。

プラグインインストールをサポートするクライアントの場合、<.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link>を使用して両方を一緒にインストールしてください。

## 設定

クライアントのリモートModel Context Protocolサーバーとして`https://tuist.dev/mcp`を追加してください。サーバーの初期化手順と公開サーバーカードは、エージェントに外部の認証ドキュメントを取得またはフォローさせることなく、動的クライアント登録によるOAuth 2.0と標準的なブラウザ認可フローをインラインで説明しています。これらのサーバー全体の指示により、ワークフローガイダンスは一般的に保たれます。ツール認証はローカルコマンドラインツールやビルドシステム統合を認証せず、エージェントは関連するTuistツールを通じて要求された変更を確認する必要があります。ビルドシステム固有の設定と認証チェックは、統合ガイドとプロンプトに記載されています。Tuistは依然として[Open Authorization](https://oauth.net/2/)ディスカバリーメタデータと現在の[auth.md protocol](https://workos.com/auth-md)を`https://tuist.dev/auth.md`で個別に広告しています。

組織の1つがシングルサインオンを強制している場合、ブラウザでクライアントを承認するには、その組織を通じてサインインしたセッションが必要であり、必要に応じてTuistはまずプロバイダーにリダイレクトします。<.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">single sign-on</.localized_link>を参照してください。

このエンドポイントは、古いセッションベースのライフサイクルに加えて、ステートレスな`2026-07-28` Model Context Protocolリクエストライフサイクル（`server/discover`を含む）を受け入れます。既存のクライアントは現在の接続方法を继续使用できます。

Model Context Protocolイベントをサポートするクライアントは、プロジェクトイベントをサブスクライブできます。利用可能なイベントと配信要件については[Events](#events)を参照してください。

すでにリモートブラウザ認証をサポートしているクライアントは、ブラウザでの認証を続けることができます。`auth.md`をサポートするクライアントとエージェントは、匿名で登録したり、信頼されたプロバイダーのIDアサーションを提示したり、サービス認証されたメールクレームを開始したりできます。登録によりTuist署名付きのIDアサーションが返され、エージェントはこれを標準のトークンエンドポイントで1時間のアクセストークンと交換します。Tuistは公開署名鍵を発行し、標準的なトークン失効とプロバイダーのセキュリティイベント配信をサポートしています。

認証されていないエージェントは、Model Context Protocolエンドポイントから返される`WWW-Authenticate`ヘッダーを読み取り、保護リソースメタデータを取得し、認証サーバーメタデータを取得して、その`agent_auth.skill` URLに従う必要があります。Tuistはまた、言語モデル駆動型クライアントがネイティブクライアント統合に頼らずにフローを発見できるように、不正なレスポンスボディで同じローカル`auth_md` URLを返します。デプロイメントローカルドキュメントは、エンドポイント名、リクエストボディ、クレームポーリング、およびアサーション交換に関する信頼できる情報源です。

エージェントがメールクレームを開始する前に、ユーザーにTuistアカウントのメールアドレスを確認してもらう必要があります。そのアドレスをプロバイダープロファイル、Git設定、環境変数、またはセッションメタデータから推測してはいけません。

エンドポイントは`mcp`スコープグループを使用します。匿名の事前クレーム資格情報は機能を発見し、公開統合ガイダンスを読み取ることができますが、サインインしたユーザーとしては扱われません。ブラウザ認証またはクレーム後、資格情報はユーザースコープとなり、各ツールはダッシュボードと同じ認可チェックを適用します。詳細については<.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>を参照してください。

ツールは、認証済みユーザーがすでに読み取り可能なプロジェクトに解決されます。XcodeおよびGradleビルドツールは、ビルドUUIDまたはダッシュボードURLを受け入れます。UUIDは正確に1つのプロジェクトを識別する必要があります。複数のプロジェクトに表示される場合、ツールは別のプロジェクトのレポートを選択する代わりに「見つかりません」を返します。プロジェクトスコープのダッシュボードおよびAPI読み取りは引き続き利用可能です。報告されたアクター識別子は未検証のラベルであり、資格情報や追加のアクセス権ではありません。

ビルド一覧および詳細ツールは、オプションの`tuist_version`メタデータを公開します。XcodeおよびCargoの場合は報告元Tuist CLI、Gradleの場合はTuist Gradleプラグイン、Mixの場合は`tuist_ex`ライブラリです。Xcodeはまた、リンクされたプロジェクト生成イベントから`tuist_generation_version`を公開しますが、これはアップロード元のCLIと異なる場合があります。欠落している観測値はnullであり、サーバーや他のレポートから推論されません。Bazelは既存の`bazel_version`を使用し、Once実行の詳細は`once_version`を公開します。これらのフィールドは報告されたバージョンを表し、検証済みのIDやワイヤー契約バージョンではありません。RESTビルドエンドポイントも同じメタデータを公開します。既存の統合およびflaky-testスキルはバージョンフィールドに依存せず、ワークフローの変更は不要です。

Tuistオペレーターが顧客のアカウントを調査する際は、すべての呼び出しを記録するTuistの内部運用ツールを使用します。このエンドポイントへの直接接続では、ユーザー自身のメンバーシップを超えたアクセス権限は付与されません。

<details>
<summary>Claude Code</summary>

実行:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

ヘッドレスなClaude Codeクライアントが失敗したネイティブサーバー接続をモデルに公開しない場合、エージェントはホストされたドキュメントを検索したりプロジェクトを編集したりする前に、構成済みエンドポイントの認証されていない[Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP)レスポンスを検査する必要があります。ブラウザ認証が利用できない場合でも、このレスポンスはモデルをデプロイメントローカルの`auth.md`ドキュメントに誘導します。

</details>


<details>
<summary>Codex</summary>

実行:

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

新しい`codex exec`実行を開始する前に、ブラウザでのログインを完了してください。Codexは初期化中にTuistサーバーの指示を読み取るため、Gradle最適化リクエストは自動的に認証および検証ワークフローを受け取ります。

</details>


<details>
<summary>Claude Desktop</summary>

**Settings → Connectors → Add custom connector**を開き、以下を設定します:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

プロンプトが表示されたら、ブラウザで[Open Authorization](https://oauth.net/2/)を完了してください。

</details>


<details>
<summary>Pi</summary>

PiにはModel Context Protocolクライアントが含まれていません。ソースとセキュリティへの影響を確認した後、サードパーティの[`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter)拡張機能をインストールできます:

```bash
pi install npm:pi-mcp-adapter
```

プロジェクトレベルの`.mcp.json`ファイルを追加します:

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

`auth`を`false`に設定すると、アダプターのブラウザ認証ハンドラーがTuistの不正なレスポンスを隠すのを防ぎます。これにより、ヘッドレスエージェントは返された`auth_md` URLを読み取り、Tuistの登録、IDアサーション交換、およびクレームポーリングフローに従うことができます。交換されたアクセストークンをベアラートークンとして構成するか、エージェントが直接認証済みModel Context Protocol呼び出しを行うようにしてください。

ブラウザ認証を優先する場合は、`auth`を`"oauth"`に設定してください。そのフローの場合、認証が完了するまでPiの[remote procedure call mode](https://pi.dev/docs/latest/rpc)で1つのプロセスを生かしたままにしてください:

```bash
pi --mode rpc
```

コールバック状態を所有するプロセスが終了しているため、保留中のブラウザ認証を別々の`pi --print`呼び出しに分割しないでください。

</details>


<details>
<summary>OpenCode</summary>

Tuist Model Context Protocolサーバーを`opencode.json`に追加します:

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

その後、サーバーを認証します:

```bash
opencode mcp auth tuist
```

</details>


<details>
<summary>Cursor</summary>

**Cursor Settings → Tools & Integrations → Model Context Protocol Tools**を開き、以下を追加します:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

**Command Palette → MCP: Add Server**を使用し、以下の設定で[Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP)サーバーを構成します:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Agent panel → Settings → Add Custom Server**を開き、以下を設定します:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

エージェントが`auth.md`をサポートしている場合、ブラウザを開かずに匿名で開始できます。信頼できるプロバイダーIDがすでにリンクされている場合、ブラウザなしで完了することもできます。サービス認証メール、匿名クレーム、または最初のプロバイダーリンクの場合、エージェントはTuist検証リンクと6桁のコードを表示します。リンクを開き、サインインして、Tuistページでエージェントのコードを入力してください。コードをエージェントに送り返さないでください。Tuistの認証サーバーメタデータは、デプロイメント独自の`/auth.md`を直接指しており、正確なリクエストおよびポーリング形状が含まれています。

## ビルドシステム統合は2つの資格情報を使用します

Model Context Protocolツールに使用される資格情報は、GradleプラグインやBazelのリモートサービスを認証しません。エージェントがGradleまたはBazel統合を編集または検証する前に、以下を実行する必要があります:

```bash
tuist auth whoami --url https://tuist.dev
```

そのコマンドが認証されていない場合、エージェントは停止し、ユーザーに以下を実行するように依頼する必要があります:

```bash
tuist auth login --url https://tuist.dev
```

ローカルまたはセルフホスト型デプロイメントの場合、両方のコマンドおよび`tuist.toml`内のURLを置き換えてください。ホスト名のスペルは everywhere で同一に保ってください。例えば、`localhost`と`127.0.0.1`は別々の保存済み資格情報を使用します。


## 機能

### ツール

以下のツールは、Tuist Model Context Protocolサーバーを通じて利用できます:

すべてのツールは、人間が読める説明と明示的な入力・出力スキーマを公開します。成功した呼び出しは、公表された出力スキーマに準拠した構造化コンテンツを返し、さらに構造化コンテンツをまだ消費できないクライアント向けに、同じ結果をテキストとしてシリアル化したものも返します。

`build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id`、または`cache_run_id`など、単一レコードの識別子を受け取るツールは、そのレコードのTuistダッシュボードURLも受け付けます。識別子を抽出するのではなく、ブラウザからURLを直接貼り付けてください。

#### ドキュメントおよびコミュニティ検索

この読み取り専用ツールは、ドキュメントウェブサイトを動かしている同じ検索エンジンを使用して、Tuistのドキュメント、[application programming interface](https://en.wikipedia.org/wiki/API)リファレンス、GitHubリリース、コミュニティフォーラム、およびGitHubイシューを検索します。リリース結果には、製品、バージョン、公開日、プレリリースステータスが含まれます。デフォルトでは安定版リリースが検索され、`include_prereleases`を使用するとプレリリースを含めることができます。このツールは、`https://tuist.dev/mcp`にあるTuistホスト型サーバーでのみ利用できます。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `search_tuist` | 公開されているTuistドキュメント、application programming interfaceリファレンス、GitHubリリース、コミュニティディスカッション、およびGitHubイシューを検索します。オプションで、1つの`source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）に制限できます。 | `query` |

#### フィードバック

エージェントは、Tuistツールやプロンプトが期待通りに動作しなかった場合（結果が混乱を招く、エラーが発生する、データが欠落している、機能が不足しているなど）、Tuistチームに伝えることができます。エージェントはレポートを提案し、ユーザーが同意した場合のみ送信するように求められます。各レポートはTuistサポートとの会話を開始し、サポートからメールで返信が届く場合があります。レポートには、エージェントの期待値、実際に発生したこと、オプションの提案、あなたのTuistユーザーID、ハンドル、メールアドレス、および所属組織が含まれます。エージェントは、問題が発生したアカウントとプロジェクトを指定することもでき、チームはどの組織に対応すべきかを知ることができます。受け入れられるのは、あなたが所属しているアカウントのみです。Tuistユーザーとしてサインインしているエージェントのみがレポートを送信でき、各ユーザーは1時間あたり最大10件のレポートを開くことができます。このツールは、`https://tuist.dev/mcp`にあるTuistホスト型サーバーでのみ利用できます。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `report_feedback` | Tuistツールまたはプロンプトに関する問題を報告します。オプションで、問題が発生した`tool_name`、`account_handle`および`project_handle`を指定し、`suggestion`を追加できます。 | `category`, `expected`, `actual` |

#### ソースに基づいた回答

これらの読み取り専用ツールにより、エージェントはホスト型サーバーとともにデプロイされた正確な公開Tuistソースリビジョンを、現在の動作に依存する回答の信頼できる情報源として使用できます。これらは`https://tuist.dev/mcp`でのみ利用できます。

互換性のあるクライアントは、初期化中にツールのソースリビジョン、リンク、結果制限に関する事実上の説明を、インラインOAuth認証情報と一緒に受け取ります。これらの説明は、回答スタイルや検証ワークフローを規定するものではありません。ユーザーは、最初に`ask_tuist`プロンプトを呼び出さずに直接質問できます。このプロンプトは、明示的なソースベースのワークフローのために引き続き利用可能です。

すべての操作には、並行性、期間、トラバース、読み取りバイト数、およびレスポンスサイズに対する固定制限があります。検索および一覧結果には、`truncated`および`truncation_reason`フィールドが含まれます。結果が切り捨てられた場合は、結果を完全なものとして扱うのではなく、パス、ファイルパターン、または検索語句を狭めてください。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `search_tuist_code` | ソースファイルを検索することで、現在の動作、デフォルト、構成、機能ゲート、エラー処理、または文書化されていない詳細に関する質問に回答します。結果には、周囲の行、リビジョン固定されたソースリンク、およびスキャン統計が含まれます。 | `pattern` |
| `list_tuist_files` | 関連するパスが不明な場合に、ソースサブシステムまたは近隣のテストを発見します。一覧表示には深度と結果数の上限があります。 | なし |
| `read_tuist_file` | 関連するパスを見つけた後、実装ファイル、呼び出しサイト、またはテスト内の特定の行範囲を検査します。切り捨てられたレスポンスには、継続のための`next_start_line`が提供されます。 | `path` |

#### プロジェクト

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_accounts` | 認証済みユーザーが利用可能な個人および組織アカウントハンドルを一覧表示します。各アカウントがプロジェクトを作成できるかどうかも含みます。 | なし |
| `get_organization` | 組織のメンバーディレクトリを取得します。保留中の招待には、ダッシュボードと同じ管理者権限が必要です。招待受諾トークンは決して返されません。 | `account_handle` |
| `create_organization` | 認証済みユーザーのためにTuist組織を作成します。 | `handle` |
| `create_project` | 認証済みユーザーがアクセスできるアカウントの下にTuistプロジェクトを作成します。 | `account_handle`, `project_handle` |
| `add_organization_member` | 既存のTuistユーザーを組織に追加するか、既存メンバーの役割を更新します。`user`（デフォルト）、`admin`、または`viewer`を受け入れます。ビューアーはダッシュボードと実行を読み取ることができますが、何も変更することはできません。 | `organization_handle`, `email` |
| `invite_organization_member` | 既存のTuistユーザーに属しているかどうかに関わらず、メールアドレスを組織に招待します。Tuistは14日後に期限切れになる受諾リンクをメールで送信します。サーバーがメールを送信できない場合、`email_sent`は`false`となり、リンクはダッシュボードからコピーする必要があります。`user`（デフォルト）、`admin`、または`viewer`を受け入れます。組織管理者権限が必要です。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 保留中の組織招待をキャンセルし、そのリンクを受諾できないようにします。組織管理者権限が必要です。 | `organization_handle`, `email` |
| `list_projects` | 認証済みユーザーがアクセス可能なすべてのプロジェクトを一覧表示します。 | なし |
| `get_project` | プロジェクトの設定と接続されているリポジトリのURLを取得します。 | `account_handle`, `project_handle` |
| `connect_project_repository` | アカウントのGitHub AppインストールがアクセスできるGitHubリポジトリにプロジェクトをリンクします。プロジェクトはリポジトリのデフォルトブランチを採用します。プロジェクト管理者権限が必要です。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | プロジェクトのGitHubリポジトリへのリンクを削除します。プロジェクト管理者権限が必要です。 | `account_handle`, `project_handle` |

#### アカウントトークン

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_account_tokens` | トークンの値を公開せずに、アカウントトークンのメタデータを一覧表示します。 | `account_handle` |
| `get_account_token` | トークンの値を公開せずに、アカウントトークンのメタデータを取得します。 | `account_handle`, `token_id` |
| `list_project_tokens` | トークンの値を公開せずに、プロジェクトトークンのメタデータを一覧表示します。 | `account_handle`, `project_handle` |

#### CIランナー

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_runner_jobs` | アカウントのCIランナージョブを一覧表示します。 | `account_handle` |
| `get_runner_job` | CIランナージョブを取得します。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | CIランナージョブで記録されたステップを一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | CIランナージョブで記録されたマシンメトリクスを一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | CIランナージョブでキャプチャされた最大500行のログを一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | アカウントのCIワークフローの集計を一覧表示します。 | `account_handle` |
| `list_runner_profiles` | アカウントのCIランナープロファイルを一覧表示し、各プロファイルの`runs-on`ラベルを含めます。 | `account_handle` |
| `get_runner_catalog` | ランナープロファイルが使用できるマシンシェイプとXcodeバージョンを一覧表示します。 | `account_handle` |
| `create_runner_profile` | プラットフォーム、マシンシェイプ、およびmacOSではXcodeバージョンを指定してランナープロファイルを作成します。オプションで、キャッシュボリュームを保存するブランチを設定できます。アカウント管理または`account:runners:write`スコープが必要です。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | ランナープロファイルのマシンシェイプ、Xcodeバージョン、またはカスタムキャッシュボリュームの変更を保存するブランチを変更します。省略されたフィールドは値を保持します。アカウント管理または`account:runners:write`スコープが必要です。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | ユーザーの確認後にランナープロファイルを削除します。デフォルトのプロファイルは削除できません。アカウント管理または`account:runners:write`スコープが必要です。 | `account_handle`, `profile_name` |

ランナーボリュームツールは、Volumesダッシュボードと同じデータを公開します。読み取りツールにはランナーアクセスが必要であり、クリアにはアカウント管理または`account:runners:write`スコープ、およびユーザーの確認が必要です。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_runner_volumes` | 名前とリポジトリでフィルタリングし、ボリュームをソートおよびページネーションします。 | `account_handle` |
| `get_runner_volume` | リポジトリ、プラットフォーム、容量、使用済みスペース、最終使用日時。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | ページネーションされたジョブとワークフローの参照、キャッシュステータス、ヒット結果、マウント時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | ジョブによってマウントされたボリューム。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | ストレージ時系列、ジョブ実行、ヒット率、トレンド。オプションの`volume_id`、`start`、および`end`（ISO 8601）。デフォルトは7日間、最大90日間。 | `account_handle` |
| `clear_runner_volume` | 保存された内容をクリアします。実行中のジョブはプライベートコピーを保持しますが、保存することはできません。後続のジョブは空の状態から開始されます。 | `account_handle`, `volume_id` |

一覧は`page`と`page_size`（最大100）を受け入れます。ボリュームインベントリは、`name`と`repository`（完全一致、ANDで結合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）、および`sort_order`（`asc`、`desc`）も受け入れます。不明な測定値とヒット結果は`null`のままです。キャッシュステータスは、ボリュームの変更が保存されたかどうかを示し、ジョブの成功を示すものではありません。

#### Webhook

Webhookツールは、ダッシュボードと同じ管理者専用権限を使用します。配信試行には、エンドポイント用に記録されたリクエストとレスポンスのデータが含まれますが、エンドポイントの署名シークレットは含まれません。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_webhook_endpoints` | アカウントのWebhookエンドポイントを一覧表示します。 | `account_handle` |
| `get_webhook_endpoint` | Webhookエンドポイントを取得します。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | エンドポイントの配信試行を一覧表示します。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 配信試行を取得します。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcodeビルド

Xcode、Gradle、Bazel、Mix、Cargoのビルド詳細ツールは、既存の`custom_metadata: {tags, values}`構造を公開し、報告されたインフラストラクチャ観測値を含みます。値は文字列として保持され、不明なキーも保存されます。例えば、`tuist.cpu.available_processors`はランタイムで利用可能な論理プロセッサ数を示し、`tuist.gradle.max_workers`はGradleのワーカ制限、`tuist.jvm.max_heap_bytes`はJVMヒープ制限（ホストメモリではありません）を示します。これらは信頼できないクライアント観測値であり、検証済みのランナー識別子ではありません。欠落している観測値はそのまま欠落したままとなり、インポートされたログや古いクライアントにはインフラストラクチャメタデータが含まれない場合があります。メタデータの形式は、クライアントとプロトコルの調整された更新を待っています。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_xcode_builds` | プロジェクトのXcodeビルド実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 特定のXcodeビルド実行に関する詳細情報を取得します。これには、生の`.xcactivitylog`を含むアーカイブの一時ダウンロードURLが含まれます。 | `build_run_id` |
| `list_xcode_build_targets` | 特定のXcodeビルド実行のビルドターゲットを一覧表示します。 | `build_run_id` |
| `list_xcode_build_files` | 特定のXcodeビルド実行のコンパイル済みファイルを一覧表示します。 | `build_run_id` |
| `list_xcode_build_steps` | ログテキストを除く、タイミングと結果付きの記録済みビルドステップを一覧表示します。 | `build_run_id` |
| `get_xcode_build_step` | ログと切り捨てフラグを含む、記録済みのビルドステップを1つ取得します。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 特定のビルド実行のビルド問題（警告とエラー）を一覧表示します。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 特定のXcodeビルド実行のキャッシュ可能タスク（キャッシュヒット/ミス）を一覧表示します。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 特定のXcodeビルド実行の[コンテンツアドレサブルストレージ](https://en.wikipedia.org/wiki/Content-addressable_storage)出力を一覧表示します。 | `build_run_id` |

`list_xcode_build_steps`はデフォルトで20ステップのページを返します（`page_size`により最大100）。ナビゲーションには`page`と`pagination_metadata`を使用します。`search`を使用してタイトル、プロジェクト、またはターゲットを一致させるか、正確な`project`、`target`、`category`（例：`swiftCompilation`）、および`status`（`success`または`failure`）でフィルタリングします。`duration_ms`でソートすると遅い順（デフォルト）、`start_ms`でソートすると時系列順になります。ステップIDは同順位を解消し、64ビット精度を完全に保持するために10進数文字列として返されます。IDはビルドごとにスコープされており、ビルド間で一致させてはいけません。

オプションの`start_ms`と`end_ms`は、ビルド開始からのミリ秒単位の時間範囲と重複するステップを選択します（終端は除外されます）。どちらのツールも、ビルドUUIDまたはダッシュボードURLを`build_run_id`として受け入れます。返されたステップ`id`を変更せずに`step_id`として渡し、そのログを取得します。ログはステップあたり最大64 KiBを保持し、`log_truncated`は省略された出力を示します。

ステップは、Xcodeビルドが処理される際にデフォルトで収集されます。記録されたステップデータは90日間保持されます。一覧レスポンスには`availability`が含まれます：記録されたステップが存在する場合は`available`（フィルタに一致するものがなくても同様）；ビルドがまだ処理中でステップがない場合は`processing`；ステップが記録されていないか期限切れの場合は`unavailable`。

同じ操作は、HTTP APIの`GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps`および`GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}`で利用可能であり、同じフィルタとページネーションをサポートします。どちらもビルドのプロジェクトへの読み取りアクセスが必要です。

#### Gradleビルド

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 完全な認証、プロジェクト設定、Gradleプラグイン、キャッシュポリシー、および2回ビルドによる検証ワークフローを返します。エージェントは、既存のAndroidまたはGradleプロジェクトを編集する前にこれを呼び出す必要があります。 | なし |
| `list_gradle_builds` | カスタムメタデータを含む、プロジェクトのGradleビルド実行を一覧表示します。オプションの`tag`パラメータを使用してカスタムタグでフィルタリングします。 | `account_handle`, `project_handle` |
| `get_gradle_build` | ビルドメタデータとタスク/キャッシュのカウントを取得します。 | `build_run_id` |
| `list_gradle_build_tasks` | タスクの結果、複合ビルド識別子、キャッシュ可能性、および増分ステータスを一覧表示します。 | `build_run_id` |
| `list_gradle_build_steps` | 検索、メタデータ、および重複する時間フィルタを使用して、タイミング付きタスク、構成、および変換を一覧表示します。 | `build_run_id` |
| `get_gradle_build_step` | 不透明なIDによって記録されたステップメタデータを検査します。ステップごとのログは利用できません。 | `build_run_id`, `step_id` |

GradleおよびBazelのステップ一覧はデフォルトで20件の結果（最大100件）を返し、`search`、正確な`project`、`target`、`category`、および`status`、重複する`start_ms` / `end_ms`フィルタ（終端除外）、および`duration_ms`または`start_ms`での並べ替えをサポートします。返されたIDは変更せずに渡してください。これらはビルドごとにスコープされています。一覧は`time_origin`と`coverage`を公開します。古いGradleレポートは、ビルド開始がアップロードされていないため`first_recorded_timestamp`を使用します。Bazelプロファイルは、`trace_profile`カバレッジと時間原点としての`profile_start`を使用して、すべての記録された間隔を公開します。古いビルドは保持されたBEPサマリーにフォールバックします。ソースレコードは90日後に期限切れになります。Bazelの詳細には、公開されている場合にサニタイズされたアクションログが含まれます。Gradleの詳細`log`はnullです。`compare_builds`プロンプトはこのカバレッジを使用して、完全なBazelトレースと保持されたサマリーを区別し、より広範な呼び出し出力を確認する前に、エージェントをアクションの結果とログのためのステップ詳細へ誘導します。

保持されたサマリーから返されたBazelステップIDは、一覧表示とステップのフェッチの間に完全なプロファイルが到着した場合でも読み取り可能です。ステップデータが期限切れになったインデックス付きプロファイルは、利用不可と報告されます。Gradleステップ一覧には、持続時間ゼロのキャッシュ済みおよびスキップされた操作が含まれます。

#### Bazel呼び出し

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 認証、プロジェクト設定、Bazel構成、および検証ワークフローを返します。 | なし |
| `list_bazel_invocations` | プロジェクトのビルドメトリクス、制限された実行タイムライン、クリティカルパス診断、および相関するリモートキャッシュ合計を含む、完了した[Bazel Build Event Protocol](https://bazel.build/remote/bep)呼び出しを一覧表示します。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | ビルドメトリクス、制限された実行タイムライン、クリティカルパス診断、および相関するリモートキャッシュ合計を含む、完了したBazel呼び出しを1件取得します。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | フィルタと明示的なカバレッジを使用して、記録されたBazelプロファイル間隔を一覧表示します。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 記録されたBazelステップと、その公開されたアクション結果およびサニタイズされたログを検査します。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | Bazel呼び出しのためにキャプチャされたサニタイズされたテストログを、実行順に一覧表示します。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bazel呼び出しのためにキャプチャされたサニタイズされたテストログを1件取得します。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 操作、エンドポイント、および観測時刻を含む生のBazelリモートキャッシュ観測を一覧表示します。オプションで、呼び出し、結果、または操作に絞り込むことができます。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 生のBazelリモートキャッシュ観測を1件取得します。 | `account_handle`, `project_handle`, `cache_event_id` |

#### Cargoビルド

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_cargo_builds` | プロジェクトのCargoビルドを新しい順に一覧表示します。`git_branch`、`status`、`is_ci`、または`command`でフィルタリングできます。Cargoテストの実行結果は、このビルド一覧ではなくテストツールを通じて利用できます。 | `account_handle`, `project_handle` |
| `get_cargo_build` | ビルドメタデータ、集計キャッシュカウンター、および診断情報付きで最大500件の記録されたコンパイラジョブを取得します。`compilations_truncated`は省略されたジョブを示します。診断情報は返されたジョブのみを対象とします。 | `account_handle`, `project_handle`, `build_id` |

`get_cargo_build`で`include_cache_inspection: true`を設定し、検証済みのタスク決定とCAS操作を4 MBの制限内で取得します。デフォルトでは、またレコードが欠落しているか無効な場合、`cache_inspection`はnullです。部分キャプチャの`truncated`フラグを尊重してください。転送は各タスクヒットのローカル/リモート origin を確立しません。HTTP詳細エンドポイントも同じクエリパラメータを受け入れます。

#### Mixビルド

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_mix_builds` | プロジェクトのMix（Elixir）コンパイルビルドを新しい順に一覧表示します。カスタムメタデータを含みます。`git_branch`、`status`、`is_ci`、または`mix_env`でフィルタリングできます。 | `account_handle`, `project_handle` |
| `get_mix_build` | ビルドメタデータ、診断カウント、および依存関係キャッシュのサマリーを取得します。 | `account_handle`, `project_handle`, `build_id` |

#### ビルドトレース

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `get_build_trace` | Xcode、Gradle、Bazel、またはMixビルドのタイムラインを、[Perfetto](https://ui.perfetto.dev)で開けるトレースファイルとしてダウンロードするためのリンクを取得します。 | `account_handle`, `project_handle`, `build_id` |

`build_id`はビルド実行ID（Bazelの場合は呼び出しID）またはビルドのダッシュボードURLです。返される`trace_url`は[Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSONファイルを配信します。リンクを持っている人は誰でも、他の認証情報なしで、呼び出しから1時間後の`expires_at`まで、そのビルドのトレースをダウンロードできます。エージェントは`curl`でダウンロードしたり、あなたがPerfettoで開くために渡したり、Perfettoの`trace_processor`でクエリしたりできます。トレースには、並列性によってレーンにパックされた記録されたステップ、ビルド全体にわたるトラック、およびビルドがマシンメトリクスを記録した場合のCPUおよびメモリカウンターが含まれます。ログを除き、上記のステップツールと同じデータを保持します。ダッシュボードでは、各ビルドの［Timeline］タブから同じファイルを提供しています。

#### Once実行

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_once_runs` | プロジェクトのOnce実行を新しい順に一覧表示します。`kind`（`build`、`test`、または`generic`）、`status`、`is_ci`、または`git_branch`でフィルタリングできます。完了していない実行のステータスは`in_progress`です。 | `account_handle`, `project_handle` |
| `get_once_run` | アクション合計、キャッシュサマリー、およびテスト実行の場合はテスト合計を含む実行を取得します。 | `account_handle`, `project_handle`, `run_id` |

Cargoビルド、Mixビルド、およびOnce実行IDはプロジェクト内で一意です。同じ読み取りは、HTTP API経由で`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds`、および`.../once/runs`で利用でき、それぞれに1つのID用の詳細エンドポイントがあります。

#### タスク、アクション、モジュール、およびファイル

これらのプロジェクトスコープのツールは、実行間で永続的なビルド識別子を検査します。`list_build_entities`から開始し、返された安定した`id`と同じ`kind`を`get_build_entity`または`list_build_entity_history`に渡し、`account_handle`と`project_handle`も一緒に指定します。ビルドまたは呼び出し識別子は必要ありません。

| ツール | 説明 | 必須パラメータ |
| --- | --- | --- |
| `list_build_entities` | プロジェクトのビルド全体で確認された、ある種類のタスク、モジュール、アクション、またはファイルを一覧表示します。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 選択した期間におけるネイティブ識別子と分析情報を含む、1つのビルドエンティティを取得します。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 1つのビルドエンティティの記録された実行、コンパイル、またはキャッシュイベントを新しい順に一覧表示します。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | ツールチェーン | 履歴リスト |
| --- | --- | --- |
| `bazel_actions` | Bazelアクション | BEPで報告されたアクション実行 |
| `gradle_tasks` | Gradleタスク | タスク実行 |
| `xcode_modules` | Xcodeモジュール | コンパイルおよびモジュールキャッシュイベント |
| `once_actions` | Onceアクション | 実行 |
| `mix_files` | Mixコンパイル済みファイル | コンパイル |
| `mix_modules` | Mixコンパイル済みモジュール | コンパイル |
| `cargo_crates` | Cargoクレート | 記録されたrustc呼び出し |

これらのツールは段階的にロールアウトされており、有効化されているプロジェクトのデータのみを返します。他のプロジェクトでは、空の結果ではなくエラーが返されます。種類は、そのビルドツールチェーンを使用しているプロジェクトでのみ利用可能です。ツールは制限付きの`start_at`/`end_at`フィルタ、`environment`（`any`、`ci`、または`local`）、および正確な`branch`を受け入れます。`list_build_entities`は`q`を受け付けます。`list_build_entity_history`は不透明な`after`/`before`カーソルをサポートします。不明なタイミングまたはキャッシュの観測値は、ゼロやミスとして扱われるのではなく、利用不可のままとなります。履歴は、既存の実行ツールを使用したドリルダウンのために、記録された親およびネイティブ実行を参照します。

`get_build_entity`のメトリクスには、タイミングが記録された観測値の数を示す`duration_samples`が含まれます。実際のゼロdurationはカウントされますが、タイミングが欠落している場合はカウントされません。この数は観測値の数より少ない場合があります。利用できないduration統計はnullのままです。

Xcodeモジュールのdurationは、ビルドログで測定されたターゲットコンパイルから取得されます。モジュールキャッシュの解決およびコンパイル作業のないターゲットは、durationサンプルに貢献しません。コンパイルの観測値はXcodeビルドを参照し、キャッシュイベントは生成またはキャッシュコマンドを参照します。

Bazelアクションは、ターゲットラベル、ニーモニック、および構成されたプライマリ出力によって識別され、入力依存のキャッシュダイジェストに頼ることなく、個別のアクションと構成を区別します。履歴はキャッシュルックアップやトレースプロファイルフェーズではなく、BEPで報告された実行を記録します。完全な実行カバレッジには`--build_event_publish_all_actions`が必要です。アーティファクトの配信はベストエフォートであるため、観測値の欠落は作業が実行されなかった証拠ではありません。安定した識別子または実行開始情報を持たない古いKuraペイロードは受け入れられますが、インデックス化されません。終了時間の測定値がない場合は利用不可のままとなり、実際のゼロdurationはカウントされます。

Mixモジュールのdurationは、含まれるファイルのコンパイルを測定するものであり、独立して測定されたモジュール作業ではありません。Onceアクションは、クライアントがターゲットマッピングを報告した際に宣言されたターゲット/機能/インデックススロットを使用します。診断ラベルだけでは安定した識別子にはなりません。既存のクライアントおよび実行レベルのツールは変更なくサポートされます。

Cargoクレートは、正確に記録されたクレートルート、名前、および種類によってグループ化されます。チェックアウトパスの変更により履歴が分割される可能性があり、ビルドプロファイル、機能、およびターゲットトリプルは区別されません。履歴はrustc呼び出しを測定するものであり、ファイルごとの作業やキャッシュヒットではありません。欠落したジョブは削除や完全なワークスペース在庫の確立を示すものではありません。

分析読み取りにはメモリと実行時間の制限があります。クエリがこれらの制限を超えた場合、ツールは空の結果を捏造する代わりにエラーを返します。

新しい観測値はデプロイ後にインデックス化されます。この機能は既存の実行テレメトリをバックフィルしません。識別子メタデータは、<.localized_link href="/guides/server/data-retention">データ保持ポリシー</.localized_link>に基づき、個々の観測値よりも長く存続します。

#### テスト

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_test_runs` | プロジェクトのテスト実行を一覧表示します。`query`フィールドは`git_branch`、`scheme`、および`status`です。`field:"value"`は完全一致、`field~"value"`は大文字小文字を区別しない部分一致、先頭の`-`はいずれかの演算子を否定します。例えば、`-git_branch~"gh-readonly-queue"`はマージキューブランチを除外します。空白で区切られたクエリフィルタと明示的な引数はANDセマンティクスで結合されます。 | `account_handle`, `project_handle` |
| `get_test_run` | 結果バンドル（`.xcresult`）およびセッションアーカイブの一時的なダウンロードURLを含む、テスト実行の詳細メトリクスを取得します。 | `test_run_id` |
| `list_test_module_runs` | 特定のテスト実行に対するテストモジュール実行を一覧表示します。 | `test_run_id` |
| `list_test_suite_runs` | 特定のテスト実行に対するテストスイート実行を、オプションでモジュールによってフィルタリングして一覧表示します。 | `test_run_id` |
| `list_test_cases` | プロジェクトのテストケースを一覧表示します（`flaky`などのフィルタをサポート）。 | `account_handle`, `project_handle` |
| `get_test_case` | 信頼性率、flakiness率、および実行回数を含む、テストケースの詳細メトリクスを取得します。 | `test_case_id`または`identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | テストケース実行を一覧表示します。オプションでテストケースまたはテスト実行によってフィルタリングできます。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 特定のテストケース実行の失敗詳細と繰り返し回数を取得します。 | `test_case_run_id` |
| `list_test_case_run_attachments` | テストケース実行の添付ファイルを一覧表示します。各添付ファイルには一時的なダウンロードURLが含まれます。 | `test_case_run_id` |
| `list_test_case_events` | ミュートやスキップなど、テストケースの状態変化を一覧表示します。 | `test_case_id` |
| `update_test_case` | テストケースの状態またはflaky分類を更新します。変更により、外部サービスを含む設定済みのWebhookエンドポイントにイベントが送信される場合があります。 | `test_case_id`または`identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | テスト実行の選択的テストターゲット結果を一覧表示します。 | `test_run_id` |
| `get_coverage` | コミットまたはブランチの最新の完全なコミットにおいて、ターゲットを含むプロジェクトのコードカバレッジを取得します。`git_commit_sha`または`branch`がない場合、デフォルトブランチを読み取ります。 | `account_handle`, `project_handle` |
| `list_coverage_files` | コミットまたはブランチの最新の完全なコミットにおいて、コミットのコードカバレッジが測定したファイルとその行カバレッジを一覧表示します。`search`、ソート、およびページネーションをサポートします。 | `account_handle`, `project_handle` |
| `get_coverage_file` | コミットまたはブランチの最新の完全なコミットにおいて、ファイルのコードカバレッジとその関数を取得します。各行の実行回数を取得するには`include_lines`を設定します。 | `account_handle`, `project_handle`, `path` |

コードカバレッジツールは、コードカバレッジが有効になっているアカウントで利用できます。

#### バンドル

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_bundles` | プロジェクトのバンドル（アプリバイナリ）を一覧表示します。オプションで`git_branch`および`tags`でフィルタリングできます（すべてのタグは完全に一致する必要があります）。 | `account_handle`, `project_handle` |
| `get_bundle` | カスタムタグを含む、特定のバンドルの詳細情報を取得します。 | `bundle_id` |
| `get_bundle_artifact_tree` | パスでソートされたフラットリストとして、バンドルの完全なアーティファクトツリーを取得します。 | `bundle_id` |

`list_bundles`は`tags: ["paid", "production"]`を受け入れ、ビルドフレーバーや環境を区別します。タグは大文字小文字を区別するラベルで、英字、数字、ハイフン、アンダースコアを含み、タグは最大10個、各タグは最大50文字です。一覧および詳細結果には`custom_metadata.tags`が含まれます。ページネーションカウントとブランチフィルタはタグ付けされた結果に適用されます。`tags`を省略すると、フィルタリングされていない動作が維持されます。無効なタグフィルタはクエリを広げるのではなくエラーを返します。

#### ジェネレーション

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_generations` | プロジェクトのジェネレーション実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_generation` | 特定のジェネレーション実行の詳細情報を取得します。 | `generation_id` |

#### キャッシュ実行

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_cache_runs` | プロジェクトのキャッシュ実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_cache_run` | 特定のキャッシュ実行の詳細情報を取得します。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | ジェネレーションまたはキャッシュ実行のモジュールキャッシュターゲットを一覧表示し、追加のハッシュ入力を含む、ターゲットごとのキャッシュヒット/ミスステータスと診断コンポーネントハッシュを表示します。 | `run_id` |

#### プレビュー

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_previews` | プロジェクトの共有可能なアプリプレビューを一覧表示します。 | `account_handle`, `project_handle` |
| `get_preview` | プレビューとそのビルドの一時的なダウンロードURLを取得します。 | `preview_id` |
| `get_latest_preview` | 実行中のアプリバイナリの最新のプレビューを検索します。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自動化

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_automation_alerts` | プロジェクトの自動化アラートを一覧表示します。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 自動化アラートを取得します。 | `alert_id` |
| `list_automation_alert_revisions` | 自動化アラートのリビジョン履歴を一覧表示します。アクションの認証情報はマスキングされます。 | `alert_id` |
| `list_project_notification_alerts` | プロジェクト通知アラートルールを一覧表示します。ダッシュボード設定ページと同じ管理者権限が必要です。Webhookアドレスはマスキングされます。 | `account_handle`, `project_handle` |

### イベント

ステートレスな`2026-07-28`Model Context Protocolライフサイクルを使用するクライアントは、`events/list`を呼び出してイベントとそのペイロードスキーマを検出できます。

| イベント | 送信タイミング | サブスクリプションフィルタ |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | テストケースが不安定でない状態から不安定な状態に変更されます。 | `account_handle`, `project_handle` |
| `build.failed` | ローカルまたは継続的インテグレーションのXcode、Gradle、またはBazelビルドが失敗で終了します。 | `account_handle`, `project_handle` |
| `test_run.failed` | ローカルまたは継続的インテグレーションのテスト実行が失敗で終了します。マージされたシャーディング実行や中断された実行も含まれます。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuistランナージョブが失敗で完了します。 | `account_handle` |

サブスクライブするには、クライアントはイベント名、上記の`arguments`にリストされたハンドル、および`https://`コールバックURLと`whsec_`署名シークレットを含む`webhook`配信を使用して`events/subscribe`を呼び出します。プロジェクトイベントにはアカウントメンバーシップと対応するテストまたはビルドデータへの読み取りアクセスが必要です。ランナージョブイベントにはアカウントメンバーシップとランナー読み取りアクセスが必要です。付与された[`auth.md`](https://workos.com/auth-md)アクセストークン、付与されたアカウントトークン、およびブラウザ認可グラントはサブスクリプションを作成できます。関連する認証情報が有効でなくなると配信は停止します。各ユーザーは最大25件のアクティブなサブスクリプションを保持できます。Tuistはサブスクリプションを保存する前に検証チャレンジをコールバックに送信します。コールバックは同じ`challenge`値を含むオブジェクトを返す必要があります。サブスクリプションのデフォルトの有効期限は7日で、再度サブスクライブすることで更新でき、ユーザーのアクセスまたは認証情報が削除されると配信が停止します。オプションの`ttlMs`は1時間から30日の範囲に制限されます。Tuistはタイムアウトしたコールバックを再試行し、5分間にわたる少なくとも3回連続のタイムアウト後にサブスクリプションを解除します。コールバックを復旧した後、再度サブスクライブしてください。

イベントが発生すると、Tuistはそのリソース識別子とダッシュボードURLをコールバックに送信します。ビルドおよびテスト実行の失敗には`is_ci`と`git_branch`も含まれるため、クライアントはローカルの失敗を無視したり、ブランチでフィルタリングしたりできます。ビルドイベントには`build_system`が含まれます。ランナージョブイベントには`workflow_job_id`と`workflow_run_id`の両方が含まれます。リクエストにはサブスクリプション識別子と[Standard Webhooks](https://www.standardwebhooks.com/)署名ヘッダーが含まれており、クライアントは発信元を検証できます。Tuistは失敗した配信を再試行するため、クライアントは安定した`eventId`を使用して重複を除外する必要があります。ペイロードにはテスト名、ログ、および失敗メッセージは省略されています。クライアントは上記のツールを通じてこれらの詳細を取得し、チームに通知するかデバッグを開始するかを決定できます。クライアントは`events/unsubscribe`を使用して配信を停止できます。

### プロンプト

| プロンプト | 説明 |
|--------|-------------|
| `fix_flaky_test` | 失敗パターンを分析し、根本原因を特定して、対象を絞った修正を適用することで、不安定なテストの修正をガイドします。 |
| `compare_builds` | ビルドを比較してパフォーマンスの低下、キャッシュの変更、およびビルドの問題を特定する手順をガイドします。Xcode、Gradle、Bazel、およびCargoプロジェクト用のネイティブツールを使用します。Cargoの比較では部分的なコンパイラカバレッジを維持し、推定されるコンパイラ作業量と経過時間による節約を区別します。 |
| `compare_test_runs` | 2つのテスト実行を比較して、回帰、新しい失敗、および不安定なテストを特定する手順をガイドします。 |
| `compare_bundles` | 2つのバンドルを比較して、アーティファクトツリー全体のサイズ変更を特定する手順をガイドします。 |
| `compare_test_case` | 2つのブランチまたは期間にわたるテストケースの動作を比較する手順をガイドします。 |
| `compare_generations` | 2つのジェネレーション実行を比較して、パフォーマンスの低下とモジュールキャッシュの変更を特定する手順をガイドします。 |
| `compare_cache_runs` | 2つのキャッシュ実行を比較して、キャッシュの有効性の変化とターゲットレベルの回帰を特定する手順をガイドします。 |
| `integrate_gradle_project` | 既存のGradleプロジェクトにTuistを統合する手順をガイドします。個別のツールとGradleの認証、アカウントの検出、プロジェクトの作成、リモートキャッシュポリシー、ビルドインサイト、および読み戻し検証が含まれます。 |
| `integrate_bazel_project` | Bazelプロジェクトの作成または選択、コマンドラインの認証、リモートキャッシュとビルドインサイトの構成、およびTuistビルドデータを通じた統合の検証を行う手順をガイドします。 |
| `integrate_xcode_project` | 既存のXcodeプロジェクトにTuistを統合する手順をガイドします。Xcodeキャッシュ、ビルドインサイト、テストインサイト、およびテストシャーディングをサポートします。 |
| `ask_tuist` | 公開資料を文脈として使用し、焦点を絞った実装とテスト証拠を現在の動作の信頼できる情報源として、Tuistに関する質問に回答します。`question`が必要であり、リビジョン固定の証拠を引用します。 |

プロジェクトデータのプロンプトは、調査を特定のプロジェクトに限定するために`account_handle`と`project_handle`を受け入れます。比較プロンプトは、比較する2つの項目（ID、ダッシュボードURL、またはブランチ名で指定）を指定するための`base`および`head`引数も受け入れます。`ask_tuist`はプロジェクトパラメータの代わりに`question`を受け入れます。`integrate_gradle_project`は、適用するGradle統合のカンマ区切りリストである`features`も受け入れます。`remote_cache`、`build_insights`、`test_insights`、`flaky_tests`、および`test_sharding`。`integrate_bazel_project`は、セルフホスト型またはローカルインストール用のオプションの`server_url`を受け入れます。`integrate_xcode_project`は、`xcode_cache`、`build_insights`、`test_insights`、および`test_sharding`を含む`features`を受け入れます。

#### Gradle統合プロンプトの機能

`integrate_gradle_project`プロンプトと`get_gradle_integration_guide`ツールは、完全なセットアップワークフローを文書化しています。このツールはサーバーの初期化指示でも参照されており、プロンプトを列挙しないエージェントでも検出可能になります。

| 機能 | エージェントが構成する内容 |
|---------|---------------------------|
| `remote_cache` | Gradleのビルドキャッシュを有効にし、Tuistのリモートキャッシュアップロードポリシーを構成し、ローカルでの読み取り専用使用を持つ継続的インテグレーションランナーからのみアップロードすることを推奨します。 |
| `build_insights` | Tuist Gradleプラグインを適用し、必要に応じてビルドアナリティクスのアップロード動作を構成します。 |
| `test_insights` | Tuist Gradleプラグインを適用し、Gradle `Test`タスクの結果が自動的にアップロードされるようにします。 |
| `flaky_tests` | 不安定なテストの検出、Gradle Test Retry プラグインのオプション使用、およびテスト隔離の構成に関するセットアップをガイドします。 |
| `test_sharding` | `tuistPrepareTestShards`、シャードマトリックス生成、および`TUIST_SHARD_INDEX`に基づくテスト実行のための継続的インテグレーションワークフローを追加します。 |

`features`が省略された場合、プロンプトはエージェントにユーザーが希望する統合を明確にするか、Gradleプロジェクトを編集する前にリクエストから最小限の実用的なセットを推測するよう求めます。

#### Xcode統合プロンプトの機能

`integrate_xcode_project`プロンプトは、TuistがサポートするすべてのXcode統合を文書化しています：

| 機能 | エージェントが構成する内容 |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`、生成されたプロジェクトのキャッシュ設定、手動Xcodeキャッシュビルド設定、および継続的インテグレーションランナーに限定されたアップロードポリシーを構成します。 |
| `build_insights` | `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath`、および`tuist setup insights`を通じたオプションのマシンメトリクスを構成します。 |
| `test_insights` | `tuist inspect test`、スキームテストのポストアクション、および継続的インテグレーションテスト実行用の結果バンドル生成を構成します。 |
| `test_sharding` | Xcodeまたは生成されたプロジェクトのシャード計画と`TUIST_SHARD_INDEX`を使用したシャード実行ワークフローを追加します。 |

`features`が省略された場合、プロンプトはエージェントにユーザーが希望する統合を明確にするか、Xcodeプロジェクトを編集する前にリクエストから最小限の実用的なセットを推測するよう求めます。
