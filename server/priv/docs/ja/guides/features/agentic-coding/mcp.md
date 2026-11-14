---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · エージェントによるコーディング · 機能 · ガイド · Tuist",
  "description": "Tuist の MCP エンドポイントを通じて、AI エージェントにテストのインサイトなどへのアクセスを提供します。"
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro)は、AIエージェントが外部サービスやデータソースと対話できるようにするオープンスタンダードです。[Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/)などのアプリケーションや、[Zed](https://zed.dev)、[Cursor](https://www.cursor.com)、[Visual Studio Code](https://code.visualstudio.com)などのエディタをTuistと相互運用可能にします。

Tuistは`https://tuist.dev/mcp`にサーバーサイドのModel Context Protocolエンドポイントをホストしています。クライアントをこのエンドポイントに接続することで、エージェントはテストインサイト、flaky test分析などを含むTuistプロジェクトデータにアクセスできます。ほとんどのツールは読み取り専用で、認証されたTuistプロジェクトデータにスコープされています。アカウント設定ツールは、認証済みユーザーに必要な権限がある場合、アカウントの一覧表示、組織の作成、プロジェクトの作成、および既存ユーザーの組織への追加を行えます。すべてのツールは、読み取り専用かどうか、元に戻すのが困難な変更を引き起こす可能性があるかどうか、パブリックなインターネットの状態を変更する可能性があるかどうかを示すアノテーションを公開しています。`update_runner_profile`、`update_notification_rule`、および`connect_claude_subscription`は、既存の設定や認証情報を置き換える可能性があるため、`destructiveHint: true`を公開しています。アカウント設定ツールにはユーザー認証が必要です。プロジェクトトークンや通常のアカウントトークンでは利用できません。ユーザーがブラウザでクライアントを承認するか、`auth.md`登録をクレームすると、Tuistはその認証情報をModel Context Protocolエンドポイントでのみユーザーに関連付け、設定ツールが要求されたワークフローを完了できるようにします。

Tuistは[2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)を実装しています。リクエストはステートレスです。クライアントは各リクエストとともにプロトコルメタデータを送信し、初期化なしで直接ツールを呼び出すことができます。`server/discover`は、サーバーの識別情報、機能、サポートされているバージョン、および手順を返します。セッション識別子や独立したイベントストリームはありません。2025-06-18または2025-03-26の初期化フローを使用するクライアントも引き続きサポートされており、それらもサーバーセッションなしで動作します。

## Model Context Protocolとスキルの比較

Model Context Protocolツールと<.localized_link href="/guides/features/agentic-coding/skills">スキル</.localized_link>は、その機能において重複する可能性があります。現在の両者の重複を考慮し、同じフロー内で両方を混在させるのではなく、ワークフローごとに1つのアプローチを選択し、一貫して使用してください。

プラグインインストールをサポートするクライアントの場合、<.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link>を使用して両方を一緒にインストールしてください。

## 設定

クライアントのリモートModel Context Protocolサーバーとして`https://tuist.dev/mcp`を追加してください。サーバーの初期化手順とパブリックサーバーカードは、エージェントに外部の認証ドキュメントを取得または追従させることなく、動的クライアント登録を伴うOAuth 2.0と標準的なブラウザ認可フローをインラインで説明しています。これらのサーバー全体の指示は、ワークフローのガイダンスを一般的に保ちます。ツールの認証はローカルのコマンドラインツールやビルドシステム統合を認証するものではなく、エージェントは関連するTuistツールを通じて要求された変更を確認する必要があります。ビルドシステム固有の設定と認証チェックは、統合ガイドとプロンプトに記載されています。Tuistは依然として、[Open Authorization](https://oauth.net/2/)ディスカバリーメタデータと現在の[auth.md protocol](https://workos.com/auth-md)を`https://tuist.dev/auth.md`で個別に公開しています。

組織のいずれかがシングルサインオンを強制している場合、ブラウザでクライアントを承認するには、その組織を通じてサインインしたセッションが必要であり、必要に応じてTuistはまずプロバイダーにリダイレクトします。<.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">single sign-on</.localized_link>を参照してください。

このエンドポイントは、古いセッションベースのライフサイクル alongside `2026-07-28`ステートレスなModel Context Protocolリクエストライフサイクル（`server/discover`を含む）を受け入れます。既存のクライアントは、現在の接続方法を继续使用できます。

Model Context Protocolイベントをサポートするクライアントは、プロジェクトイベントをサブスクライブできます。利用可能なイベントと配信要件については、[Events](#events)を参照してください。

すでにリモートブラウザ認証をサポートしているクライアントは、ブラウザでの認証を継続できます。`auth.md`をサポートするクライアントとエージェントは、匿名で登録したり、信頼されたプロバイダーのIDアサーションを提示したり、サービス認証された電子メールクレームを開始したりできます。登録によりTuistが署名したIDアサーションが返され、エージェントはこれを標準のトークンエンドポイントで1時間有効なアクセストークンと交換します。Tuistはパブリック署名鍵を公開し、標準的なトークン失効とプロバイダーのセキュリティイベント配信をサポートしています。

認証されていないエージェントは、Model Context Protocolエンドポイントから返される`WWW-Authenticate`ヘッダーを読み取り、保護リソースメタデータを取得し、認証サーバーメタデータを取得して、その`agent_auth.skill`URLに従う必要があります。Tuistは、言語モデル駆動型クライアントがネイティブクライアント統合に頼らずにフローを発見できるように、未承認のレスポンスボディにも同じローカル`auth_md`URLを返します。デプロイメントローカルドキュメントは、エンドポイント名、リクエストボディ、クレームポーリング、およびアサーション交換に関する信頼できる情報源です。

エージェントが電子メールクレームを開始する前に、ユーザーにTuistアカウントの電子メールアドレスを確認してもらう必要があります。プロバイダーのプロフィール、Git設定、環境変数、またはセッションメタデータからそのアドレスを推測してはいけません。

このエンドポイントは`mcp`スコープグループを使用します。匿名の事前クレーム認証情報は、機能を発見し、パブリックな統合ガイダンスを読み取ることができますが、サインインしたユーザーとしては扱われません。ブラウザでの承認またはクレーム後、認証情報はユーザースコープとなり、各ツールはダッシュボードと同じ認可チェックを適用します。詳細については、<.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>を参照してください。

ツールは、認証済みユーザーがすでに読み取りアクセス権を持つプロジェクトに解決されます。XcodeおよびGradleビルドツールは、ビルドUUIDまたはダッシュボードURLを受け入れます。UUIDは正確に1つのプロジェクトを識別する必要があります。複数のプロジェクトに出現する場合、ツールは別のプロジェクトのレポートを選択する代わりに「見つかりません」を返します。プロジェクトスコープのダッシュボードおよびAPI読み取りは利用可能です。報告されたアクター識別子は、検証されていないラベルであり、認証情報や追加のアクセス権ではありません。

ビルド一覧および詳細ツールは、オプションの`tuist_version`メタデータを公開します。XcodeおよびCargoについては報告元のTuist CLI、GradleについてはTuist Gradleプラグイン、Mixについては`tuist_ex`ライブラリです。Xcodeは、リンクされたプロジェクト生成イベントから`tuist_generation_version`も公開します。これはアップロードに使用したCLIと異なる場合があります。欠損している観測値はnullであり、サーバーや他のレポートから推論されることはありません。Bazelは既存の`bazel_version`を使用します。Onceの実行詳細は`once_version`を公開します。これらのフィールドは報告されたバージョンを示すものであり、検証された識別子やワイヤー契約のバージョンではありません。RESTビルドエンドポイントも同じメタデータを公開します。既存の統合およびflaky-testスキルはバージョンフィールドに依存せず、ワークフローの変更は不要です。

Tuistオペレーターが顧客のアカウントを調査する際は、すべての呼び出しを記録するTuistの内部運用ツールを通じて行います。このエンドポイントへの直接接続では、ユーザー自身のメンバーシップを超えるアクセス権限は付与されません。

### Pulse

Pulseは、アカウントの運用メトリクス、ログ、トレースに対する読み取り専用ツールを公開します。これらはすべて`account_handle`で指定されます。最初の2つはPulseページとそのREST APIを反映しています。残りの5つは、エージェントがテレメトリーを直接探索できるようにするもので、REST相当機能はありません。

| ツール | 目的 | `/api/accounts/:account_handle/pulse`以下のREST相当機能 |
| --- | --- | --- |
| `query_pulse` | Pulseページのテーブル | `GET /:signal` |
| `get_pulse_analytics` | Pulseページのウィジェット | `GET /:signal/analytics` |
| `query_pulse_metrics` | インスタントまたは範囲PromQL | なし |
| `list_pulse_labels` | ラベル名、または1つのラベルの値 | なし |
| `search_pulse_logs` | フィルターされたログエントリ | なし |
| `search_pulse_traces` | フィルターされたスパン | なし |
| `get_pulse_trace` | 1つのトレースのすべてのスパン | なし |

Pulseは、アカウントまたはプロジェクトがパブリックであっても、サーバー構成済み組織の現在のメンバーに制限されています。ユーザー認証、またはユーザー関連の`mcp`認証情報とアカウント読み取り権限が必要です。プロジェクトトークン、通常のアカウントトークン、匿名登録、および組織メンバーシップのないオペレーターアクセスは、Pulseへのアクセスを付与しません。認証情報は別のバックエンドやテレメトリーテナントを選択できず、サーバー構成済みのアカウントのみがPulseテレメトリーを持つため、どのツールも他のアカウントのデータを読み取ることはできません。ブラウザエージェントは、そのページのアカウントスコープ内で、Pulseページ上でのみこれらのツールを受け取ります。

RESTにはユーザー認証情報が必要です。OAuthおよび`auth.md`ユーザー関連付けは`/mcp`エンドポイントでのみ利用可能です。現在のユーザーに関連付けられていないアカウント認証情報は、関連するアカウントのメンバーシップや可視性に関係なく拒否されます。

`query_pulse`は`signal`（`metrics`、`logs`、または`traces`）、オプションの`query`、および`range`（`15m`、`1h`、`6h`、または`24h`、デフォルトは`1h`）を受け取ります。メトリクスはPromQL式を受け入れます。ログとトレースは、ログボディとスパン名に対してマッチングされる大文字小文字を区別しないリテラルテキストを受け入れます。`*`（デフォルト）はすべてを選択します。トレースの行は個々のスパンです。テーブルは`search`、`page`（デフォルトは`1`）、`page_size`（`1`～`100`、デフォルトは`20`）、`sort_by`、および`sort_order`（`asc`または`desc`）を受け入れます。ソート列はシグナルによって異なり、ツールスキーマに一覧表示されます。フィルターには`service`およびログの`level`が含まれます。フィルター演算子は対応する`_op`引数（`eq`、`contains`、または`not_contains`）を使用し、デフォルトでは完全一致となります。

ソート列は、メトリクスの場合`name`/`value`、ログの場合`timestamp`/`service`/`level`/`message`/`trace_id`、トレースの場合`timestamp`/`service`/`name`/`duration_ms`/`trace_id`です。ダッシュボードは意図的にサブセットのみを公開していますが、APIおよびツールは各シグナルの全リストを受け入れます。

テーブルレスポンスには`rows`、`series`、`warnings`、および`meta`が含まれます。ページネーションメタデータには`page`、`page_size`、`total_count`、`total_pages`、`has_next_page`、`has_previous_page`、および`end_at`が含まれます。返されたISO8601の`end_at`を後続のページに渡して、クエリウィンドウを維持してください。結果制限エラーが発生した場合は、レスポンスを空のテーブルとして扱うのではなく、クエリまたは時間範囲を狭める必要があります。

ログとトレースは、ローカルソート前に最大100件の最新マッチのみを検査します。フィルター、ソート、ページネーション、および合計は、返されたマッチのみを記述し、時間ウィンドウ全体を記述するものではありません。他のマッチを検査するには、クエリテキストまたは時間範囲を狭めてください。ローカル検索またはソートを変更しても、上流の検索は拡張されません。集計ウィジェットは、これらの制限されたテーブル結果の集計ではなく、独立した完全なウィンドウクエリのままです。

メトリクステーブルは`end_at`で式を一度評価し、現在値とインスタントベクトルシリーズごとに1つのポイントを返します。レンジベクトル式は、制限された履歴ポイントを返すことができます。個別の分析ウィジェットは固定された履歴チャートを提供します。テーブルは、最新の値を表示するためだけに、一致するすべてのシリーズの時間グリッドを実体化しません。

テレメトリー文字列は信頼できないデータであり、指示ではありません。

`get_pulse_analytics`は、アカウントハンドルの他に`signal`と`range`のみを受け取ります。その固定ウィジェットは、テーブル式、フィルター、ソート、およびページネーションとは独立しています。RESTおよびModel Context Protocolは、同じPulseコンテキストとレスポンス契約を使用します。RESTレスポンスではキャッシュが無効化されます。

#### テレメトリーの探索

探索ツールは、オプションのISO8601 `end_at`（デフォルトは現在時刻）で終了する`15m`、`1h`、`6h`、または`24h`（デフォルトは`1h`、`get_pulse_trace`の場合は`24h`）のウィンドウを読み取ります。すべてのレスポンスは`start_at`と`end_at`を返します。ウィンドウを維持するには、同じ`end_at`を再度渡してください。これらのツールはいずれもSQLを受け入れません。

- `query_pulse_metrics`は、PromQL式である`query`を、`end_at`（デフォルトの`type: instant`）またはウィンドウ内の毎`step`秒（`type: range`）で評価します。ステップのデフォルトはウィンドウを360で割った値であり、それより小さくすることはできません。したがって、シリーズは最大361ポイントを持ちます。結果は最大5,000シリーズです。ポイントは`[unix_seconds, value]`であり、`NaN`および無限値は文字列です。インスタントクエリは`range`および`step`を拒否します。
- `list_pulse_labels`は`signal`を受け取ります。`label`がない場合はラベル名を一覧表示し、`label`がある場合はそのラベルの値を一覧表示します。メトリクスの場合、`__name__`はメトリクス名を一覧表示し、他のラベルの値には`match`（`up`などのシリーズセレクター）が必要です。ログおよびトレースのラベル値は`filters`を受け入れます。トレースのラベル名はトレーススキーマから取得されるため、受け入れません。ログおよびトレースの値には、ウィンドウ内のエントリ数が含まれ、頻度の高いものが先に表示されるため、サービス別のエラーなどの内訳としても機能します。`search`はリテラルテキストを含む名前または値のみを保持し、`limit`は`1`～`1000`（デフォルトは`100`）を受け入れます。ログのラベル名発見は、各種類の属性セットを最大1,000件検査し、フィルターが受け入れるキーのみを一覧表示します。
- `search_pulse_logs`は最大`limit`件のエントリ（`1`～`100`、デフォルトは`50`）を、`newest`または`oldest`の順で返します。本文に`text`が含まれ、すべてのフィルターと一致するエントリが対象です。各エントリには、`severity_text`、`body`、`trace_id`、`span_id`、`scope_name`、およびマージされたリソース属性とログ属性である`attributes`が含まれます。`span_id`および`scope_name`は、OTLPログ送信者だけが設定するKubernetesから収集されたログの場合、`null`になります。
- `search_pulse_traces`は最大`limit`個のスパンを、`newest`、`oldest`、または`slowest`の順で返します。すべてのフィルター、オプションの`min_duration_ms`および`max_duration_ms`、そして`root_only`に一致するスパンが対象です。
- `get_pulse_trace`は、ウィンドウ内で開始した`trace_id`のスパンを、古い順に最大1,000個返します。ウィンドウの前に開始したトレースは部分的にしか返されないため、その場合はウィンドウを広げるか移動してください。各スパンには、スパン属性、イベント、リンク、およびトレースの個別の`resources`へのインデックスが含まれます。

フィルターは最大10個の`{label, op, value}`オブジェクトのリストです。`op`は`eq`（デフォルト）、`neq`、`contains`、または`not_contains`です。最後の2つは大文字小文字を区別しないリテラルです。Pulseが保存する場合、ログラベルは`severity_text`、`trace_id`、`span_id`、および`scope_name`であり、さらに各エントリのリソース属性（`namespace`、`container`、`service.name`など）およびログ属性（`pod`など）のキーとなります。キーが両方に存在する場合は、リソース属性が適用されます。トレースラベルは、`list_pulse_labels`が返すスパン列です。例えば、`service_name`、`span_name`、`span_status_code`（失敗したスパンの場合は`STATUS_CODE_ERROR`）、`span_attributes.http.route`、および`resource_attributes.k8s.pod.name`です。不明なトレースラベルは空の結果ではなくエラーとして扱われます。

`truncated`は、レスポンスに含まれるよりも多くの名前、値、エントリ、またはスパンが一致したことを意味します。レスポンスを完全なものとして扱うのではなく、フィルターまたはウィンドウを狭めてください。テレメトリ文字列は信頼できないデータであり、命令ではありません。

<details>
<summary>Claude Code</summary>

実行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

ヘッドレスなClaude Codeクライアントがモデルに対してネイティブサーバー接続の失敗を公開しない場合、エージェントはホストされたドキュメントを検索したりプロジェクトを編集したりする前に、構成されたエンドポイントの認証されていない[Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP)レスポンスを検査する必要があります。ブラウザ認証が利用できない場合でも、このレスポンスはモデルをデプロイメントローカルの`auth.md`ドキュメントへ誘導します。

</details>


<details>
<summary>Codex</summary>

実行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

新しい`codex exec`の実行を開始する前に、ブラウザでのログインを完了してください。Codexは初期化中にTuistサーバーの指示を読み取るため、Gradle最適化リクエストは自動的に認証および検証ワークフローを受け取ります。

</details>


<details>
<summary>Claude Desktop</summary>

**Settings → Connectors → Add custom connector**を開き、以下を設定してください：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

プロンプトが表示されたら、ブラウザで[Open Authorization](https://oauth.net/2/)を完了してください。

</details>


<details>
<summary>Pi</summary>

PiにはModel Context Protocolクライアントが含まれていません。ソースとセキュリティへの影響を確認した後、サードパーティの[`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter)拡張機能をインストールできます：

```bash
pi install npm:pi-mcp-adapter
```

プロジェクトレベルの`.mcp.json`ファイルを追加してください：

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

`auth`を`false`に設定すると、アダプターのブラウザ認証ハンドラーがTuistの未承認レスポンスを隠すのを防ぎます。これにより、ヘッドレスエージェントは返された`auth_md` URLを読み取り、Tuistの登録、IDアサーション交換、およびクレームポーリングフローに従うことができます。交換されたアクセストークンをBearerトークンとして構成するか、エージェントが直接認証済みModel Context Protocol呼び出しを行うようにしてください。

ブラウザ認証を希望する場合は、`auth`を`"oauth"`に設定してください。そのフローでは、認証が完了するまでPiの[remote procedure call mode](https://pi.dev/docs/latest/rpc)を使用して1つのプロセスを生かしておいてください：

```bash
pi --mode rpc
```

コールバック状態を所有するプロセスが終了しているため、保留中のブラウザ認証を別々の`pi --print`呼び出しに分割しないでください。

</details>


<details>
<summary>OpenCode</summary>

Tuist Model Context Protocolサーバーを`opencode.json`に追加してください：

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

その後、サーバーを認証してください：

```bash
opencode mcp auth tuist
```

</details>


<details>
<summary>Cursor</summary>

**Cursor Settings → Tools & Integrations → Model Context Protocol Tools**を開き、以下を追加してください：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

**Command Palette → MCP: Add Server**を使用し、以下の設定で[Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP)サーバーを構成してください：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Agent panel → Settings → Add Custom Server**を開き、以下を設定してください：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

エージェントが`auth.md`をサポートしている場合、ブラウザを開かずに匿名で開始できます。信頼されたプロバイダーIDがすでにリンクされている場合も、ブラウザなしで完了できます。サービス認証メール、匿名クレーム、または最初のプロバイダーリンクの場合、エージェントはTuist確認リンクと6桁のコードを表示します。リンクを開き、サインインして、Tuistページでエージェントのコードを入力してください。コードをエージェントに送り返さないでください。Tuistの認可サーバーメタデータは、デプロイメント独自の`/auth.md`を直接指しており、そこには正確なリクエスト形状とポーリング形状が含まれています。

## Amp orbsおよびClaude Codeクラウドセッション内のエージェント

Tuistアカウントに接続されたサンドボックスで実行されるコーディングエージェントは、ブラウザや保存されたTuist資格情報なしで、独自のIDトークンを使用してエンドポイントを認証できます：

- **Settings → Integrations → Amp**でアカウントが接続されているAmpワークスペースまたはプロジェクトの**Amp orbs**は、orbのIDトークンを送信します。Ampでは、サーバーの`Authorization`ヘッダーを`Bearer ${amp:id-token}`に設定してください。AmpはサーバーURLのオリジン用にトークンを発行し、有効期限が切れる前に更新します。別のオリジン用に発行されたトークンは拒否されます。
- 接続されたClaude Code環境の**Claude Code cloud sessions**は、Tuistが`TUIST_OIDC_TOKEN`として渡すセッショントークンを送信します。ヘッダーを`Bearer ${TUIST_OIDC_TOKEN}`に設定してください。

TuistのLinuxサンドボックスにはこれが構成されています。Ampのユーザー設定とClaude Codeのユーザー構成の両方に`tuist`サーバーがあり、どちらも`${TUIST_URL}/mcp`を指しています。さらに、Tuist CLIと、エージェントにプロジェクトの履歴に対して結果を確認するタイミングを指示するスキルが含まれています。それ以外の場所では、上記のヘッダーを使用してサーバーを自分で追加してください。

これらのトークンは、接続されたアカウントのすべてのプロジェクトへの読み取り専用アクセス権限を提供します。`mcp`グループの読み取りスコープを持ち、テストのミュートやスキップなど、データの作成、変更、削除を行うスコープは持ちません。ワークスペースまたは環境を切断すると、次のリクエストでアクセスが停止され、アクセス権限はトークン自体の有効期間を超えて存続しません。複数のTuistアカウントに接続されたAmpワークスペースは、トークンが特定のアカウントを指定していないため拒否されます。接続がない場合、未承認レスポンスの`error_description`にその旨が表示されます。

この読み取り専用アクセスはModel Context Protocolエンドポイントにのみ適用されます。同じサンドボックス内のコマンドラインツールとビルドシステム統合は、引き続きトークンを交換して接続のCIアクセスを行います。

## WebMCP

[WebMCP](https://webmachinelearning.github.io/webmcp)をサポートするブラウザでは、Tuistのページが`document.modelContext`でツールを登録するため、ブラウザに組み込まれたエージェントは追加の設定なしでそれらを呼び出すことができます。呼び出しはTuistサーバー上で実行されます。

- **Website and documentation pages**は、ドキュメントおよびソースツール（`search_tuist`、`search_tuist_code`、`list_tuist_files`、および`read_tuist_file`）を登録します。サインインは必要ありません。
- サインインしている場合、**An account's dashboard pages**はそのアカウント用のTuist読み取り専用ツールを登録します。各ページは、表示内容に応じて、プロジェクトのビルドシステム用のツールのみを登録します。GradleプロジェクトのビルドページにはGradleビルドツール、テストページにはテストおよびカバレッジツール、ランナーページにはランナーツール、サンドボックスページにはサンドボックスツールが割り当てられます。個人アカウントのAI設定ページのサブスクリプションセクションには`list_ai_subscriptions`があり、これは自分のアカウントに対してのみ回答します。すべてのページには、ドキュメントツールである`list_projects`と`get_project`も含まれます。ツールはサインインしたユーザーとして実行されるため、ダッシュボードで読み取れるデータと、現在閲覧しているアカウントのデータにのみアクセスできます。別のページまたはアカウントに移動すると、ツールはそのページのツールに置き換えられます。

データを作成、変更、または削除するツールはWebMCPでは利用できません。ブラウザエージェントはユーザーが追加することなくツールを受け取り、ビルドとテストによって生成されるコンテンツを読み取るためです。これらのツールを使用するには、MCPクライアントを`/mcp`エンドポイントに接続してください。

組織がシングルサインオンを強制している場合は、そのプロバイダーを使用してダッシュボードにサインインし、ツールを使用してください。

## ビルドシステム統合は2つの資格情報を使用します

Model Context Protocolツールに使用される資格情報は、GradleプラグインやBazelのリモートサービスを認証しません。エージェントがGradleまたはBazel統合を編集または検証する前に、以下を実行する必要があります：

```bash
tuist auth whoami --url https://tuist.dev
```

そのコマンドが認証されていない場合、エージェントは停止し、ユーザーに以下を実行するよう依頼する必要があります：

```bash
tuist auth login --url https://tuist.dev
```

ローカルまたはセルフホスト型デプロイメントの場合は、両方のコマンドと`tuist.toml`内のURLを置き換えてください。すべての場所でホスト名の表記を同一に保ってください。例えば、`localhost`と`127.0.0.1`は別々の保存された資格情報を使用します。


## 機能

### ツール

以下のツールは、Tuist Model Context Protocolサーバーを通じて利用可能です：

すべてのツールは、明示的な入力および出力スキーマとともに人間が読める説明を公開します。成功した呼び出しは、公表された出力スキーマに準拠した構造化コンテンツを返し、さらに構造化コンテンツをまだ消費しないクライアント向けにテキストとしてシリアル化された同じ結果を返します。

`build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id`、または`cache_run_id`など、単一レコードの識別子を受け取るツールは、そのレコードのTuistダッシュボードURLも受け入れます。識別子を抽出するのではなく、ブラウザからURLを直接貼り付けてください。

`get_xcode_build`、`get_test_run`、`get_gradle_build`、および`get_project`には`side_quests`を含めることができます。これは、プロジェクトが使用していないものの、レコードが役立つと示すTuist機能です。それぞれに`id`、証拠を示す`tip`、および`docs`リンクがあります。エージェントには、まずユーザーのリクエストを完了し、該当するサイドクエストを言及し、ユーザーが同意した場合のみアクションを実行することが求められます。これらは、ユーザーセッション、MCPトークン、またはエージェントIDで接続しているかどうかにかかわらず、プロジェクトのアカウントのメンバーにのみ返されます：

| ID | ツール | 推奨条件 |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | Xcode 26以降で処理されたクリーンビルドが、キャッシュ可能なコンパイルタスクを実行しませんでした。 |
| `gradle_build_cache` | `get_gradle_build` | ビルドがキャッシュ可能なタスクを実行しましたが、Gradleのビルドキャッシュがいずれのタスクに対してもキーを計算しませんでした。つまり、ビルドキャッシュが無効でした。 |
| `flaky_test_quarantine` | `get_test_run` | 実行に不安定なテストがありましたが、プロジェクト内の有効な自動化がそれらをミュートまたはスキップしていませんでした。Onceプロジェクトには推奨されません。 |
| `test_sharding` | `get_test_run` | Tuistがシャードできるビルドシステムにおいて、シャードされていないCI実行が10分以上かかりました。ヒントには、選択的テストがいつ、いくつのテストをすでにスキップしたかが示されます。 |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | CI実行がGitHub Actions、Bitrise、GitLab CI、またはBuildkiteマシンを使用しており、アカウントがTuist Runnersでジョブを実行したことがありません。tuist.devのみ。 |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | GitHub Actions実行が、GitHubリポジトリに接続されていないプロジェクトに属しています。 |
| `other_build_systems` | `get_project` | アカウントがサポートされているすべてのビルドシステムでTuistを使用していません。ヒントには他のビルドシステムを識別するファイルがリストされているため、エージェントはリポジトリを確認できます。 |

#### ドキュメントおよびコミュニティ検索

この読み取り専用ツールは、ドキュメントウェブサイトと同じ検索エンジンを使用して、Tuistのドキュメント、[アプリケーションプログラミングインターフェース](https://en.wikipedia.org/wiki/API)リファレンス、GitHubリリース、コミュニティフォーラム、およびGitHubイシューを検索します。リリース結果には、製品、バージョン、公開日、プレリリースステータスが含まれます。デフォルトでは安定版リリースが検索され、`include_prereleases`を使用するとプレリリースを含めることができます。このツールは、`https://tuist.dev/mcp`のTuistホストサーバーでのみ利用できます。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `search_tuist` | 公開されているTuistドキュメント、アプリケーションプログラミングインターフェースリファレンス、GitHubリリース、コミュニティディスカッション、およびGitHubイシューを検索します。オプションで、1つの`source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）に制限できます。 | `query` |

#### フィードバック

エージェントは、Tuistツールやプロンプトが期待通りに動作しなかった場合（結果が不明確、エラー、データ欠落、機能欠落など）、Tuistチームに伝えることができます。エージェントにはレポートを提案し、ユーザーが同意した場合のみ送信することが求められます。各レポートはTuistサポートとの会話を開始し、サポートからメールで返信が届く場合があります。レポートには、エージェントの期待値、実際の事象、オプションの提案、TuistユーザーID、ハンドル、メールアドレス、所属組織が含まれます。エージェントは問題が発生したアカウントとプロジェクトを指定することもでき、チームはどの組織に対応すべきかを把握できます。受け入れられるのは、ユーザーが所属しているアカウントのみです。Tuistユーザーとしてサインインしているエージェントのみがレポートを送信でき、各ユーザーは1時間あたり最大10件のレポートを作成できます。このツールは、`https://tuist.dev/mcp`のTuistホストサーバーでのみ利用できます。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `report_feedback` | Tuistツールまたはプロンプトの問題を報告します。オプションで、`tool_name`、問題が発生した`account_handle`および`project_handle`を指定し、`suggestion`を追加できます。 | `category`, `expected`, `actual` |

#### ソースに基づく回答

これらの読み取り専用ツールにより、エージェントはホストサーバーと共にデプロイされた正確な公開Tuistソースリビジョンを、現在の動作に依存する回答の信頼できる情報源として使用できます。`https://tuist.dev/mcp`でのみ利用できます。

互換性のあるクライアントは、初期化中にツールのソースリビジョン、リンク、結果制限に関する事実上の説明を、インラインOAuth認証情報とともに受け取ります。これらの説明は、回答スタイルや検証ワークフローを規定するものではありません。ユーザーは、まず`ask_tuist`プロンプトを呼び出さずに直接質問することができます。このプロンプトは、明示的なソースに基づくワークフローのために引き続き利用可能です。

すべての操作には、同時実行数、期間、トラバーサル、読み取りバイト数、レスポンスサイズに対する固定制限があります。検索および一覧結果には、`truncated`および`truncation_reason`フィールドが含まれます。結果が切り捨てられた場合は、結果を網羅的なものとして扱うのではなく、パス、ファイルパターン、または検索語句を絞り込んでください。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `search_tuist_code` | ソースファイルを検索することで、現在の動作、デフォルト、構成、機能フラグ、エラー処理、または文書化されていない詳細に関する質問に回答します。結果には、周辺の行、リビジョン固定のソースリンク、およびスキャン統計情報が含まれます。 | `pattern` |
| `list_tuist_files` | 関連するパスが不明な場合に、ソースサブシステムまたは近くのテストを発見します。一覧表示には深度と結果数の上限があります。 | なし |
| `read_tuist_file` | 関連するパスを見つけた後、実装ファイル、呼び出しサイト、またはテスト内の特定の行範囲を検査します。切り捨てられたレスポンスには、継続のための`next_start_line`が提供されます。 | `path` |

#### プロジェクト

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_accounts` | 認証済みユーザーが利用可能な個人および組織アカウントのハンドルを一覧表示します。各アカウントがプロジェクトを作成できるかどうかも含みます。 | なし |
| `get_organization` | 組織のメンバーディレクトリを取得します。保留中の招待には、ダッシュボードと同じ管理者権限が必要です。招待受諾トークンは返されません。 | `account_handle` |
| `create_organization` | 認証済みユーザーのためにTuist組織を作成します。 | `handle` |
| `create_project` | 認証済みユーザーがアクセスできるアカウントの下にTuistプロジェクトを作成します。 | `account_handle`, `project_handle` |
| `add_organization_member` | 既存のTuistユーザーを組織に追加するか、既存のメンバーの役割を更新します。`user`（デフォルト）、`admin`、または`viewer`を受け入れます。ビューアーはダッシュボードと実行を読み取ることができますが、変更はできません。 | `organization_handle`, `email` |
| `invite_organization_member` | メールアドレスを組織に招待します。そのアドレスが既存のTuistユーザーに属しているかどうかは問いません。Tuistは14日後に期限切れになる受諾リンクをメールで送信します。サーバーがメールを送信できない場合、`email_sent`は`false`になり、リンクはダッシュボードからコピーする必要があります。`user`（デフォルト）、`admin`、または`viewer`を受け入れます。組織管理者権限が必要です。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 保留中の組織招待をキャンセルし、そのリンクを受諾できないようにします。組織管理者権限が必要です。 | `organization_handle`, `email` |
| `list_projects` | 認証済みユーザーがアクセスできるすべてのプロジェクトを一覧表示します。 | なし |
| `get_project` | プロジェクトの構成と接続されているリポジトリのURLを取得します。 | `account_handle`, `project_handle` |
| `connect_project_repository` | プロジェクトを、アカウントのGitHub AppインストールがアクセスできるGitHubリポジトリにリンクします。プロジェクトはリポジトリのデフォルトブランチを採用します。プロジェクト管理者権限が必要です。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | プロジェクトのGitHubリポジトリへのリンクを削除します。プロジェクト管理者権限が必要です。 | `account_handle`, `project_handle` |

#### アカウントトークン

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_account_tokens` | トークンの値を公開せずに、アカウントトークンのメタデータを一覧表示します。 | `account_handle` |
| `get_account_token` | トークンの値を公開せずに、アカウントトークンのメタデータを取得します。 | `account_handle`, `token_id` |
| `list_project_tokens` | トークンの値を公開せずに、プロジェクトトークンのメタデータを一覧表示します。 | `account_handle`, `project_handle` |

#### AIサブスクリプション

これらのツールは、認証済みユーザー自身のClaudeおよびChatGPTサブスクリプション（スレッドなどのAI機能向け）を管理します。ユーザー認証とAI機能へのアクセスが必要で、接続メタデータのみを返し、認証情報は一切返しません。切断すると保存された認証情報は削除されますが、プロバイダーでの認可は取り消されません。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_ai_subscriptions` | 各サブスクリプションが接続されているか、およびサーバーがそれを接続できるかを一覧表示します。 | なし |
| `connect_claude_subscription` | `claude setup-token`が出力するサブスクリプトントークンを保存します。トークンはクライアントとモデルを通過する秘密情報なので、明示的にのみ提供してください。ダッシュボードのAI設定に貼り付けると、会話に含まれなくなります。 | `token` |
| `start_chatgpt_subscription_login` | OpenAIデバイスサインインを開始し、ユーザーが入力する検証用URLとコード、および`login_id`を返します。15分後に期限切れになります。 | なし |
| `poll_chatgpt_subscription_login` | 保留中のサインインを確認します。ユーザーがコードを承認するまで`pending`、その後`connected`になります。 | `login_id` |
| `cancel_chatgpt_subscription_login` | 保留中のサインインをキャンセルします。接続済みのサブスクリプションは接続状態のままです。 | `login_id` |
| `disconnect_ai_subscription` | サブスクリプションの保存された認証情報と保留中のサインインを削除します。 | `provider` |

#### 通知ルール

これらのツールは、認証済みユーザー自身の通知ルールを管理します。新しいプレビューなどのイベントがルールのプロジェクト（リストされていない場合は通知可能なすべてのプロジェクト）で発生し、条件を満たすと、Tuistアプリデバイスへのプッシュ通知などのアクションを実行します。ルールがないと通知は受信できません。ユーザー認証が必要で、自分のルールに対してのみ動作し、自分が所属するアカウントのプロジェクトのみを受け入れます。ルールはすべてのアカウントにまたがるため、ダッシュボードページでは提供されません。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_notification_events` | ルールがサブスクライブできるイベントタイプを一覧表示します。各イベントには、その条件用のJSONスキーマが含まれます。 | なし |
| `list_notification_condition_options` | プロジェクト内のイベントに対する条件値（最近のプレビューのトラックやブランチなど）を提案します。 | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 自分のルールを一覧表示します。 | なし |
| `create_notification_rule` | イベント、オプションのプロジェクトと条件、および少なくとも1つのアクションからルールを作成します。 | `event`, `actions` |
| `update_notification_rule` | ルールの有効状態、プロジェクト、条件、またはアクションを変更します。 | `rule_id` |
| `delete_notification_rule` | ルールを削除します。 | `rule_id` |

#### 継続的インテグレーションランナー

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_runner_jobs` | アカウントの継続的インテグレーションランナージョブを一覧表示します。 | `account_handle` |
| `get_runner_job` | 継続的インテグレーションランナージョブを取得します。マシンのメモリ不足、停止した内容、変更すべき内容を含みます。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 継続的インテグレーションランナージョブのために記録されたステップを一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 継続的インテグレーションランナージョブのために記録されたマシンメトリクスを一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 継続的インテグレーションランナージョブのためにキャプチャされた最大500行のログを一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | アカウントの継続的インテグレーションワークフローの集計を一覧表示します。 | `account_handle` |
| `list_runner_profiles` | アカウントの継続的インテグレーションランナープロファイルを一覧表示し、各プロファイルの`runs-on`ラベルを含めます。 | `account_handle` |
| `get_runner_catalog` | ランナープロファイルが使用できるマシンシェイプとXcodeバージョンを一覧表示します。 | `account_handle` |
| `create_runner_profile` | プラットフォーム、マシンシェイプ、およびmacOSの場合はXcodeバージョンを指定してランナープロファイルを作成します。オプションで、キャッシュボリュームを保存するブランチを設定できます。アカウント管理権限または`account:runners:write`スコープが必要です。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | ランナープロファイルのマシンシェイプ、Xcodeバージョン、またはカスタムキャッシュボリュームの変更を保存するブランチを変更します。省略されたフィールドは値を維持します。アカウント管理権限または`account:runners:write`スコープが必要です。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | ユーザーの確認後にランナープロファイルを削除します。デフォルトのプロファイルは削除できません。アカウント管理権限または`account:runners:write`スコープが必要です。 | `account_handle`, `profile_name` |

ランナーボリュームツールは、Volumesダッシュボードと同じデータを公開します。読み取りツールにはランナーアクセスが必要ですが、クリア操作にはアカウント管理権限または`account:runners:write`スコープ、およびユーザーの確認が必要です。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_runner_volumes` | 名前とリポジトリでフィルタリングし、ボリュームをソートおよびページネーションします。 | `account_handle` |
| `get_runner_volume` | リポジトリ、プラットフォーム、容量、使用済みスペース、最終使用日時。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | ページネーションされたジョブおよびワークフロー参照、キャッシュステータス、ヒット結果、マウント時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | ジョブによってマウントされたボリューム。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | ストレージ時系列、ジョブ実行、ヒット率、傾向。オプションの`volume_id`、`start`、`end`（ISO 8601）。デフォルトは7日間、最大90日間。 | `account_handle` |
| `delete_runner_volume` | ボリュームとその保存内容を削除します。実行中のジョブはプライベートコピーを保持しますが保存はできず、同じキーの後続のジョブは空の状態から開始されます。 | `account_handle`, `volume_id` |

リストは`page`と`page_size`（最大100）を受け入れます。ボリュームインベントリはさらに`name`と`repository`（完全一致、AND結合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）、および`sort_order`（`asc`、`desc`）を受け入れます。不明な測定値とヒット結果は`null`のままです。キャッシュステータスはボリュームの変更が保存されたかどうかを示し、ジョブの成功ではありません。

#### サンドボックス

サンドボックスツールは、Sandboxesダッシュボードと同じデータとアクションを公開し、[API](https://tuist.dev/api/docs)と同じアクセス権を持ちます。アカウントメンバーはサンドボックスの一覧表示、取得、作成、一時停止、再開、削除を行えますが、エージェント環境、Amp、またはリモート実行を提供するサンドボックス、および分析・アーカイブツールにはアカウント管理権限が必要です。読み取り専用ビューアーは使用できません。アカウントでサンドボックスが有効になっている必要があります。ダッシュボードのサンドボックスページは読み取り専用ツールを登録します。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_sandboxes` | ステータス、シェイプ、タイムスタンプを含むサンドボックスをページネーションします。オプションの`search`（サンドボックス内のテキスト、Amp Orb、またはAnthropicセッションID）、`status`、`vcpus`、`sort_by`（`created`、`last_active`、`identifier`）、および`sort_order`。 | `account_handle` |
| `get_sandbox` | サンドボックスのステータス、シェイプ、ノード、アーカイブ、タイムスタンプ。 | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU時間、作成されたサンドボックス数、セッション、セットアップ、開始までの所要時間、およびアカウントの制限に対するピークvCPU、メモリ、ディスク使用量と傾向。オプションの`start`および`end`（ISO 8601）。デフォルトは30日間、最大90日間。 | `account_handle` |
| `create_sandbox` | 最小構成のサンドボックスを起動し、実行開始後に返します。オプションの`platform`（`linux`または`darwin`）、`template`、`memory_mb`付きの`vcpus`（Linux: 2x4096、4x8192、8x16384、デフォルト2x4096。macOS: 8x8192、8x16384、8x24576、デフォルト8x8192）、および`workspace_gb`。 | `account_handle` |
| `pause_sandbox` | 実行中のサンドボックスをそのノードのディスクにスナップショットします。 | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 一時停止中またはアーカイブ済みのサンドボックスを再開します。 | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 一時停止中のサンドボックスのディスクをオブジェクトストレージに移動するキューに入れます。 | `account_handle`, `sandbox_id` |
| `delete_sandbox` | ユーザーの確認後にサンドボックスとそのディスクを削除します。 | `account_handle`, `sandbox_id` |

#### Ampワークスペース

これらのツールは、OrbがトークンなしでTuistにサインインできるようにする<.localized_link href="/guides/server/authentication#amp-orbs">Ampワークスペース接続</.localized_link>を管理します。ダッシュボードのIntegrationsページと同じ管理者専用権限を使用します。Orb内のエージェントは、`$AMP_WORKSPACE_ID`および`$AMP_PROJECT_ID`から自身のIDを読み取れます。接続が許可するすべてのOrbはアカウント内のすべてのプロジェクトへのCIアクセス権を持つため、エージェントは接続前にユーザーに確認すべきです。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | アカウントに接続されているAmpワークスペースと、それぞれが制限されているプロジェクト（あれば）を一覧表示します。 | `account_handle` |
| `connect_amp_workspace` | Ampワークスペースを接続します。オプションの`project_id`は、サインインを1つのAmpプロジェクトのOrbに制限します。 | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | ワークスペースを切断します。Orbが既に持っているセッションは期限切れになるまで有効です。 | `account_handle`, `connection_id` |

#### Claude環境

これらのツールは、Claude Managed Agentsのセルフホスト環境を接続し、Settings → Integrations → Claudeと同様に、そのセッションをTuistサンドボックスで実行します。アカウント管理権限とサンドボックスの有効化が必要です。エージェントはAnthropicのAPIを使用して環境を作成できますが、環境キーを生成できるのはClaude Consoleのみであるため、エージェントはユーザーにそれを求めます。TuistはAnthropic APIキーまたはワークロードIDフェデレーションを使用してセッションを開始し、その認証情報で環境を取得してから保存します。Anthropic側のセットアップにはユーザー自身のAnthropic認証情報を使用しますが、Tuistはそれらを受け取りません。キーはクライアントとモデルを通過するため、明示的に提供する場合のみ指定してください。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_claude_environments` | 接続されている環境とそれぞれが使用する認証情報、さらにフェデレーションルールが信頼すべき発行者URLとサブジェクトプレフィックスを一覧表示します。 | `account_handle` |
| `connect_claude_environment` | `api_key`を使用して、または`organization_id`、`workspace_id`、`service_account_id`、`federation_rule_id`を使用して環境を接続します。オプションの`platform`、`vcpus`、`memory_mb`でサンドボックスのシェイプを設定します。 | `account_handle`, `environment_id`, `environment_key` |

#### Webhook

Webhookツールは、ダッシュボードと同じ管理者専用権限を使用します。配信試行にはエンドポイント用に記録されたリクエストおよびレスポンスデータが含まれますが、エンドポイントの署名シークレットは決して含まれません。

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_webhook_endpoints` | アカウントのWebhookエンドポイントを一覧表示します。 | `account_handle` |
| `get_webhook_endpoint` | Webhookエンドポイントを取得します。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | エンドポイントの配信試行を一覧表示します。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 配信試行を取得します。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcodeビルド

Xcode、Gradle、Bazel、Mix、Cargo向けのビルド詳細ツールは、既存の`custom_metadata: {tags, values}`構造を公開し、報告された場合はインフラストラクチャ観測値も含みます。値は文字列のまま保持され、不明なキーも保存されます。例えば、`tuist.cpu.available_processors`はランタイム時に利用可能な論理プロセッサ数を示し、`tuist.gradle.max_workers`はGradleワーカーの上限、`tuist.jvm.max_heap_bytes`はJVMヒープの上限（ホストメモリではありません）を示します。これらは信頼されていないクライアント観測値であり、検証済みのランナーIDではありません。観測値が存在しない場合は欠落したままとなり、インポートされたログや古いクライアントにはインフラストラクチャメタデータがない場合があります。メタデータの形式は、調整されたクライアント/プロトコルの更新を待っています。

| ツール | 説明 | 必須パラメーター |
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

`list_xcode_build_steps`はデフォルトで20ステップずつページを返します（`page_size`で最大100）。ナビゲーションには`page`と`pagination_metadata`を使用します。`search`を使用してタイトル、プロジェクト、またはターゲットを一致させるか、正確な`project`、`target`、`category`（例：`swiftCompilation`）、および`status`（`success`または`failure`）でフィルタリングします。`duration_ms`でソートすると遅い順（デフォルト）、`start_ms`でソートすると時系列順になります。ステップIDは同順位を解決し、64ビット精度を完全に保持するために10進数文字列として返されます。IDはビルドごとにスコープされ、ビルド間で一致させてはいけません。

オプションの`start_ms`と`end_ms`は、ビルド開始からのミリ秒単位の時間範囲と重複するステップを選択します（終了時間は除外されます）。どちらのツールも、ビルドUUIDまたはダッシュボードURLを`build_run_id`として受け入れます。返されたステップの`id`を`step_id`として変更せずに渡し、そのログを取得します。ログはステップあたり最大64 KiBまで保持され、`log_truncated`で省略された出力を示します。

Xcodeビルドの処理時に、ステップはデフォルトで収集されます。記録されたステップデータは90日間保持されます。リストレスポンスには`availability`が含まれます。記録されたステップが存在する場合は`available`（フィルタに一致するものがなくても）、ビルドがまだ処理中でステップがない場合は`processing`、ステップが記録されていないか期限切れの場合は`unavailable`となります。

同じ操作はHTTP APIの`GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps`および`GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}`で利用でき、同じフィルタとページネーションをサポートします。どちらもビルドのプロジェクトへの読み取りアクセス権が必要です。

#### Gradleビルド

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 完全な認証、プロジェクトセットアップ、Gradleプラグイン、キャッシュポリシー、および2回ビルドによる検証ワークフローを返します。エージェントは、既存のAndroidまたはGradleプロジェクトを編集する前にこれを呼び出すべきです。 | なし |
| `list_gradle_builds` | プロジェクトのGradleビルド実行をカスタムメタデータを含めて一覧表示します。オプションの`tag`パラメータでカスタムタグによってフィルタリングします。 | `account_handle`, `project_handle` |
| `get_gradle_build` | ビルドメタデータ、タスク/キャッシュのカウント、および`failures`（各失敗したタスクと構成ステップの失敗メッセージ）を取得します。 | `build_run_id` |
| `list_gradle_build_tasks` | タスクの結果、複合ビルドの識別子、キャッシュ可能性、増分ステータス、および失敗メッセージを一覧表示します。 | `build_run_id` |
| `list_gradle_build_steps` | 検索、メタデータ、および重複する時間フィルタを使用して、タイムスタンプ付きのタスク、構成、および変換を一覧表示します。 | `build_run_id` |
| `get_gradle_build_step` | 不透明なIDによって記録されたステップメタデータを検査します。失敗したタスクまたは構成ステップの`log`は、その失敗メッセージです。 | `build_run_id`, `step_id` |

GradleおよびBazelのステップリストはデフォルトで20件（最大100件）の結果を返し、`search`、正確な`project`、`target`、`category`、および`status`、重複する`start_ms` / `end_ms`フィルタ（終了は除外）、および`duration_ms`または`start_ms`による順序付けをサポートします。返されたIDは変更せずに渡してください。これらはビルドごとにスコープされます。リストは`time_origin`および`coverage`を公開します。古いGradleレポートは、ビルド開始がアップロードされていないため`first_recorded_timestamp`を使用します。Bazelプロファイルは、`trace_profile`カバレッジと時間原点としての`profile_start`を使用して、すべての記録された間隔を公開します。古いビルドは保持されたBEPサマリーにフォールバックします。ソースレコードは90日後に期限切れになります。Bazelの詳細には、公開された場合にサニタイズされたアクションログが含まれます。失敗したタスクまたは構成ステップのGradle詳細には、Tuist Gradleプラグインが`log`として報告した失敗メッセージ（例外メッセージとその原因チェーンをGradleのコンソールが表示する通り、スタックトレースやタスク出力なし、プロジェクト内のパスは相対パス化、認証情報やその他のローカルパスは編集済み、ステップあたり最大16 KiB、ビルドあたり最大32件の失敗ステップ）が含まれます。その他のGradleステップ、古いプラグインバージョンによって報告されたビルド、および認証情報なしのレポートでは、`log`はnullです。構成ステップは、失敗した場合に`failure`を、それ以外の場合は`unknown`を報告します。`compare_builds`プロンプトはこのカバレッジを使用して、完全なBazelトレースと保持されたサマリーを区別し、より広範な呼び出し出力を確認する前に、エージェントをアクションの結果とログのためのステップ詳細へ誘導します。

単一ステップツール`get_gradle_build_step`および`get_bazel_build_step`はIDによってステップを取得し、時間フィルタを受け入れません。時間範囲でステップをフィルタリングするには、対応するリストツールを使用してください。

保持されたサマリーから返されたBazelステップIDは、ステップの一覧表示と取得の間に完全なプロファイルが到着した場合でも読み取り可能です。ステップデータが期限切れになったインデックス付きプロファイルは、利用不可を報告します。Gradleステップリストには、持続時間がゼロのキャッシュ済みおよびスキップされた操作が含まれます。

#### Bazel呼び出し

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 認証、プロジェクトセットアップ、Bazel構成、および検証ワークフローを返します。 | なし |
| `list_bazel_invocations` | 完了した[Bazel Build Event Protocol](https://bazel.build/remote/bep)呼び出しを新しい順に一覧表示し、ビルドメトリクス、制限された実行タイムライン、クリティカルパス診断、およびプロジェクトに関連するリモートキャッシュの合計を提供します。`status`、`git_branch`、`git_commit_sha`、`is_ci`、および`command`でフィルタリングします。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | ビルドメトリクス、制限された実行タイムライン、クリティカルパス診断、および関連するリモートキャッシュの合計を含む、完了したBazel呼び出しを1件取得します。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | フィルタと明示的なカバレッジ付きで、記録されたBazelプロファイルの間隔を一覧表示します。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 記録されたBazelステップ、その公開されたアクションの結果、およびサニタイズされたログを検査します。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | Bazel呼び出しのためにキャプチャされたサニタイズされたログを実行順に一覧表示します。Bazelの進行状況出力の制限された末尾と`test.log`アーティファクトです。オプションの`stream`（`stdout`または`stderr`）、`source`（`progress`または`test_log`）、`target_label`、および`errors`フィルタで結果を絞り込むことができます。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bazel呼び出しのためにキャプチャされたサニタイズされたログチャンクを1件取得します。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 操作、エンドポイント、および観測時間を含む生のBazelリモートキャッシュ観測を一覧表示し、オプションで呼び出し、結果、または操作に絞り込むことができます。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 生のBazelリモートキャッシュ観測を1件取得します。 | `account_handle`, `project_handle`, `cache_event_id` |

`list_bazel_invocations`フィルタは完全一致であり、同じ秒で終了する呼び出しは呼び出しID順に並べ替えられます。ブランチ上の最新の失敗した呼び出しを見つけるには、`status: "failure"`、`git_branch`、および`page_size: 1`を指定して呼び出します。RESTエンドポイント`GET /api/projects/{account_handle}/{project_handle}/bazel/invocations`も同じフィルタを受け入れます。

テストログには、元のテスト結果の`target_label`と試行の`status`が含まれているため、`target_label: "//foo:bar_test"`はそのターゲットのテストログのみを返します。`errors: true`は、失敗した試行のテストログと、Bazelのレポーターが`ERROR:`、`FAIL:`、または`TIMEOUT:`で始まる行を含むstderr進行状況チャンクを返します。進行状況出力はターゲットに帰属せず、帰属が記録される前に書き込まれたログはフィールドが空になります。失敗したアクションとその出力は`list_bazel_build_steps`からターゲットごとに利用でき、テストケースごとの失敗はテスト実行ツールから利用できます。

#### Cargoビルド

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_cargo_builds` | プロジェクトのCargoビルドを新しい順に一覧表示します。`git_branch`、`status`、`is_ci`、または`command`でフィルタリングします。Cargoテストの実行結果はこのビルド一覧ではなく、テストツールを通じて利用できます。 | `account_handle`, `project_handle` |
| `get_cargo_build` | ビルドメタデータ、集計キャッシュカウンター、および診断情報付きで最大500件の記録されたコンパイラジョブを取得します。`compilations_truncated`は省略されたジョブを示し、診断情報は返されたジョブのみを対象とします。 | `account_handle`, `project_handle`, `build_id` |

`get_cargo_build`で`include_cache_inspection: true`を設定して、検証されたタスクの決定とCAS操作を4 MBの上限内で取得します。デフォルトでは、またレコードが欠落しているか無効な場合、`cache_inspection`はnullになります。部分的なキャプチャを示す`truncated`フラグを尊重してください。転送は各タスクヒットのローカル/リモートの起源を確立するものではありません。HTTP詳細エンドポイントも同じクエリパラメータを受け入れます。

#### Mixビルド

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_mix_builds` | プロジェクトのMix（Elixir）コンパイルビルドを新しい順に、カスタムメタデータを含めて一覧表示します。`git_branch`、`status`、`is_ci`、または`mix_env`でフィルタリングします。 | `account_handle`, `project_handle` |
| `get_mix_build` | ビルドメタデータ、診断カウント、および依存関係キャッシュの概要を取得します。 | `account_handle`, `project_handle`, `build_id` |

#### ビルドトレース

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `get_build_trace` | Xcode、Gradle、Bazel、またはMixビルドのタイムラインを[Perfetto](https://ui.perfetto.dev)で開けるトレースファイルとしてダウンロードするためのリンクを取得します。 | `account_handle`, `project_handle`, `build_id` |

`build_id`はビルド実行ID（Bazelの場合は呼び出しID）またはビルドのダッシュボードURLです。返される`trace_url`は[Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSONファイルを配信します。リンクを持っている人は誰でも、他の認証情報なしで`expires_at`（呼び出しから1時間後）までそのビルドのトレースをダウンロードできます。エージェントは`curl`でダウンロードし、それをあなたに渡してPerfettoで開かせたり、Perfettoの`trace_processor`でクエリしたりできます。トレースには、並列性によってレーンにパックされた記録されたステップ、ビルド全体にわたるトラック、およびビルドがマシンメトリクスを記録した場合のCPUおよびメモリーカウンターが含まれます。ログを除き、上記のステップツールと同じデータを保持しています。ダッシュボードでは、各ビルドの「Timeline」タブから同じファイルを利用できます。

#### Once実行

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_once_runs` | プロジェクトのOnce実行を新しい順に一覧表示します。`kind`（`build`、`test`、または`generic`）、`status`、`is_ci`、または`git_branch`でフィルタリングします。完了していない実行のステータスは`in_progress`です。 | `account_handle`, `project_handle` |
| `get_once_run` | アクションの合計、キャッシュの概要、およびテスト実行の場合はテストの合計を含む実行を取得します。 | `account_handle`, `project_handle`, `run_id` |

Cargoビルド、Mixビルド、およびOnce実行のIDはプロジェクト内で一意です。同じ読み取りはHTTP APIを通じて`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds`、および`.../once/runs`で利用でき、それぞれに1つのIDに対する詳細エンドポイントがあります。

#### タスク、アクション、モジュール、およびファイル

これらのプロジェクトスコープのツールは、実行間で永続的なビルドアイデンティティを検査します。`list_build_entities`から始め、返された安定した`id`と同じ`kind`を`get_build_entity`または`list_build_entity_history`に渡し、`account_handle`と`project_handle`も一緒に指定します。ビルドまたは呼び出しの識別子は必要ありません。

| ツール | 説明 | 必須パラメーター |
| --- | --- | --- |
| `list_build_entities` | プロジェクトのビルド全体で見られる1種類のタスク、モジュール、アクション、またはファイルを一覧表示します。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 選択した期間のネイティブアイデンティティと分析データを持つ1つのビルドエンティティを取得します。 | `account_handle`, `project_handle`, `kind`, `id` |
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

これらのツールは段階的にロールアウトされており、有効になっているプロジェクトのデータのみを返します。他のプロジェクトでは、空の結果ではなくエラーを返します。種類は、そのビルドツールチェーンを使用しているプロジェクトでのみ利用可能です。ツールは制限付きの`start_at`/`end_at`フィルター、`environment`（`any`、`ci`、または`local`）、および正確な`branch`を受け入れます。`list_build_entities`は`q`を受け付けます。`list_build_entity_history`は不透明な`after`/`before`カーソルをサポートします。不明なタイミングまたはキャッシュの観測は、ゼロまたはミスになるのではなく、利用不可のままとなります。履歴は、既存の実行ツールを使用したドリルダウンのために、記録された親とネイティブ実行を参照します。

`get_build_entity`のメトリクスには、タイミングが記録された観測の数である`duration_samples`が含まれます。実際のゼロ持続時間はカウントされますが、欠落しているタイミングはカウントされません。このカウントは観測カウントより低くなる可能性があります。利用できない持続時間統計はnullのままです。

Xcodeモジュールの持続時間は、ビルドログで測定されたターゲットコンパイルから得られます。モジュールキャッシュの解決とコンパイル作業のないターゲットは、持続時間のサンプルに貢献しません。コンパイルの観測はXcodeビルドを参照し、キャッシュイベントは生成またはキャッシュコマンドを参照します。

Bazelアクションは、ターゲットラベル、ニーモニック、および構成された主要な出力によって識別され、入力依存のキャッシュダイジェストに頼ることなく、別々のアクションと構成を区別します。履歴はキャッシュルックアップやトレースプロファイルフェーズではなく、BEPで報告された実行を記録します。完全な実行カバレッジには`--build_event_publish_all_actions`が必要です。アーティファクトの配信はベストエフォートであるため、欠落している観測は作業が実行されなかった証拠ではありません。安定したアイデンティティまたは実行開始のない古いKuraペイロードは受け入れられますが、インデックス化されません。終了時間の測定値がない場合は利用不可のままとなり、実際のゼロ持続時間はカウントされます。

Mixモジュールの持続時間は、独立して測定されたモジュール作業ではなく、包含ファイルのコンパイルを測定します。Onceアクションは、クライアントがターゲットマッピングを報告したときに宣言されたターゲット/機能/インデックススロットを使用します。診断ラベルだけでは安定したアイデンティティにはなりません。既存のクライアントと実行レベルのツールは変更なくサポートされ続けます。

Cargoクレートは、正確に記録されたクレートルート、名前、および種類によってグループ化されます。チェックアウトパスの変更により履歴が分割される可能性があり、ビルドプロファイル、機能、およびターゲットトリプルは区別されません。履歴はrustc呼び出しを測定し、ファイルごとの作業やキャッシュヒットは測定しません。欠落しているジョブは、削除や完全なワークスペース在庫の確立にはなりません。

分析読み取りにはメモリーと実行時間の制限があります。クエリがこれらの制限を超えると、ツールは空の結果を捏造する代わりにエラーを返します。

新しい観測はデプロイ後にインデックス化されます。この機能は既存の実行テレメトリをバックフィルしません。アイデンティティメタデータは<.localized_link href="/guides/server/data-retention">データ保持ポリシー</.localized_link>に基づき、個々の観測よりも長く保持されます。

#### テスト

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_test_runs` | プロジェクトのテスト実行を一覧表示します。`query`フィールドは`git_branch`、`scheme`、および`status`です。`field:"value"`は完全一致、`field~"value"`は大文字小文字を区別しない部分文字列一致、先頭の`-`はいずれかの演算子を否定します。例えば、`-git_branch~"gh-readonly-queue"`はマージキューブランチを除外します。空白で区切られたクエリフィルターと明示的な引数はANDセマンティクスで結合されます。 | `account_handle`, `project_handle` |
| `get_test_run` | テスト実行の詳細なメトリクスを取得します。結果バンドル（`.xcresult`）とセッションアーカイブの一時ダウンロードURLが含まれます。 | `test_run_id` |
| `list_test_module_runs` | 特定のテスト実行に対するテストモジュール実行を一覧表示します。 | `test_run_id` |
| `list_test_suite_runs` | 特定のテスト実行に対するテストスイート実行を一覧表示します。オプションでモジュールによるフィルターが可能です。 | `test_run_id` |
| `list_test_cases` | プロジェクトのテストケースを一覧表示します（`flaky`などのフィルターをサポート）。 | `account_handle`, `project_handle` |
| `get_test_case` | 信頼性レート、不安定性レート、および実行回数を含むテストケースの詳細なメトリクスを取得します。 | `test_case_id`または`identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | テストケース実行を一覧表示します。オプションでテストケースまたはテスト実行によるフィルターが可能です。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 特定のテストケース実行の失敗詳細と繰り返し情報を取得します。 | `test_case_run_id` |
| `list_test_case_run_attachments` | テストケース実行の添付ファイルを一覧表示します。各添付ファイルには一時ダウンロードURLが含まれます。 | `test_case_run_id` |
| `list_test_case_events` | ミュートやスキップなど、テストケースの状態変更を一覧表示します。 | `test_case_id` |
| `update_test_case` | テストケースの状態または不安定性分類を更新します。変更により、外部サービスを含む構成されたWebhookエンドポイントにイベントが送信される場合があります。 | `test_case_id`または`identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | テスト実行の選択的テストターゲット結果を一覧表示します。 | `test_run_id` |
| `get_coverage` | コミットまたはブランチの最新完全コミットにおいて、ターゲットを含むプロジェクトのコードカバレッジを取得します。`git_commit_sha`または`branch`がない場合、デフォルトブランチを読み取ります。 | `account_handle`, `project_handle` |
| `list_coverage_files` | コミットまたはブランチの最新完全コミットにおいて、コードカバレッジが測定したファイルとその行カバレッジを一覧表示します。`search`、ソート、およびページネーションをサポートします。 | `account_handle`, `project_handle` |
| `get_coverage_file` | コミットまたはブランチの最新完全コミットにおいて、ファイルのコードカバレッジとその関数を取得します。各行の実行回数を取得するには`include_lines`を設定します。 | `account_handle`, `project_handle`, `path` |

コードカバレッジツールは、コードカバレッジが有効になっているアカウントで利用できます。

#### バンドル

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_bundles` | プロジェクトのバンドル（アプリバイナリ）を一覧表示します。オプションで`git_branch`および`tags`によるフィルターが可能です（すべてのタグは完全一致する必要があります）。 | `account_handle`, `project_handle` |
| `get_bundle` | カスタムタグを含む特定のバンドルの詳細情報を取得します。 | `bundle_id` |
| `get_bundle_artifact_tree` | バンドルの完全なアーティファクトツリーをパス順にソートされたフラットリストとして取得します。 | `bundle_id` |

`list_bundles`は`tags: ["paid", "production"]`を受け入れ、ビルドフレーバーや環境を区別します。タグは大文字小文字を区別するラベルで、文字、数字、ハイフン、アンダースコアを含み、タグは最大10個、各タグは最大50文字です。一覧および詳細結果には`custom_metadata.tags`が含まれます。ページネーションカウントとブランチフィルターはタグ付けされた結果に適用されます。`tags`を省略すると、フィルターなしの動作が維持されます。無効なタグフィルターはクエリを広げるのではなくエラーを返します。

#### ジェネレーション

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_generations` | プロジェクトのジェネレーション実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_generation` | 特定のジェネレーション実行の詳細情報を取得します。 | `generation_id` |

#### キャッシュ実行

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_cache_runs` | プロジェクトのキャッシュ実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_cache_run` | 特定のキャッシュ実行の詳細情報を取得します。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | ジェネレーションまたはキャッシュ実行のモジュールキャッシュターゲットを一覧表示し、ターゲットごとのキャッシュヒット/ミスステータスと、追加のハッシュ入力を含む診断コンポーネントハッシュを表示します。 | `run_id` |

#### プレビュー

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_previews` | プロジェクトの共有可能なアプリプレビューを一覧表示します。 | `account_handle`, `project_handle` |
| `get_preview` | プレビューとそのビルドの一時ダウンロードURLを取得します。 | `preview_id` |
| `get_latest_preview` | 実行中のアプリバイナリの最新プレビューを検索します。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自動化

| ツール | 説明 | 必須パラメーター |
|------|-------------|---------------------|
| `list_automation_alerts` | プロジェクトの自動化アラートを一覧表示します。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 自動化アラートを取得します。 | `alert_id` |
| `list_automation_alert_revisions` | 自動化アラートのリビジョン履歴を一覧表示します。アクション認証情報はマスキングされます。 | `alert_id` |
| `list_project_notification_alerts` | プロジェクト通知アラートルールを一覧表示します。ダッシュボード設定ページと同じ管理者権限が必要です。Webhookアドレスはマスキングされます。 | `account_handle`, `project_handle` |

### イベント

ステートレスな`2026-07-28` Model Context Protocolライフサイクルを使用するクライアントは、`events/list`を呼び出してイベントとそのペイロードスキーマを発見できます。

| イベント | 送信タイミング | サブスクリプションフィルター |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | テストケースが非不安定から不安定に変更されたとき。 | `account_handle`, `project_handle` |
| `build.failed` | ローカルまたは継続的インテグレーションのXcode、Gradle、またはBazelビルドが失敗で完了したとき。 | `account_handle`, `project_handle` |
| `test_run.failed` | ローカルまたは継続的インテグレーションのテスト実行が失敗で完了したとき（マージされたシャーディング実行または放棄された実行を含む）。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuistランナーのジョブが失敗で完了したとき。 | `account_handle` |

サブスクライブするには、クライアントはイベント名、上記の`arguments`にリストされたハンドル、および`https://`コールバックURLと`whsec_`署名シークレットを含む`webhook`配信を使用して`events/subscribe`を呼び出します。プロジェクトイベントにはアカウントメンバーシップと対応するテストまたはビルドデータへの読み取りアクセスが必要です。ランナーのジョブイベントにはアカウントメンバーシップとランナーへの読み取りアクセスが必要です。承認済みの[`auth.md`](https://workos.com/auth-md)アクセストークン、承認済みのアカウントトークン、およびブラウザ認証グラントはサブスクリプションを作成できます。関連する認証情報が有効でなくなると配信は停止します。各ユーザーは最大25件のアクティブなサブスクリプションを保持できます。Tuistはサブスクリプションを保存する前にコールバックに検証チャレンジを送信します。コールバックは同じ`challenge`値を含むオブジェクトを返す必要があります。サブスクリプションのデフォルト有効期間は7日で、再度サブスクライブすることで更新でき、ユーザーのアクセスまたは認証情報が削除されると配信が停止します。オプションの`ttlMs`は1時間から30日の範囲に制限されます。Tuistはタイムアウトしたコールバックを再試行し、5分間にわたる少なくとも3回の連続タイムアウト後にサブスクライブを解除します。コールバックを復旧した後、再度サブスクライブしてください。

イベントが発生すると、Tuistはそのリソース識別子とダッシュボードURLをコールバックに送信します。ビルドおよびテスト実行の失敗には`is_ci`と`git_branch`も含まれるため、クライアントはローカルの失敗を無視したり、ブランチでフィルターしたりできます。ビルドイベントには`build_system`が含まれます。ランナーのジョブイベントには`workflow_job_id`と`workflow_run_id`の両方が含まれます。リクエストにはサブスクリプション識別子と[Standard Webhooks](https://www.standardwebhooks.com/)署名ヘッダーが含まれており、クライアントは発信元を検証できます。Tuistは失敗した配信を再試行するため、クライアントは安定した`eventId`を使用して重複を除外する必要があります。ペイロードにはテスト名、ログ、および失敗メッセージは含まれません。クライアントは上記のツールを通じてこれらの詳細を取得し、チームに通知するかデバッグを開始するかを決定できます。クライアントは`events/unsubscribe`を使用して配信を停止できます。

### プロンプト

| プロンプト | 説明 |
|--------|-------------|
| `fix_flaky_test` | 失敗パターンを分析し、根本原因を特定して、対象を絞った修正を適用することで、不安定なテストの修正をガイドします。 |
| `compare_builds` | ビルドを比較してパフォーマンスの劣化、キャッシュの変更、およびビルドの問題を特定する手順をガイドします。Xcode、Gradle、Bazel、およびCargoプロジェクト用のネイティブツールを使用します。Cargoの比較では部分的なコンパイラカバレッジを維持し、推定されるコンパイラの作業量と経過時間による節約を区別します。 |
| `compare_test_runs` | 2つのテスト実行を比較して、劣化、新しい失敗、および不安定なテストを特定する手順をガイドします。 |
| `compare_bundles` | 2つのバンドルを比較して、アーティファクトツリー全体のサイズ変更を特定する手順をガイドします。 |
| `compare_test_case` | 2つのブランチまたは期間にわたるテストケースの動作を比較する手順をガイドします。 |
| `compare_generations` | 2つのジェネレーション実行を比較して、パフォーマンスの劣化とモジュールキャッシュの変更を特定する手順をガイドします。 |
| `compare_cache_runs` | 2つのキャッシュ実行を比較して、キャッシュ効率の変化とターゲットレベルの劣化を特定する手順をガイドします。 |
| `integrate_gradle_project` | 既存のGradleプロジェクトにTuistを統合する手順をガイドします。ツールとGradleの個別の認証、アカウントの検出、プロジェクトの作成、リモートキャッシュポリシー、ビルドインサイト、および読み戻し検証が含まれます。 |
| `integrate_bazel_project` | Bazelプロジェクトの作成または選択、コマンドラインの認証、リモートキャッシュとビルドインサイトの構成、そしてTuistビルドデータによる統合の検証を行う手順をガイドします。 |
| `integrate_xcode_project` | 既存のXcodeプロジェクトにTuistを統合する手順をガイドします。Xcodeキャッシュ、ビルドインサイト、テストインサイト、およびテストシャーディングをサポートします。 |
| `ask_tuist` | 公開情報を文脈として使用し、現在の動作の真実の源として焦点を絞った実装とテストの証拠を用いて、Tuistに関する質問に回答します。`question`が必要で、リビジョン固定の証拠を引用します。 |

プロジェクトデータのプロンプトは`account_handle`と`project_handle`を受け取り、調査範囲を特定のプロジェクトに限定します。比較プロンプトは、比較対象の2つの項目（ID、ダッシュボードURL、またはブランチ名で指定）を指定するための`base`および`head`引数も受け入れます。`ask_tuist`はプロジェクトパラメータの代わりに`question`を受け入れます。`integrate_gradle_project`は、適用するGradle統合のコンマ区切りリストである`features`も受け入れます：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests`、および`test_sharding`。`integrate_bazel_project`は、セルフホスト型またはローカルインストール用のオプションの`server_url`を受け入れます。`integrate_xcode_project`は、`xcode_cache`、`build_insights`、`test_insights`、および`test_sharding`を含む`features`を受け入れます。

#### Gradle統合プロンプトの機能

`integrate_gradle_project`プロンプトと`get_gradle_integration_guide`ツールは、完全なセットアップワークフローを文書化しています。このツールはサーバーの初期化手順でも参照されており、プロンプトを列挙しないエージェントからも発見可能になります。

| 機能 | エージェントが構成する内容 |
|---------|---------------------------|
| `remote_cache` | Gradleのビルドキャッシュを有効にし、Tuistのリモートキャッシュアップロードポリシーを構成し、ローカルでの読み取り専用使用を持つ継続的インテグレーションランナーからのみアップロードすることを推奨します。 |
| `build_insights` | Tuist Gradleプラグインを適用し、必要に応じてビルド分析のアップロード動作を構成します。 |
| `test_insights` | Tuist Gradleプラグインを適用し、Gradle `Test`タスクの結果が自動的にアップロードされるようにします。 |
| `flaky_tests` | 不安定なテストの検出、オプションのGradle Test Retryプラグインの使用、およびテスト検疫の構成のためのセットアップをガイドします。 |
| `test_sharding` | `tuistPrepareTestShards`、シャードマトリックス生成、および`TUIST_SHARD_INDEX`に基づくテスト実行のための継続的インテグレーションワークフローを追加します。 |

`features`が省略された場合、プロンプトはエージェントにユーザーが希望する統合を明確にするよう求め、またはGradleプロジェクトを編集する前にリクエストから最小限の実用的なセットを推論します。

#### Xcode統合プロンプトの機能

`integrate_xcode_project`プロンプトは、TuistがサポートするすべてのXcode統合を文書化しています：

| 機能 | エージェントが構成する内容 |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`、生成されたプロジェクトのキャッシュ設定、手動のXcodeキャッシュビルド設定、および継続的インテグレーションランナーに限定されたアップロードポリシーを構成します。 |
| `build_insights` | `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath`、および`tuist setup insights`を通じたオプションのマシンメトリクスを構成します。 |
| `test_insights` | `tuist inspect test`、スキームテストのポストアクション、および継続的インテグレーションテスト実行用の結果バンドル生成を構成します。 |
| `test_sharding` | `TUIST_SHARD_INDEX`を使用したXcodeまたは生成されたプロジェクトのシャード計画とシャード実行ワークフローを追加します。 |

`features`が省略された場合、プロンプトはエージェントにユーザーが希望する統合を明確にするよう求め、またはXcodeプロジェクトを編集する前にリクエストから最小限の実用的なセットを推論します。
