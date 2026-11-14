---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · エージェントコーディング · 機能 · ガイド · Tuist",
  "description": "Tuist の MCP エンドポイントを通じて、AI エージェントにテストインサイトなどへのアクセスを提供します。"
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro)は、AIエージェントが外部サービスやデータソースと対話できるようにするオープンスタンダードです。[Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/)といったアプリケーションや、[Zed](https://zed.dev)、[Cursor](https://www.cursor.com)、[Visual Studio Code](https://code.visualstudio.com)などのエディタをTuistと相互運用可能にします。

Tuistは`https://tuist.dev/mcp`でサーバーサイドのModel Context Protocolエンドポイントをホストしています。クライアントをこれに接続することで、エージェントはテストインサイト、flakyテスト分析などを含むTuistプロジェクトデータにアクセスできます。ほとんどのツールは読み取り専用で、認証されたTuistプロジェクトデータにスコープが限定されています。アカウント設定ツールは、認証済みユーザーに必要な権限がある場合、アカウントの一覧表示、組織の作成、プロジェクトの作成、および既存ユーザーの組織への追加が可能です。各ツールは、読み取り専用かどうか、元に戻すのが困難な変更を引き起こす可能性があるか、公的なインターネットの状態を変更できるかを示すアノテーションを公開します。`update_runner_profile`、`update_notification_rule`、および`connect_claude_subscription`は、既存の設定や認証情報を置き換える可能性があるため、`destructiveHint: true`を公開します。アカウント設定ツールにはユーザー認証が必要です。プロジェクトトークンや通常のアカウントトークンでは利用できません。ユーザーがブラウザでクライアントを承認するか、`auth.md`登録をクレームすると、Tuistはその認証情報をModel Context Protocolエンドポイント上でのみユーザーに関連付け、設定ツールが要求されたワークフローを完了できるようにします。

Tuistは[2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)を実装しています。リクエストはステートレスです。クライアントは各リクエストとともにプロトコルメタデータを送信し、初期化なしで直接ツールを呼び出すことができます。`server/discover`は、サーバーの識別情報、機能、サポートされているバージョン、および手順を返します。セッション識別子や独立したイベントストリームはありません。2025-06-18または2025-03-26の初期化フローを使用するクライアントも引き続きサポートされており、それらもサーバーセッションなしで動作します。

## Model Context Protocolとスキル

Model Context Protocolツールと<.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link>は、その機能が重複する場合があります。現在の重複状況を考慮し、ワークフローごとに1つのアプローチを選択し、同じフロー内で両方を混在させるのではなく、一貫して使用してください。

プラグインインストールをサポートするクライアントの場合、<.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link>を使用して両方を一緒にインストールしてください。

## 設定

クライアントのリモートModel Context Protocolサーバーとして`https://tuist.dev/mcp`を追加してください。サーバーの初期化手順と公開サーバーカードは、エージェントに外部の認証ドキュメントを取得またはフォローさせることなく、動的クライアント登録を伴うOAuth 2.0と標準的なブラウザ承認フローをインラインで説明しています。これらのサーバー全体の指示により、ワークフローガイダンスは一般的なものに留まります。ツールの認証はローカルコマンドラインツールやビルドシステム統合を認証せず、エージェントは関連するTuistツールを通じて要求された変更を確認する必要があります。ビルドシステム固有の設定と認証チェックは、統合ガイドとプロンプトに記載されています。Tuistは引き続き、[Open Authorization](https://oauth.net/2/)ディスカバリーメタデータと現在の[auth.md protocol](https://workos.com/auth-md)を`https://tuist.dev/auth.md`で個別に公開しています。

組織のいずれかがシングルサインオンを強制している場合、ブラウザでクライアントを承認するには、その組織を通じてサインインしたセッションが必要であり、必要に応じてTuistはまずプロバイダーにリダイレクトします。<.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">single sign-on</.localized_link>を参照してください。

このエンドポイントは、古いセッションベースのライフサイクル alongside `2026-07-28`ステートレスなModel Context Protocolリクエストライフサイクル（`server/discover`を含む）を受け入れます。既存のクライアントは、現在の接続方法を继续使用できます。

Model Context Protocolイベントをサポートするクライアントは、プロジェクトイベントをサブスクライブできます。利用可能なイベントと配信要件については、[Events](#events)を参照してください。

リモートブラウザ認証をすでにサポートしているクライアントは、ブラウザでの認証を続けることができます。`auth.md`をサポートするクライアントとエージェントは、匿名で登録したり、信頼されたプロバイダーのIDアサーションを提示したり、サービス認証された電子メールクレームを開始したりできます。登録によりTuist署名付きIDアサーションが返され、エージェントはこれを標準トークンエンドポイントで交換して1時間有効のアクセストークンを取得します。Tuistは公開署名鍵を公開し、標準的なトークン失効とプロバイダーセキュリティイベントの配信をサポートしています。

認証されていないエージェントは、Model Context Protocolエンドポイントから返される`WWW-Authenticate`ヘッダーを読み取り、保護リソースメタデータを取得し、認証サーバーメタデータを取得して、その`agent_auth.skill`URLに従う必要があります。Tuistは、言語モデル駆動型クライアントがネイティブクライアント統合に頼らずにフローを発見できるように、不正なレスポンスボディにも同じローカル`auth_md`URLを返します。デプロイメントローカルドキュメントは、エンドポイント名、リクエストボディ、クレームポーリング、およびアサーション交換の信頼できる情報源です。

エージェントが電子メールクレームを開始する前に、ユーザーにTuistアカウントの電子メールアドレスを確認してもらう必要があります。プロバイダープロフィール、Git設定、環境変数、またはセッションメタデータからそのアドレスを推測してはいけません。

このエンドポイントは`mcp`スコープグループを使用します。匿名のプレクレーム資格情報は、機能を発見し、公開統合ガイダンスを読み取ることができますが、サインインしたユーザーとしては扱われません。ブラウザ承認またはクレーム後、資格情報はユーザー範囲となり、各ツールはダッシュボードと同じ承認チェックを適用します。詳細については、<.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>を参照してください。

ツールは、認証済みユーザーがすでに読み取り可能なプロジェクトに解決されます。XcodeおよびGradleビルドツールは、ビルドUUIDまたはダッシュボードURLを受け入れます。UUIDは正確に1つのプロジェクトを識別する必要があります。複数のプロジェクトに表示される場合、ツールは別のプロジェクトのレポートを選択する代わりに「見つかりません」を返します。プロジェクトスコープのダッシュボードおよびAPI読み取りは引き続き利用可能です。報告されたアクター識別子は未検証のラベルであり、資格情報や追加のアクセス権ではありません。

ビルド一覧および詳細ツールは、オプションの`tuist_version`メタデータを公開します。XcodeおよびCargoの場合は報告元Tuist CLI、Gradleの場合はTuist Gradleプラグイン、Mixの場合は`tuist_ex`ライブラリです。Xcodeは、リンクされたプロジェクト生成イベントから`tuist_generation_version`も公開します。これはアップロード元のCLIと異なる場合があります。欠損している観測値はnullであり、サーバーや他のレポートから推論されることはありません。Bazelは既存の`bazel_version`を使用し、Onceの実行詳細は`once_version`を公開します。これらのフィールドは報告されたバージョンを表し、検証済みのIDやワイヤーコントラクトのバージョンではありません。RESTビルドエンドポイントも同じメタデータを公開します。既存の統合およびflaky-testスキルはバージョンフィールドに依存せず、ワークフローの変更は不要です。

Tuistオペレーターが顧客のアカウントを調査する際は、すべての呼び出しを記録するTuistの内部運用ツールを使用します。このエンドポイントへの直接接続では、ユーザー自身の所属範囲を超えるアクセス権は付与されません。

### Pulse

Pulseは2つの読み取り専用ツールを公開しており、どちらも`account_handle`で指定されます。

| ツール | `/api/accounts/:account_handle/pulse`以下のREST相当 |
| --- | --- |
| `query_pulse` | `GET /:signal` |
| `get_pulse_analytics` | `GET /:signal/analytics` |

Pulseは、アカウントまたはプロジェクトが公開されている場合でも、サーバー構成組織の現在のメンバーに制限されます。ユーザー認証、またはユーザーに関連付けられた`mcp`資格情報とアカウント読み取り権限が必要です。プロジェクトトークン、通常のアカウントトークン、匿名登録、および組織メンバーシップのないオペレーターアクセスでは、Pulseへのアクセスは付与されません。資格情報を使用して別のバックエンドやテレメトリーテナントを選択することはできません。ブラウザエージェントは、そのページのアカウントスコープ内にあるPulseページでのみ、これらのツールを受け取ります。

RESTにはユーザー資格情報が必要です。OAuthおよび`auth.md`ユーザー関連付けは`/mcp`エンドポイントでのみ利用可能です。関連するアカウントのメンバーシップや可視性に関係なく、現在のユーザーを持たないアカウント資格情報は拒否されます。

`query_pulse`は`signal`（`metrics`、`logs`、または`traces`）、オプションの`query`、および`range`（`15m`、`1h`、`6h`、または`24h`、デフォルト`1h`）を受け取ります。メトリクスはPromQL式を受け入れます。ログとトレースは、ログボディとスパン名に対してマッチングされる大文字小文字を区別しないリテラルテキストを受け入れます。`*`（デフォルト）はすべてを選択します。トレース行は個々のスパンです。テーブルは`search`、`page`（デフォルト`1`）、`page_size`（`1`–`100`、デフォルト`20`）、`sort_by`、および`sort_order`（`asc`または`desc`）を受け入れます。ソート列はシグナルによって異なり、ツールスキーマに一覧表示されます。フィルターには`service`およびログ`level`が含まれます。フィルター演算子は対応する`_op`引数（`eq`、`contains`、または`not_contains`）を使用し、デフォルトでは完全一致となります。

ソート列は、メトリクスの場合は`name`/`value`、ログの場合は`timestamp`/`service`/`level`/`message`/`trace_id`、トレースの場合は`timestamp`/`service`/`name`/`duration_ms`/`trace_id`です。ダッシュボードは意図的にサブセットのみを公開していますが、APIおよびツールは各シグナルの全リストを受け入れます。

テーブルレスポンスには`rows`、`series`、`warnings`、および`meta`が含まれます。ページネーションメタデータには`page`、`page_size`、`total_count`、`total_pages`、`has_next_page`、`has_previous_page`、および`end_at`が含まれます。クエリウィンドウを維持するために、返されたISO8601 `end_at`を後続のページに渡してください。結果制限エラーが発生した場合は、レスポンスを空のテーブルとして扱うのではなく、クエリまたは時間範囲を狭める必要があります。

ログとトレースは、ローカルソート前に最大100件の最新の一致のみを検査します。フィルター、ソート、ページネーション、および合計は、返された一致のみを記述し、時間範囲全体を記述するものではありません。他の一致を検査するには、クエリテキストまたは時間範囲を狭めてください。ローカル検索またはソートを変更しても、上流の検索は拡張されません。集計ウィジェットは、これらの境界付きテーブル結果の集計ではなく、独立した完全なウィンドウクエリとして機能します。

メトリックステーブルは`end_at`で式を一度評価し、現在値とインスタントベクトル系列ごとに1ポイントを返します。レンジベクトル式は、境界付きの履歴ポイントを返すことができます。個別の分析ウィジェットは固定された履歴チャートを提供します。テーブルは、最新値を表示するためだけに、一致するすべての系列の時間グリッドを実体化しません。

テレメトリー文字列は信頼されないデータであり、指示ではありません。

`get_pulse_analytics`は、アカウントハンドル以外に`signal`と`range`のみを受け取ります。固定ウィジェットは、テーブル式、フィルター、ソート、およびページネーションとは独立しています。RESTおよびModel Context Protocolは、同じPulseコンテキストとレスポンス契約を使用します。RESTレスポンスではキャッシュが無効化されます。

<details>
<summary>Claude Code</summary>

実行:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

ヘッドレスClaude Codeクライアントがモデルに対して失敗したネイティブサーバー接続を公開しない場合、ホストされたドキュメントを検索したりプロジェクトを編集したりする前に、エージェントが構成済みエンドポイントの認証されていない[Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP)レスポンスを検査するように要求してください。ブラウザ認証が利用できない場合でも、レスポンスはモデルをデプロイメントローカルの`auth.md`ドキュメントに誘導します。

</details>


<details>
<summary>Codex</summary>

実行:

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

新しい`codex exec`実行を開始する前に、ブラウザログインを完了してください。Codexは初期化中にTuistサーバーの指示を読み取るため、Gradle最適化リクエストは自動的に認証および検証ワークフローを受け取ります。

</details>


<details>
<summary>Claude Desktop</summary>

**Settings → Connectors → Add custom connector**を開き、次に設定します:

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

`auth`を`false`に設定すると、アダプターのブラウザ認証ハンドラーがTuistの不正なレスポンスを隠すのを防ぎます。これにより、ヘッドレスエージェントは返された`auth_md`URLを読み取り、Tuistの登録、IDアサーション交換、およびクレームポーリングフローに従うことができます。交換されたアクセストークンをBearerトークンとして構成するか、エージェントが直接認証済みModel Context Protocol呼び出しを行うようにします。

ブラウザ認証を優先する場合は、`auth`を`"oauth"`に設定してください。そのフローの場合、認証が完了するまでPiの[remote procedure call mode](https://pi.dev/docs/latest/rpc)で1つのプロセスを生かしておきます:

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

次に、サーバーを認証します:

```bash
opencode mcp auth tuist
```

</details>


<details>
<summary>Cursor</summary>

**Cursor Settings → Tools & Integrations → Model Context Protocol Tools**を開き、追加します:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

**Command Palette → MCP: Add Server**を使用し、次に[Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP)サーバーを以下のように構成します:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Agent panel → Settings → Add Custom Server**を開き、次に設定します:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

エージェントが`auth.md`をサポートしている場合、ブラウザを開かずに匿名で開始できます。信頼されたプロバイダーIDがすでにリンクされている場合、ブラウザなしで完了することもできます。サービス認証済みメール、匿名クレーム、または初回プロバイダーリンクの場合、エージェントはTuist検証リンクと6桁のコードを表示します。リンクを開き、サインインして、Tuistページでエージェントのコードを入力してください。コードを決してエージェントに送り返さないでください。Tuistの認可サーバーメタデータは、デプロイメント独自の`/auth.md`を直接指しており、そこには正確なリクエストおよびポーリング形状が含まれています。

## Amp orbsおよびClaude Codeクラウドセッション内のエージェント

Tuistアカウントに接続されたサンドボックスで実行されるコーディングエージェントは、ブラウザや保存されたTuist認証情報なしで、独自のIDトークンを使用してエンドポイントに認証できます:

- アカウントが**Settings → Integrations → Amp**の下で接続したAmpワークスペースまたはプロジェクトの**Amp orbs**は、orbのIDトークンを送信します。Ampでは、サーバーの`Authorization`ヘッダーを`Bearer ${amp:id-token}`に設定します。AmpはサーバーURLのオリジン用にトークンを発行するため、URLはこのTuistインスタンス自身のアドレスである必要があり、有効期限が切れる前に更新されます。別のオリジン用に発行されたトークンは拒否されます。
- 接続されたClaude Code環境の**Claude Code cloud sessions**は、Tuistが`TUIST_OIDC_TOKEN`として渡すセッショントークンを送信します。ヘッダーを`Bearer ${TUIST_OIDC_TOKEN}`に設定します。

TuistのLinuxサンドボックスにはこれが構成されています。Ampのユーザー設定とClaude Codeのユーザー構成の両方に`tuist`サーバーがあり、どちらも`${TUIST_URL}/mcp`を指しています。さらに、Tuist CLIと、エージェントにプロジェクトの履歴に対して結果を確認するタイミングを指示するスキルも含まれています。他の場所では、上記のヘッダーを使用してサーバーを手動で追加してください。

これらのトークンは、接続されたアカウントのすべてのプロジェクトへの読み取り専用アクセスを提供します。これらは`mcp`グループの読み取りスコープを持ち、テストのミュートやスキップなど、データの作成、変更、削除を行うスコープは持ちません。ワークスペースまたは環境を切断すると、次のリクエストでアクセスが停止し、アクセスはトークン自体の有効期間を超えて存続しません。複数のTuistアカウントに接続されたAmpワークスペースは、トークンが1つのアカウントを特定しないため拒否されます。接続が存在しない場合、不正なレスポンスの`error_description`にその旨が記載されます。

この読み取り専用アクセスはModel Context Protocolエンドポイントにのみ適用されます。同じサンドボックス内のコマンドラインツールとビルドシステム統合は、引き続きトークンを交換して接続のCIアクセスを行います。

## WebMCP

[WebMCP](https://webmachinelearning.github.io/webmcp)をサポートするブラウザでは、Tuistのページが`document.modelContext`でツールを登録するため、ブラウザに組み込まれたエージェントは追加の構成なしでそれらを呼び出すことができます。呼び出しはTuistサーバー上で実行されます。

- **Website and documentation pages**は、ドキュメントおよびソースツール（`search_tuist`、`search_tuist_code`、`list_tuist_files`、および`read_tuist_file`）を登録します。サインインは不要です。
- サインインしている場合、**An account's dashboard pages**はそのアカウント用のTuist読み取り専用ツールを登録します。各ページは、表示内容とプロジェクトのビルドシステムに応じたツールのみを登録します。GradleプロジェクトのビルドページはGradleビルドツールを取得し、テストページはテストおよびカバレッジツールを取得し、ランナーページはランナーツールを取得し、サンドボックスページはサンドボックストールを取得します。個人アカウントのAI設定ページのSubscriptionsセクションは`list_ai_subscriptions`を取得しますが、これは自分のアカウントに対してのみ回答します。すべてのページはまた、ドキュメントツールである`list_projects`および`get_project`も取得します。ツールはサインインしたユーザーとして実行されるため、ダッシュボードで読み取れるデータと、現在閲覧しているアカウントのみにアクセスできます。別のページまたはアカウントに移動すると、ツールはそのページのツールに置き換えられます。

データを作成、変更、または削除するツールはWebMCPでは利用できません。ブラウザエージェントはユーザーが追加することなくツールを受け取り、ビルドおよびテストが生成するコンテンツを読み取るためです。これらのツールを使用するには、MCPクライアントを`/mcp`エンドポイントに接続してください。

組織がシングルサインオンを強制している場合は、そのプロバイダーを使用してダッシュボードにサインインし、ツールを使用してください。

## ビルドシステム統合は2つの認証情報を使用します

Model Context Protocolツールに使用される認証情報は、GradleプラグインやBazelのリモートサービスを認証しません。エージェントがGradleまたはBazel統合を編集または検証する前に、次を実行する必要があります:

```bash
tuist auth whoami --url https://tuist.dev
```

そのコマンドが認証されていない場合、エージェントは停止し、ユーザーに次を実行するよう依頼する必要があります:

```bash
tuist auth login --url https://tuist.dev
```

ローカルまたはセルフホスト型デプロイメントの場合、両方のコマンドおよび`tuist.toml`内のURLを置き換えてください。ホスト名のスペルは everywhere で同一に保ってください。例えば、`localhost`と`127.0.0.1`は別々の保存された認証情報を使用します。


## 機能

### ツール

以下のツールはTuist Model Context Protocolサーバーを通じて利用できます:

すべてのツールは、人間が読める説明とともに明示的な入力および出力スキーマを公開します。正常な呼び出しは、公表された出力スキーマに準拠した構造化コンテンツを返し、さらに構造化コンテンツをまだ消費しないクライアント向けにテキストとしてシリアライズされた同じ結果を返します。

`build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id`、または`cache_run_id`など、単一レコードの識別子を取るツールは、そのレコードのTuistダッシュボードURLも受け入れます。識別子を抽出するのではなく、ブラウザからURLを直接貼り付けてください。

`get_xcode_build`、`get_test_run`、`get_gradle_build`、および`get_project`には`side_quests`を含めることができます。これは、プロジェクトが使用していないものの、レコードが役立つと示すTuist機能です。それぞれに`id`、証拠を示す`tip`、および`docs`リンクがあります。エージェントはまずユーザーのリクエストを完了し、該当するサイドクエストに言及し、ユーザーが同意した場合にのみ1つを実行するように求められます。これらは、ユーザーセッション、MCPトークン、またはエージェントIDで接続するかにかかわらず、プロジェクトのアカウントのメンバーにのみ返されます:

| ID | ツール | 推奨時期 |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | Xcode 26以降で処理されたクリーンビルドが、キャッシュ可能なコンパイルタスクを実行しませんでした。 |
| `gradle_build_cache` | `get_gradle_build` | ビルドがキャッシュ可能なタスクを実行しましたが、Gradleのビルドキャッシュがいずれのタスクに対してもキーを計算しませんでした。これは、ビルドキャッシュが無効になっていたことを意味します。 |
| `flaky_test_quarantine` | `get_test_run` | 実行に不安定なテストが含まれており、プロジェクト内の有効な自動化がそれらをミュートまたはスキップしていません。Onceプロジェクトでは推奨されません。 |
| `test_sharding` | `get_test_run` | Tuistがシャード化できるビルドシステムにおいて、シャード化されていないCI実行が10分以上かかりました。ヒントには、選択的テストがいつどれだけ多くのテストをすでにスキップしたかが示されます。 |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | CI実行がGitHub Actions、Bitrise、GitLab CI、またはBuildkiteのマシンを使用しており、そのアカウントはTuist Runnersでジョブを実行したことがありません。tuist.devのみで利用可能です。 |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | GitHub Actionsの実行が、GitHubリポジトリに接続されていないプロジェクトに属しています。 |
| `other_build_systems` | `get_project` | アカウントが、サポートされているすべてのビルドシステムでTuistを使用していません。ヒントには、他のビルドシステムを識別するファイルが一覧表示されるため、エージェントがリポジトリを確認できます。 |

#### ドキュメントおよびコミュニティ検索

この読み取り専用ツールは、ドキュメントウェブサイトと同じ検索エンジンを使用して、Tuistのドキュメント、[アプリケーションプログラミングインターフェース](https://en.wikipedia.org/wiki/API)リファレンス、GitHubリリース、コミュニティフォーラム、およびGitHubイシューを検索します。リリース結果には、製品、バージョン、公開日、プレリリースステータスが含まれます。デフォルトでは安定版リリースが検索され、`include_prereleases`を使用してプレリリースを含めることができます。このツールは、`https://tuist.dev/mcp`にあるTuistホストサーバーでのみ利用可能です。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `search_tuist` | 公開されているTuistドキュメント、アプリケーションプログラミングインターフェースリファレンス、GitHubリリース、コミュニティディスカッション、およびGitHubイシューを検索します。オプションで、1つの`source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）に制限できます。 | `query` |

#### フィードバック

エージェントは、Tuistツールやプロンプトが期待通りに動作しなかった場合（結果が混乱を招く、エラーが発生する、データが欠落している、機能が不足しているなど）、Tuistチームに通知できます。エージェントはレポートを提案し、ユーザーが同意した場合にのみ送信するように求められます。各レポートはTuistサポートとの会話を開始し、サポートからメールで返信される場合があります。レポートには、エージェントの期待値、実際の発生事象、オプションの提案、あなたのTuistユーザーID、ハンドル、メールアドレス、および所属組織が含まれます。エージェントは問題が発生したアカウントとプロジェクトを指定することもでき、チームはどの組織に対応すべきかを把握できます。受け入れられるのは、あなたが所属しているアカウントのみです。Tuistユーザーとしてサインインしているエージェントのみがレポートを送信でき、各ユーザーは1時間あたり最大10件のレポートを作成できます。このツールは、`https://tuist.dev/mcp`にあるTuistホストサーバーでのみ利用可能です。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `report_feedback` | Tuistツールまたはプロンプトに関する問題を報告します。オプションで、`tool_name`、問題が発生した`account_handle`および`project_handle`を指定し、`suggestion`を追加できます。 | `category`, `expected`, `actual` |

#### ソースに基づく回答

これらの読み取り専用ツールにより、エージェントはホストサーバーとともにデプロイされた正確な公開Tuistソースリビジョンを、現在の動作に依存する回答のための信頼できる情報源として使用できます。これらは`https://tuist.dev/mcp`でのみ利用可能です。

互換性のあるクライアントは、初期化中にツールのソースリビジョン、リンク、結果制限に関する事実上の説明を、インラインOAuth認証情報とともに受け取ります。これらの説明は、回答スタイルや検証ワークフローを規定するものではありません。ユーザーは、まず`ask_tuist`プロンプトを呼び出さずに直接質問を行うことができます。このプロンプトは、明示的なソースに基づくワークフローのために引き続き利用可能です。

すべての操作には、並行処理、期間、トラバーサル、読み取りバイト数、およびレスポンスサイズに対する固定制限があります。検索および一覧結果には、`truncated`および`truncation_reason`フィールドが含まれます。結果が切り捨てられた場合は、結果を網羅的なものとして扱うのではなく、パス、ファイルパターン、または検索語句を絞り込んでください。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `search_tuist_code` | ソースファイルを検索することで、現在の動作、デフォルト、構成、機能ゲート、エラー処理、または文書化されていない詳細に関する質問に回答します。結果には、周囲の行、リビジョン固定ソースリンク、およびスキャン統計が含まれます。 | `pattern` |
| `list_tuist_files` | 関連するパスが不明な場合に、ソースサブシステムまたは近隣のテストを発見します。一覧表示には深度と結果数の上限があります。 | なし |
| `read_tuist_file` | 関連するパスを見つけた後、実装ファイル、呼び出しサイト、またはテスト内の特定の行範囲を検査します。切り捨てられたレスポンスには、継続のための`next_start_line`が提供されます。 | `path` |

#### プロジェクト

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_accounts` | 認証済みユーザーが利用可能な個人および組織アカウントのハンドルを一覧表示します。各アカウントがプロジェクトを作成できるかどうかも含みます。 | なし |
| `get_organization` | 組織のメンバーディレクトリを取得します。保留中の招待には、ダッシュボードと同じ管理者権限が必要です。招待受諾トークンは返されません。 | `account_handle` |
| `create_organization` | 認証済みユーザーのためにTuist組織を作成します。 | `handle` |
| `create_project` | 認証済みユーザーがアクセスできるアカウントの下にTuistプロジェクトを作成します。 | `account_handle`, `project_handle` |
| `add_organization_member` | 既存のTuistユーザーを組織に追加するか、既存のメンバーの役割を更新します。`user`（デフォルト）、`admin`、または`viewer`を受け入れます。ビューアーはダッシュボードと実行を読み取ることができますが、何も変更することはできません。 | `organization_handle`, `email` |
| `invite_organization_member` | 既存のTuistユーザーに属しているかどうかにかかわらず、メールアドレスを組織に招待します。Tuistは14日後に期限切れになる受諾リンクをメールで送信します。サーバーがメールを送信できない場合、`email_sent`は`false`になり、リンクをダッシュボードからコピーする必要があります。`user`（デフォルト）、`admin`、または`viewer`を受け入れます。組織管理者権限が必要です。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 保留中の組織招待をキャンセルし、そのリンクを受け付けられないようにします。組織管理者権限が必要です。 | `organization_handle`, `email` |
| `list_projects` | 認証済みユーザーがアクセスできるすべてのプロジェクトを一覧表示します。 | なし |
| `get_project` | プロジェクトの構成と接続されたリポジトリのURLを取得します。 | `account_handle`, `project_handle` |
| `connect_project_repository` | アカウントのGitHub AppインストールがアクセスできるGitHubリポジトリにプロジェクトをリンクします。プロジェクトはリポジトリのデフォルトブランチを採用します。プロジェクト管理者権限が必要です。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | プロジェクトからGitHubリポジトリへのリンクを削除します。プロジェクト管理者権限が必要です。 | `account_handle`, `project_handle` |

#### アカウントトークン

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_account_tokens` | トークンの値を公開せずに、アカウントトークンのメタデータを一覧表示します。 | `account_handle` |
| `get_account_token` | トークンの値を公開せずに、アカウントトークンのメタデータを取得します。 | `account_handle`, `token_id` |
| `list_project_tokens` | トークンの値を公開せずに、プロジェクトトークンのメタデータを一覧表示します。 | `account_handle`, `project_handle` |

#### AIサブスクリプション

これらのツールは、スレッドなどのAI機能向けに、認証済みユーザー自身のClaudeおよびChatGPTサブスクリプションを管理します。ユーザー認証とAI機能へのアクセスが必要で、接続メタデータのみを返し、認証情報は決して返しません。切断すると保存された認証情報は削除されますが、プロバイダーでの認可は取り消されません。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_ai_subscriptions` | 各サブスクリプションが接続されているかどうか、およびサーバーがそれを接続できるかどうかを一覧表示します。 | なし |
| `connect_claude_subscription` | `claude setup-token`が出力するサブスクリショントークンを保存します。トークンはクライアントとモデルを通過する秘密情報であるため、明示的にのみ提供してください。ダッシュボードのAI設定に貼り付けると、会話に含まれなくなります。 | `token` |
| `start_chatgpt_subscription_login` | OpenAIデバイスサインインを開始し、ユーザーが入力する検証URLとコード、および`login_id`を返します。15分後に期限切れになります。 | なし |
| `poll_chatgpt_subscription_login` | 保留中のサインインを確認します。ユーザーがコードを承認するまで`pending`、その後`connected`になります。 | `login_id` |
| `cancel_chatgpt_subscription_login` | 保留中のサインインをキャンセルします。接続済みのサブスクリプションは接続されたままです。 | `login_id` |
| `disconnect_ai_subscription` | サブスクリプションの保存された認証情報と保留中のサインインを削除します。 | `provider` |

#### 通知ルール

これらのツールは、認証済みユーザー自身の通知ルールを管理します。新しいプレビューなどのイベントがルールのプロジェクト（リストされていない場合は通知可能な任意のプロジェクト）で発生し、条件を満たすと、Tuistアプリデバイスへのプッシュ通知などのアクションを実行します。ルールがないと通知は受信できません。ユーザー認証が必要で、自分のルールに対してのみ動作し、自分が所属するアカウントのプロジェクトのみを受け入れます。ルールはすべてのアカウントにまたがるため、ダッシュボードページでは提供されません。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_notification_events` | ルールがサブスクライブできるイベントタイプを一覧表示します。各タイプには、その条件用のJSON Schemaが含まれています。 | なし |
| `list_notification_condition_options` | プロジェクト内のイベントに対する条件値を提案します。例えば、最近のプレビューのトラックやブランチなどです。 | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 自分のルールを一覧表示します。 | なし |
| `create_notification_rule` | イベント、オプションのプロジェクトと条件、および少なくとも1つのアクションからルールを作成します。 | `event`, `actions` |
| `update_notification_rule` | ルールの有効状態、プロジェクト、条件、またはアクションを変更します。 | `rule_id` |
| `delete_notification_rule` | ルールを削除します。 | `rule_id` |

#### 継続的インテグレーションランナー

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_runner_jobs` | アカウントの継続的インテグレーションランナージョブを一覧表示します。 | `account_handle` |
| `get_runner_job` | 継続的インテグレーションランナージョブを取得します。マシンのメモリ不足、停止した処理、変更すべき事項が含まれます。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 継続的インテグレーションランナージョブに記録されたステップを一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 継続的インテグレーションランナージョブに記録されたマシンメトリクスを一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 継続的インテグレーションランナージョブのキャプチャされたログ行を最大500件まで一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | アカウントの継続的インテグレーションワークフロー集計を一覧表示します。 | `account_handle` |
| `list_runner_profiles` | アカウントの継続的インテグレーションランナープロファイルと、各プロファイルの`runs-on`ラベルを一覧表示します。 | `account_handle` |
| `get_runner_catalog` | ランナープロファイルが使用できるマシンシェイプとXcodeバージョンを一覧表示します。 | `account_handle` |
| `create_runner_profile` | プラットフォーム、マシンシェイプ、macOSの場合はXcodeバージョンを指定してランナープロファイルを作成します。オプションで、キャッシュボリュームを保存するブランチを設定できます。アカウント管理権限または`account:runners:write`スコープが必要です。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | ランナープロファイルのマシンシェイプ、Xcodeバージョン、またはカスタムキャッシュボリュームの変更を保存するブランチを変更します。省略されたフィールドは値を保持します。アカウント管理権限または`account:runners:write`スコープが必要です。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | ユーザーの確認後にランナープロファイルを削除します。デフォルトのプロファイルは削除できません。アカウント管理権限または`account:runners:write`スコープが必要です。 | `account_handle`, `profile_name` |

ランナーボリュームツールは、Volumesダッシュボードと同じデータを公開します。読み取りツールにはランナーアクセスが必要で、クリアにはアカウント管理権限または`account:runners:write`スコープ、およびユーザーの確認が必要です。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_runner_volumes` | 名前とリポジトリでフィルタリングし、ボリュームをソートおよびページネーションします。 | `account_handle` |
| `get_runner_volume` | リポジトリ、プラットフォーム、容量、使用済みスペース、最終使用日時。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | ページネーションされたジョブおよびワークフロー参照、キャッシュステータス、ヒット結果、マウント時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | ジョブによってマウントされたボリューム。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | ストレージ時系列、ジョブ実行、ヒット率、トレンド。オプションで`volume_id`、`start`、`end`（ISO 8601）。デフォルトは7日間、最大90日間。 | `account_handle` |
| `delete_runner_volume` | ボリュームとその保存されたコンテンツを削除します。実行中のジョブはプライベートコピーを保持しますが保存はできず、同じキーを持つ後続のジョブは空の状態で開始されます。 | `account_handle`, `volume_id` |

リストは`page`および`page_size`（最大100）を受け入れます。ボリュームインベントリは`name`および`repository`（完全一致、AND結合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）、`sort_order`（`asc`、`desc`）も受け入れます。不明な測定値とヒット結果は`null`のままです。キャッシュステータスはボリュームの変更が保存されたかどうかを示し、ジョブの成功を示すものではありません。

#### サンドボックス

サンドボックストールは、Sandboxesダッシュボードと同じデータとアクションを公開し、[API](https://tuist.dev/api/docs)と同じアクセス権を持ちます。アカウントメンバーはサンドボックスの一覧表示、取得、作成、一時停止、再開、削除を行えますが、エージェント環境、Amp、リモート実行を提供するサンドボックス、および分析・アーカイブツールにはアカウント管理権限が必要です。読み取り専用ビューアーは使用できません。アカウントでサンドボックスが有効になっている必要があります。ダッシュボードのサンドボックスページは読み取り専用ツールを登録します。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_sandboxes` | ステータス、シェイプ、タイムスタンプを含むサンドボックスをページネーションします。オプションで`search`（サンドボックス内のテキスト、Amp Orb、またはAnthropicセッションID）、`status`、`vcpus`、`sort_by`（`created`、`last_active`、`identifier`）、`sort_order`。 | `account_handle` |
| `get_sandbox` | サンドボックスのステータス、シェイプ、ノード、アーカイブ、タイムスタンプ。 | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU時間、作成されたサンドボックス数、セッション、セットアップ、開始までの所要時間、およびアカウント制限に対するピークvCPU、メモリ、ディスク使用量とトレンド。オプションで`start`および`end`（ISO 8601）。デフォルトは30日間、最大90日間。 | `account_handle` |
| `create_sandbox` | 最小構成のサンドボックスを起動し、実行開始後に返します。オプションで`platform`（`linux`または`darwin`）、`template`、`memory_mb`付きの`vcpus`（Linux: 2x4096、4x8192、8x16384、デフォルト2x4096。macOS: 8x8192、8x16384、8x24576、デフォルト8x8192）、`workspace_gb`。 | `account_handle` |
| `pause_sandbox` | 実行中のサンドボックスをそのノードのディスクにスナップショットします。 | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 一時停止中またはアーカイブ済みのサンドボックスを再開します。 | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 一時停止中のサンドボックスのディスクをオブジェクトストレージに移動するようキューに登録します。 | `account_handle`, `sandbox_id` |
| `delete_sandbox` | ユーザーの確認後にサンドボックスとそのディスクを削除します。 | `account_handle`, `sandbox_id` |

#### Ampワークスペース

これらのツールは、OrbがトークンなしでTuistにサインインできるようにする<.localized_link href="/guides/server/authentication#amp-orbs">Ampワークスペース接続</.localized_link>を管理します。ダッシュボードのIntegrationsページと同じ管理者専用権限を使用します。Orb内のエージェントは`$AMP_WORKSPACE_ID`および`$AMP_PROJECT_ID`から自身のIDを読み取れます。接続が許可するすべてのOrbはアカウント内のすべてのプロジェクトへのCIアクセス権を得るため、エージェントは接続前にユーザーに確認すべきです。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | アカウントに接続されているAmpワークスペースと、それぞれが制限されているプロジェクト（存在する場合）を一覧表示します。 | `account_handle` |
| `connect_amp_workspace` | Ampワークスペースを接続します。オプションの`project_id`により、サインインを1つのAmpプロジェクトのOrbに限定できます。 | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | ワークスペースを切断します。そのOrbが既に持っているセッションは、有効期限まで有効です。 | `account_handle`, `connection_id` |

#### Claude環境

これらのツールは、Claude Managed Agentsのセルフホスト環境を接続し、Settings → Integrations → Claudeと同様に、Tuistサンドボックスでセッションを実行します。アカウント管理権限とサンドボックスの有効化が必要です。エージェントはAnthropicのAPIを使用して環境を作成できますが、環境キーを生成できるのはClaude Consoleのみであるため、エージェントはユーザーにそれを求めます。TuistはAnthropic APIキーまたはワークロードIDフェデレーションを使用してセッションを開始し、その資格情報で環境を取得してから保存します。Anthropic側のセットアップにはユーザー自身のAnthropic資格情報が使用され、Tuistがそれらを受け取ることはありません。キーはクライアントとモデルを通過するため、明示的に提供してください。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_claude_environments` | 接続された環境と各環境が使用する資格情報、およびフェデレーションルールが信頼すべき発行元URLとサブジェクトプレフィックスを一覧表示します。 | `account_handle` |
| `connect_claude_environment` | `api_key`を使用して、または`organization_id`、`workspace_id`、`service_account_id`、`federation_rule_id`を使用して環境を接続します。オプションの`platform`、`vcpus`、`memory_mb`でサンドボックスのシェイプを設定します。 | `account_handle`, `environment_id`, `environment_key` |

#### Webhook

Webhookツールは、ダッシュボードと同じ管理者専用権限を使用します。配信試行にはエンドポイント用に記録されたリクエストおよびレスポンスデータが含まれますが、エンドポイントの署名シークレットは含まれません。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_webhook_endpoints` | アカウントのWebhookエンドポイントを一覧表示します。 | `account_handle` |
| `get_webhook_endpoint` | Webhookエンドポイントを取得します。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | エンドポイントの配信試行を一覧表示します。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 配信試行を取得します。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcodeビルド

Xcode、Gradle、Bazel、Mix、Cargo向けのビルド詳細ツールは、既存の`custom_metadata: {tags, values}`構造を公開し、報告された場合はインフラストラクチャ観測値も含みます。値は文字列のまま保持され、不明なキーも保存されます。例えば、`tuist.cpu.available_processors`はランタイム時に利用可能な論理プロセッサ数を示し、`tuist.gradle.max_workers`はGradleワーカーの上限、`tuist.jvm.max_heap_bytes`はJVMヒープの上限であり、ホストメモリではありません。これらは信頼されていないクライアント観測値であり、検証済みのランナーIDではありません。欠落している観測値は欠落したままとなり、インポートされたログや古いクライアントにはインフラストラクチャメタデータがない場合があります。メタデータの更新は、調整されたクライアント/プロトコルのアップデートを待っています。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_xcode_builds` | プロジェクトのXcodeビルド実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 特定のXcodeビルド実行に関する詳細情報を取得します。これには、生の`.xcactivitylog`を含むアーカイブの一時的なダウンロードURLが含まれます。 | `build_run_id` |
| `list_xcode_build_targets` | 特定のXcodeビルド実行のビルドターゲットを一覧表示します。 | `build_run_id` |
| `list_xcode_build_files` | 特定のXcodeビルド実行のコンパイル済みファイルを一覧表示します。 | `build_run_id` |
| `list_xcode_build_steps` | ログテキストを除く、タイミングと結果付きの記録済みビルドステップを一覧表示します。 | `build_run_id` |
| `get_xcode_build_step` | ログと切り捨てフラグを含む、記録済みのビルドステップを1つ取得します。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 特定のビルド実行のビルド問題（警告とエラー）を一覧表示します。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 特定のXcodeビルド実行のキャッシュ可能タスク（キャッシュヒット/ミス）を一覧表示します。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 特定のXcodeビルド実行の[コンテンツアドレサブルストレージ](https://en.wikipedia.org/wiki/Content-addressable_storage)出力を一覧表示します。 | `build_run_id` |

`list_xcode_build_steps`はデフォルトで20ステップのページを返します（`page_size`で最大100）。ナビゲーションには`page`と`pagination_metadata`を使用します。`search`を使用してタイトル、プロジェクト、またはターゲットを一致させるか、正確な`project`、`target`、`category`（例：`swiftCompilation`）、および`status`（`success`または`failure`）でフィルタリングします。`duration_ms`でソートすると遅い順（デフォルト）、`start_ms`でソートすると時系列順になります。ステップIDは同順位を解消し、64ビット精度を完全に保持するために10進数文字列として返されます。IDはビルドごとにスコープされており、ビルド間で一致させてはいけません。

オプションの`start_ms`と`end_ms`は、ビルド開始からのミリ秒単位の時間範囲と重複するステップを選択します。終了時間は除外されます。両方のツールは、ビルドUUIDまたはダッシュボードURLを`build_run_id`として受け入れます。返されたステップ`id`を変更せずに`step_id`として渡し、そのログを取得します。ログはステップあたり最大64 KiB保持され、`log_truncated`によって省略された出力を示します。

Xcodeビルドが処理される際、ステップはデフォルトで収集されます。記録されたステップデータは90日間保持されます。リストレスポンスには`availability`が含まれます。記録されたステップが存在する場合は`available`（フィルタが何も一致しない場合でも）、ビルドがまだ処理中でステップがない場合は`processing`、ステップが記録されていないか有効期限切れの場合は`unavailable`。

同じ操作はHTTP APIの`GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps`および`GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}`で利用でき、同じフィルタとページネーションをサポートします。どちらもビルドのプロジェクトへの読み取りアクセス権が必要です。

#### Gradleビルド

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 認証、プロジェクト設定、Gradleプラグイン、キャッシュポリシー、および2回ビルドによる検証ワークフローの全体を返します。エージェントは、既存のAndroidまたはGradleプロジェクトを編集する前にこれを呼び出す必要があります。 | なし |
| `list_gradle_builds` | プロジェクトのGradleビルド実行を一覧表示し、カスタムメタデータを含めます。オプションの`tag`パラメータを使用してカスタムタグでフィルタリングします。 | `account_handle`, `project_handle` |
| `get_gradle_build` | ビルドメタデータ、タスク/キャッシュのカウント、および`failures`（各失敗したタスクと構成ステップの失敗メッセージ）を取得します。 | `build_run_id` |
| `list_gradle_build_tasks` | タスクの結果、複合ビルドID、キャッシュ可能性、増分ステータス、および失敗メッセージを一覧表示します。 | `build_run_id` |
| `list_gradle_build_steps` | 検索、メタデータ、および重複する時間フィルタを使用して、時間計測されたタスク、構成、および変換を一覧表示します。 | `build_run_id` |
| `get_gradle_build_step` | 不透明なIDによって記録されたステップメタデータを検査します。失敗したタスクまたは構成ステップの`log`は、その失敗メッセージです。 | `build_run_id`, `step_id` |

GradleおよびBazelのステップリストはデフォルトで20件の結果を返し（最大100件）、`search`、正確な`project`、`target`、`category`、および`status`、重複する`start_ms` / `end_ms`フィルタ（終了は除外）、および`duration_ms`または`start_ms`でのソートをサポートします。返されたIDは変更せずに渡してください。これらはビルドごとにスコープされています。リストは`time_origin`および`coverage`を公開します。古いGradleレポートは、ビルド開始がアップロードされていないため`first_recorded_timestamp`を使用します。Bazelプロファイルは、`trace_profile`カバレッジと時間原点としての`profile_start`ですべての記録された間隔を公開します。古いビルドは保持されたBEPサマリーにフォールバックします。ソースレコードは90日後に有効期限切れになります。Bazelの詳細には、公開されている場合にサニタイズされたアクションログが含まれます。失敗したタスクまたは構成ステップのGradle詳細には、Tuist Gradleプラグインが`log`として報告した失敗メッセージ（例外メッセージとその原因チェーン。Gradleのコンソールでの出力と同様ですが、スタックトレースやタスク出力は含まず、プロジェクト内のパスは相対パス化され、認証情報やその他のローカルパスは編集されています。ステップあたり最大16 KiB、ビルドあたり最大32件の失敗ステップ）が含まれます。他のGradleステップ、古いプラグインバージョンによって報告されたビルド、および認証情報なしのレポートでは`log`はnullです。構成ステップは、失敗した場合に`failure`を、それ以外の場合は`unknown`を報告します。`compare_builds`プロンプトはこのカバレッジを使用して、完全なBazelトレースと保持されたサマリーを区別し、より広範な呼び出し出力を確認する前に、エージェントをアクションの結果とログのためのステップ詳細へ誘導します。

単一ステップツール`get_gradle_build_step`および`get_bazel_build_step`はIDによってステップを取得し、時間フィルタを受け入れません。時間範囲でステップをフィルタリングするには、対応するリストツールを使用してください。

保持されたサマリーから返されたBazelステップIDは、リスト取得とステップフェッチの間に完全なプロファイルが到着した場合でも読み取り可能です。ステップデータの有効期限が切れたインデックス付きプロファイルは利用不可を報告します。Gradleステップリストには、ゼロ期間のキャッシュ済みおよびスキップされた操作が含まれます。

#### Bazel呼び出し

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 認証、プロジェクト設定、Bazel構成、および検証ワークフローを返します。 | なし |
| `list_bazel_invocations` | 完了した[Bazel Build Event Protocol](https://bazel.build/remote/bep)呼び出しを新しい順に一覧表示し、ビルドメトリクス、制限された実行タイムライン、クリティカルパス診断、およびプロジェクトに関連付けられたリモートキャッシュの合計を含めます。`status`、`git_branch`、`git_commit_sha`、`is_ci`、および`command`でフィルタリングします。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | ビルドメトリクス、制限された実行タイムライン、クリティカルパス診断、および関連付けられたリモートキャッシュの合計を含む、完了したBazel呼び出しを1つ取得します。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | フィルタと明示的なカバレッジを使用して、記録されたBazelプロファイル間隔を一覧表示します。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 記録されたBazelステップと、その公開されたアクションの結果およびサニタイズされたログを検査します。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | Bazel呼び出しのためにキャプチャされたサニタイズされたログを実行順に一覧表示します。Bazelの進捗出力の制限された末尾と`test.log`アーティファクトです。オプションの`stream`（`stdout`または`stderr`）、`source`（`progress`または`test_log`）、`target_label`、および`errors`フィルタで結果を絞り込みます。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bazel呼び出しのためにキャプチャされたサニタイズされたログチャンクを1つ取得します。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 操作、エンドポイント、および観測時間を含む生のBazelリモートキャッシュ観測を一覧表示し、オプションで呼び出し、結果、または操作に絞り込むことができます。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 生のBazelリモートキャッシュ観測を1つ取得します。 | `account_handle`, `project_handle`, `cache_event_id` |

`list_bazel_invocations`フィルタは完全一致であり、同じ秒で終了する呼び出しは呼び出しIDで順序付けられます。ブランチ上の最新の失敗した呼び出しを見つけるには、`status: "failure"`、`git_branch`、および`page_size: 1`を指定して呼び出します。RESTエンドポイント`GET /api/projects/{account_handle}/{project_handle}/bazel/invocations`も同じフィルタを受け入れます。

テストログには、由来するテスト結果の`target_label`および試行`status`が含まれているため、`target_label: "//foo:bar_test"`はそのターゲットのテストログのみを返します。`errors: true`は、失敗した試行のテストログと、Bazelのレポーターが`ERROR:`、`FAIL:`、または`TIMEOUT:`で始まる行を含むstderr進捗チャンクを返します。進捗出力はターゲットに帰属せず、帰属が記録される前に書き込まれたログは空のフィールドを持ちます。失敗したアクションとその出力は、`list_bazel_build_steps`からターゲットごとに利用でき、テストケースごとの失敗はテスト実行ツールから利用できます。

#### Cargoビルド

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_cargo_builds` | プロジェクトのCargoビルドを新しい順に一覧表示します。`git_branch`、`status`、`is_ci`、または`command`でフィルタリングします。Cargoテスト実行の結果は、このビルド一覧ではなく、テストツールを通じて利用できます。 | `account_handle`, `project_handle` |
| `get_cargo_build` | ビルドメタデータ、集計キャッシュカウンタ、および診断情報付きで最大500件の記録されたコンパイラジョブを取得します。`compilations_truncated`は省略されたジョブを示します。診断情報は返されたジョブのみを対象とします。 | `account_handle`, `project_handle`, `build_id` |

`get_cargo_build`で`include_cache_inspection: true`を設定し、検証されたタスクの決定とCAS操作を4 MBの制限内で取得します。デフォルトでは、またレコードが存在しないか無効な場合、`cache_inspection`はnullです。部分キャプチャの`truncated`フラグを尊重してください。転送は各タスクヒットのローカル/リモートの起源を確立しません。HTTP詳細エンドポイントも同じクエリパラメータを受け入れます。

#### Mixビルド

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_mix_builds` | プロジェクトのMix（Elixir）コンパイルビルドを新しい順に一覧表示し、カスタムメタデータを含めます。`git_branch`、`status`、`is_ci`、または`mix_env`でフィルタリングします。 | `account_handle`, `project_handle` |
| `get_mix_build` | ビルドメタデータ、診断カウント、および依存関係キャッシュの概要を取得します。 | `account_handle`, `project_handle`, `build_id` |

#### ビルドトレース

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `get_build_trace` | Xcode、Gradle、Bazel、またはMixビルドのタイムラインを、[Perfetto](https://ui.perfetto.dev)で開けるトレースファイルとしてダウンロードするリンクを取得します。 | `account_handle`, `project_handle`, `build_id` |

`build_id`はビルド実行ID（Bazelの場合は呼び出しID）またはビルドのダッシュボードURLです。返される`trace_url`は[Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSONファイルを提供します。リンクを持っている人は誰でも、他の認証情報なしで、呼び出しから1時間後の`expires_at`まで、そのビルドのトレースをダウンロードできます。エージェントは`curl`でダウンロードし、あなたがPerfettoで開けるように渡すか、Perfettoの`trace_processor`でクエリできます。トレースには、並列性によってレーンにパックされた記録されたステップ、ビルド全体にわたるトラック、およびビルドがマシンのメトリクスを記録した場合のCPUとメモリのカウンタが含まれます。ログを除き、上記のステップツールと同じデータを保持します。ダッシュボードでは、各ビルドのタイムラインタブから同じファイルを提供しています。

#### Once runs

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_once_runs` | プロジェクトのOnce runを新しい順に一覧表示します。`kind`（`build`、`test`、または`generic`）、`status`、`is_ci`、または`git_branch`でフィルタリングします。完了していないrunのステータスは`in_progress`です。 | `account_handle`, `project_handle` |
| `get_once_run` | アクションの合計、キャッシュの概要、およびテスト実行の場合はテストの合計を含むrunを取得します。 | `account_handle`, `project_handle`, `run_id` |

Cargoビルド、Mixビルド、およびOnce runのIDはプロジェクト内で一意です。同じ読み取りは、HTTP APIの`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds`、および`.../once/runs`で利用可能であり、それぞれが1つのIDに対する詳細エンドポイントを持っています。

#### タスク、アクション、モジュール、ファイル

これらのプロジェクトスコープのツールは、実行間で永続的なビルド識別子を検査します。`list_build_entities`から始め、返された安定した`id`と同じ`kind`を`get_build_entity`または`list_build_entity_history`に渡し、`account_handle`と`project_handle`も一緒に指定します。ビルドまたは呼び出しの識別子は必要ありません。

| ツール | 説明 | 必須パラメータ |
| --- | --- | --- |
| `list_build_entities` | プロジェクトのビルド全体で見られる、ある種類のタスク、モジュール、アクション、またはファイルを一覧表示します。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 選択した期間のネイティブ識別子と分析情報を含む1つのビルドエンティティを取得します。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 1つのビルドエンティティの記録された実行、コンパイル、またはキャッシュイベントを新しい順に一覧表示します。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | ツールチェーン | 履歴リスト |
| --- | --- | --- |
| `bazel_actions` | Bazelアクション | BEPで報告されたアクション実行 |
| `gradle_tasks` | Gradleタスク | タスク実行 |
| `xcode_modules` | Xcodeモジュール | コンパイルとモジュールキャッシュイベント |
| `once_actions` | Onceアクション | 実行 |
| `mix_files` | Mixコンパイル済みファイル | コンパイル |
| `mix_modules` | Mixコンパイル済みモジュール | コンパイル |
| `cargo_crates` | Cargoクレート | 記録されたrustc呼び出し |

これらのツールは段階的に展開されており、有効になっているプロジェクトのデータのみを返します。他のプロジェクトでは、空の結果ではなくエラーが返されます。種類は、そのビルドツールチェーンを使用しているプロジェクトでのみ利用可能です。ツールは境界付きの`start_at`/`end_at`フィルタ、`environment`（`any`、`ci`、または`local`）、および正確な`branch`を受け入れます。`list_build_entities`は`q`を受け入れます。`list_build_entity_history`は不透明な`after`/`before`カーソルをサポートします。不明なタイミングやキャッシュの観測値は、ゼロやミスとして扱われるのではなく、利用不可のままとなります。履歴は、既存のrunツールを使用したドリルダウンのために、記録された親およびネイティブ実行を参照します。

`get_build_entity`の指標には、タイミングが記録された観測値の数である`duration_samples`が含まれます。実際のゼロdurationはカウントされますが、タイミングが欠落している場合はカウントされません。この数は観測値の数より少なくなる可能性があります。利用できないduration統計はnullのままです。

Xcodeモジュールのdurationは、ビルドログで測定されたターゲットコンパイルから取得されます。モジュールキャッシュの解決やコンパイル作業のないターゲットは、durationサンプルに寄与しません。コンパイルの観測値はXcodeビルドを参照し、キャッシュイベントはgenerationまたはcacheコマンドを参照します。

Bazelアクションは、ターゲットラベル、ニーモニック、および構成された主要な出力によって識別され、入力依存のキャッシュダイジェストに頼ることなく、個別のアクションと構成を区別します。履歴は、キャッシュルックアップやトレースプロファイルフェーズではなく、BEPで報告された実行を記録します。完全な実行カバレッジには`--build_event_publish_all_actions`が必要です。アーティファクトの配信はベストエフォートであるため、観測値が欠落していることは、作業が実行されなかった証拠ではありません。安定した識別子や実行開始情報を持たない古いKuraペイロードは受け入れられますが、インデックス付けされません。終了時間の測定値がない場合は利用不可のままとなり、実際のゼロdurationはカウントされます。

Mixモジュールのdurationは、独立して測定されたモジュールの作業ではなく、含まれるファイルのコンパイルを測定します。Onceアクションは、クライアントがターゲットマッピングを報告した際に、宣言されたターゲット/機能/インデックススロットを使用します。診断ラベルだけでは安定した識別子にはなりません。既存のクライアントとrunレベルのツールは変更なくサポートされ続けます。

Cargoクレートは、正確に記録されたクレートルート、名前、および種類によってグループ化されます。チェックアウトパスの変更により履歴が分割される可能性があり、ビルドプロファイル、機能、およびターゲットトリプルは区別されません。履歴はrustc呼び出しを測定し、ファイルごとの作業やキャッシュヒットは測定しません。欠落しているジョブは、削除や完全なワークスペース在庫の確立にはつながりません。

分析読み取りには、メモリと実行時間の制限があります。クエリがこれらの制限を超えると、ツールは空の結果を作成する代わりにエラーを返します。

新しい観測値はデプロイ後にインデックス付けされます。この機能は、既存のrunテレメトリをバックフィルしません。識別子メタデータは、<.localized_link href="/guides/server/data-retention">データ保持ポリシー</.localized_link>の下で、個々の観測値よりも長く存続します。

#### テスト

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_test_runs` | プロジェクトのテスト実行を一覧表示します。`query`フィールドは`git_branch`、`scheme`、および`status`です。`field:"value"`は完全一致、`field~"value"`は大文字小文字を区別しない部分一致、先頭の`-`はいずれかの演算子を否定します。例えば、`-git_branch~"gh-readonly-queue"`はマージキューブランチを除外します。空白で区切られたクエリフィルタと明示的な引数はANDセマンティクスで結合されます。 | `account_handle`, `project_handle` |
| `get_test_run` | 結果バンドル（`.xcresult`）とセッションアーカイブの一時的なダウンロードURLを含む、テスト実行の詳細な指標を取得します。 | `test_run_id` |
| `list_test_module_runs` | 特定のテスト実行に対するテストモジュール実行を一覧表示します。 | `test_run_id` |
| `list_test_suite_runs` | 特定のテスト実行に対するテストスイート実行を一覧表示します。オプションでモジュールによるフィルタリングが可能です。 | `test_run_id` |
| `list_test_cases` | プロジェクトのテストケースを一覧表示します（`flaky`などのフィルタをサポート）。 | `account_handle`, `project_handle` |
| `get_test_case` | 信頼性レート、flakinessレート、および実行回数を含む、テストケースの詳細な指標を取得します。 | `test_case_id`または`identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | テストケース実行を一覧表示します。オプションでテストケースまたはテスト実行によるフィルタリングが可能です。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 特定のテストケース実行の失敗詳細と繰り返しを取得します。 | `test_case_run_id` |
| `list_test_case_run_attachments` | テストケース実行の添付ファイルを一覧表示します。各添付ファイルには一時的なダウンロードURLが含まれています。 | `test_case_run_id` |
| `list_test_case_events` | ミュートやスキップなど、テストケースの状態変化を一覧表示します。 | `test_case_id` |
| `update_test_case` | テストケースの状態またはflaky分類を更新します。変更により、外部サービスを含む設定済みのWebhookエンドポイントにイベントがディスパッチされる場合があります。 | `test_case_id`または`identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | テスト実行の選択的テストターゲット結果を一覧表示します。 | `test_run_id` |
| `get_coverage` | コミットまたはブランチの最新の完了コミットにおいて、そのターゲットを含むプロジェクトのコードカバレッジを取得します。`git_commit_sha`または`branch`がない場合、デフォルトブランチを読み取ります。 | `account_handle`, `project_handle` |
| `list_coverage_files` | コミットまたはブランチの最新の完了コミットにおいて、そのコミットのコードカバレッジが測定したファイルとその行カバレッジを一覧表示します。`search`、並べ替え、およびページネーションをサポートします。 | `account_handle`, `project_handle` |
| `get_coverage_file` | コミットまたはブランチの最新の完了コミットにおいて、ファイルのコードカバレッジとその関数を取得します。各行の実行回数を取得するには`include_lines`を設定します。 | `account_handle`, `project_handle`, `path` |

コードカバレッジツールは、コードカバレッジが有効になっているアカウントで利用できます。

#### バンドル

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_bundles` | プロジェクトのバンドル（アプリバイナリ）を一覧表示します。オプションで`git_branch`および`tags`（すべてのタグが完全に一致する必要があります）でフィルタリングできます。 | `account_handle`, `project_handle` |
| `get_bundle` | カスタムタグを含む、特定のバンドルの詳細情報を取得します。 | `bundle_id` |
| `get_bundle_artifact_tree` | パスで並べ替えられたフラットリストとして、バンドルの完全なアーティファクトツリーを取得します。 | `bundle_id` |

`list_bundles`は`tags: ["paid", "production"]`を受け入れ、ビルドのフレーバーや環境を区別します。タグは大文字小文字を区別するラベルで、文字、数字、ハイフン、またはアンダースコアを含み、タグは最大10個、タグあたり最大50文字です。一覧および詳細結果には`custom_metadata.tags`が含まれます。ページネーションカウントとブランチフィルタはタグ付けされた結果に適用されます。`tags`を省略すると、フィルタリングされていない動作が維持されます。無効なタグフィルタは、クエリを広げるのではなくエラーを返します。

#### Generations

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_generations` | プロジェクトのgeneration実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_generation` | 特定のgeneration実行の詳細情報を取得します。 | `generation_id` |

#### キャッシュ実行

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_cache_runs` | プロジェクトのキャッシュ実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_cache_run` | 特定のキャッシュ実行の詳細情報を取得します。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | generationまたはキャッシュ実行のモジュールキャッシュターゲットを一覧表示し、ターゲットごとのキャッシュヒット/ミスステータスと診断用コンポーネントハッシュ（追加のハッシュ入力を含む）を表示します。 | `run_id` |

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
| `list_automation_alert_revisions` | 自動化アラートのリビジョン履歴を一覧表示します。アクションの認証情報はマスクされます。 | `alert_id` |
| `list_project_notification_alerts` | プロジェクト通知アラートルールを一覧表示します。ダッシュボードの設定ページと同じ管理者権限が必要です。Webhookアドレスはマスクされます。 | `account_handle`, `project_handle` |

### イベント

ステートレスな`2026-07-28` Model Context Protocolライフサイクルを使用するクライアントは、`events/list`を呼び出してイベントとそのペイロードスキーマを発見できます：

| イベント | 送信タイミング | サブスクリプションフィルタ |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | テストケースが非flakyからflakyに変更されたとき。 | `account_handle`, `project_handle` |
| `build.failed` | ローカルまたは継続的インテグレーションのXcode、Gradle、またはBazelビルドが失敗で完了したとき。 | `account_handle`, `project_handle` |
| `test_run.failed` | ローカルまたは継続的インテグレーションのテスト実行が失敗で完了したとき（マージされたシャーディング実行や放棄された実行を含む）。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuistランナージョブが失敗で完了したとき。 | `account_handle` |

サブスクライブするには、クライアントは`events/subscribe`をイベント名、上記の`arguments`にリストされたハンドル、および`https://`コールバックURLと`whsec_`署名シークレットを含む`webhook`配信とともに呼び出します。プロジェクトイベントにはアカウントメンバーシップと対応するテストまたはビルドデータへの読み取りアクセスが必要です。ランナージョブイベントにはアカウントメンバーシップとランナーの読み取りアクセスが必要です。承認済みの[`auth.md`](https://workos.com/auth-md)アクセストークン、承認済みのアカウントトークン、およびブラウザ認可グラントはサブスクリプションを作成できます。関連する認証情報が有効でなくなると配信は停止します。各ユーザーは最大25件のアクティブなサブスクリプションを保持できます。Tuistはサブスクリプションを保存する前にコールバックに検証チャレンジを送信します。コールバックは同じ`challenge`値を含むオブジェクトを返す必要があります。サブスクリプションはデフォルトで7日間有効で、再度サブスクライブすることで更新でき、ユーザーのアクセスまたは認証情報が削除されると配信が停止します。オプションの`ttlMs`は1時間から30日の間で制限されます。Tuistはタイムアウトしたコールバックを再試行し、5分間にわたる少なくとも3回連続のタイムアウト後にサブスクリプションを解除します。コールバックを復旧した後、再度サブスクライブしてください。

イベントが発生すると、Tuistはそのリソース識別子とダッシュボードURLをコールバックに送信します。ビルドおよびテスト実行の失敗には`is_ci`と`git_branch`も含まれるため、クライアントはローカルの失敗を無視したり、ブランチでフィルタリングしたりできます。ビルドイベントには`build_system`が含まれます。ランナージョブイベントには`workflow_job_id`と`workflow_run_id`の両方が含まれます。リクエストにはサブスクリプション識別子と[Standard Webhooks](https://www.standardwebhooks.com/)署名ヘッダーが含まれ、クライアントが発信元を検証できます。Tuistは失敗した配信を再試行するため、クライアントは安定した`eventId`を使用して重複を除外する必要があります。ペイロードにはテスト名、ログ、および失敗メッセージは含まれません。クライアントは上記のツールを通じてこれらの詳細を取得し、チームに通知するかデバッグを開始するかを決定できます。クライアントは`events/unsubscribe`で配信を停止できます。

### プロンプト

| プロンプト | 説明 |
|--------|-------------|
| `fix_flaky_test` | 失敗パターンを分析し、根本原因を特定して、的を絞った修正を適用することで、不安定なテストの修正手順を案内します。 |
| `compare_builds` | ビルドを比較して、パフォーマンスの劣化、キャッシュの変化、ビルドの問題を特定する手順を案内します。Xcode、Gradle、Bazel、Cargoプロジェクト向けのネイティブツールを使用します。Cargoの比較では部分的なコンパイラカバレッジを保持し、推定されるコンパイラの作業量と経過時間による節約を区別します。 |
| `compare_test_runs` | 2つのテスト実行を比較して、回帰、新しい失敗、不安定なテストを特定する手順を案内します。 |
| `compare_bundles` | 2つのバンドルを比較して、アーティファクトツリー全体のサイズ変化を特定する手順を案内します。 |
| `compare_test_case` | 2つのブランチまたは期間にわたるテストケースの動作を比較する手順を案内します。 |
| `compare_generations` | 2つの生成実行を比較して、パフォーマンスの劣化とモジュールキャッシュの変化を特定する手順を案内します。 |
| `compare_cache_runs` | 2つのキャッシュ実行を比較して、キャッシュの有効性の変化とターゲットレベルの回帰を特定する手順を案内します。 |
| `integrate_gradle_project` | 既存のGradleプロジェクトにTuistを統合する手順を案内します。個別のツールおよびGradle認証、アカウントの検出、プロジェクトの作成、リモートキャッシュポリシー、ビルドインサイト、読み戻し検証が含まれます。 |
| `integrate_bazel_project` | Bazelプロジェクトの作成または選択、コマンドラインの認証、リモートキャッシュとビルドインサイトの構成、Tuistビルドデータによる統合の検証を行う手順を案内します。 |
| `integrate_xcode_project` | 既存のXcodeプロジェクトにTuistを統合する手順を案内します。Xcodeキャッシュ、ビルドインサイト、テストインサイト、テストシャーディングをサポートします。 |
| `ask_tuist` | 公開情報を文脈として使用し、焦点を絞った実装とテスト証拠を現在の動作の信頼できる情報源として、Tuistに関する質問に回答します。`question`が必要で、リビジョン固定の証拠を引用します。 |

プロジェクトデータのプromptは`account_handle`と`project_handle`を受け取り、調査範囲を特定のプロジェクトに限定します。比較プロンプトはさらに`base`と`head`引数を受け取り、比較対象の2つの項目（ID、ダッシュボードURL、またはブランチ名で指定）を指定します。`ask_tuist`はプロジェクトパラメータの代わりに`question`を受け入れます。`integrate_gradle_project`はさらに、適用するGradle統合のカンマ区切りリストである`features`を受け入れます。`remote_cache`、`build_insights`、`test_insights`、`flaky_tests`、および`test_sharding`です。`integrate_bazel_project`は、セルフホスト型またはローカルインストール用のオプションの`server_url`を受け入れます。`integrate_xcode_project`は`features`を受け入れ、`xcode_cache`、`build_insights`、`test_insights`、および`test_sharding`を含みます。

#### Gradle統合プロンプトの機能

`integrate_gradle_project`プロンプトと`get_gradle_integration_guide`ツールは、完全なセットアップワークフローを文書化しています。このツールはサーバーの初期化手順でも参照されており、プロンプトを列挙しないエージェントからも発見可能です。

| 機能 | エージェントが構成する内容 |
|---------|---------------------------|
| `remote_cache` | Gradleのビルドキャッシュを有効にし、Tuistのリモートキャッシュアップロードポリシーを構成します。ローカルでの読み取り専用使用を前提とし、継続的インテグレーションランナーからのみアップロードすることを推奨します。 |
| `build_insights` | Tuist Gradleプラグインを適用し、必要に応じてビルド分析のアップロード動作を構成します。 |
| `test_insights` | Tuist Gradleプラグインを適用し、Gradle `Test`タスクの結果が自動的にアップロードされるようにします。 |
| `flaky_tests` | 不安定なテストの検出のためのセットアップ、オプションのGradle Test Retryプラグインの使用、テスト検疫の構成に関する手順を案内します。 |
| `test_sharding` | `tuistPrepareTestShards`、シャードマトリックスの生成、および`TUIST_SHARD_INDEX`に基づくテスト実行のための継続的インテグレーションワークフローを追加します。 |

`features`が省略された場合、プロンプトはエージェントに対して、ユーザーが希望する統合を明確にするか、リクエストから最小限の実用的なセットを推論してからGradleプロジェクトを編集するよう求めます。

#### Xcode統合プロンプトの機能

`integrate_xcode_project`プロンプトは、TuistがサポートするすべてのXcode統合を文書化しています。

| 機能 | エージェントが構成する内容 |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`、生成されたプロジェクトのキャッシュ設定、手動のXcodeキャッシュビルド設定、および継続的インテグレーションランナーに限定されたアップロードポリシーを構成します。 |
| `build_insights` | `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath`、および`tuist setup insights`を通じたオプションのマシンメトリクスを構成します。 |
| `test_insights` | `tuist inspect test`、スキームテストのポストアクション、および継続的インテグレーションテスト実行用の結果バンドル生成を構成します。 |
| `test_sharding` | `TUIST_SHARD_INDEX`を使用したXcodeまたは生成されたプロジェクトのシャード計画とシャード実行ワークフローを追加します。 |

`features`が省略された場合、プロンプトはエージェントに対して、ユーザーが希望する統合を明確にするか、リクエストから最小限の実用的なセットを推論してからXcodeプロジェクトを編集するよう求めます。
