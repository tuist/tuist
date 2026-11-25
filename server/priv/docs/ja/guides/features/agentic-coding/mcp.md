---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · エージェント型コーディング · 機能 · ガイド · Tuist",
  "description": "Tuist の MCP エンドポイントを通じて、AI エージェントにテストインサイトなどへのアクセスを提供します。"
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro)は、AIエージェントが外部サービスやデータソースと対話できるようにするオープンスタンダードです。[Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/)などのアプリケーションや、[Zed](https://zed.dev)、[Cursor](https://www.cursor.com)、[Visual Studio Code](https://code.visualstudio.com)などのエディタをTuistと相互運用可能にします。

Tuistは`https://tuist.dev/mcp`にサーバーサイドのModel Context Protocolエンドポイントをホストしています。クライアントをこのエンドポイントに接続することで、エージェントはテストインサイト、flakyテスト分析などを含むTuistプロジェクトデータにアクセスできます。ほとんどのツールは、認証済みユーザーがダッシュボードで既に閲覧できるTuistデータを読み取ります。各ツールは、読み取り専用かどうか、元に戻しにくい変更を引き起こす可能性があるか（`destructiveHint`）、およびTuistの外部にアクセスできるか（`openWorldHint`）を示すアノテーションを公開します。状態を変更するツールは、アカウントまたはプロジェクトに対するユーザーの権限によって制限されます。

- **組織とメンバー**：`create_organization`、`add_organization_member`（既存のユーザーを追加するか、メンバーのロールを変更）、`invite_organization_member`（任意のアドレスに招待メールを送信）、および`cancel_organization_invitation`。
- **プロジェクト**：`create_project`、`start_project_logo_upload`および`complete_project_logo_upload`（ロゴを置き換え）、`connect_project_repository`および`disconnect_project_repository`（GitHubリポジトリのリンク）。
- **テスト**：`update_test_case`（テストケースをミュート、スキップ、再有効化、またはflakyとしてフラグ付け；変更はアカウントのWebhookエンドポイントに到達する可能性があります）。
- **通知ルール**：`create_notification_rule`、`update_notification_rule`、および`delete_notification_rule`。
- **CIランナー**：`create_runner_profile`、`update_runner_profile`（キャッシュボリュームを保存するジョブを絞り込むと、保留中の保存が破棄されます）、`delete_runner_profile`、および`delete_runner_volume`（ボリュームの保存内容を削除）。
- **サンドボックス**：`create_sandbox`、`pause_sandbox`、`resume_sandbox`、`extend_sandbox`、`archive_sandbox`、`delete_sandbox`（ディスクを削除）、およびサンドボックスのデバイス（現在のmacOSサンドボックスのiOSシミュレーター）での`boot_sandbox_device`、`launch_sandbox_app`、`open_sandbox_url`。
- **フィードバック**：`report_feedback`（ツールやプロンプトに関するレポートをTuistチームに送信；tuist.devのみ）。
- **Organization AI**：`save_organization_ai_model`、`remove_organization_ai_model`、`set_organization_ai_default_model`、`save_organization_ai_task_route`、`remove_organization_ai_task_route`、および`remove_organization_ai_provider`（プロバイダーのキーとモデルを削除し、AnthropicでリンクされたClaude組織とのリンクを解除）。
- **エージェント統合**：`connect_amp_workspace`（ワークスペースのorbsにアカウントへのCIアクセスを付与）、`disconnect_amp_workspace`、および`connect_claude_environment`（Claude Managed Agents環境がTuistサンドボックスでセッションを実行できるようにする）。

`add_organization_member`、`cancel_organization_invitation`、`complete_project_logo_upload`、`disconnect_project_repository`、`update_test_case`、`update_notification_rule`、`delete_notification_rule`、`update_runner_profile`、`delete_runner_profile`、`delete_runner_volume`、`delete_sandbox`、`disconnect_amp_workspace`、`remove_organization_ai_provider`、`remove_organization_ai_model`、および`remove_organization_ai_task_route`は、既存の状態を置き換えたり削除したりするため、`destructiveHint: true`を公開します。`invite_organization_member`、`update_test_case`、`connect_claude_environment`、`remove_organization_ai_provider`、および`report_feedback`は、メールの送信、外部Webhookエンドポイントへの通知、Anthropicへの呼び出し、またはTuistチームへのレポート送信を行うため、`openWorldHint: true`を公開します。

個人のClaudeおよびChatGPTサブスクリプションはダッシュボードのAI設定でのみ接続されるため、サブスクリプショントークンやサインイン情報がModel Context Protocolクライアントを経由することはありません。アカウントセットアップツールにはユーザー認証が必要です。プロジェクトトークンや通常のアカウントトークンでは利用できません。ユーザーがブラウザでクライアントを承認するか、`auth.md`登録を主張すると、TuistはそのクレデンシャルをModel Context Protocolエンドポイント上でのみユーザーに関連付け、セットアップツールが要求されたワークフローを完了できるようにします。誰でもクライアントを登録できるため、ブラウザで承認すると、クライアント名とアクセス送信先のホストを表示する同意ページが表示され、そこで承認されて初めてTuistがクレデンシャルを発行します。スコープを要求しないクライアントには`mcp`スコープグループが付与されます。クライアントは`S256`を使用したPKCEを使用する必要があり、リダイレクトURIはHTTPS、ループバックアドレス上のHTTP、またはアプリケーション固有のスキームを使用する必要があります。

Tuistは[2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)を実装しています。リクエストはステートレスです：クライアントは各リクエストとともにプロトコルメタデータを送信し、初期化なしで直接ツールを呼び出すことができます。`server/discover`はサーバーの識別情報、機能、サポートされているバージョン、および手順を返します。セッション識別子や独立したイベントストリームはありません。2025-06-18または2025-03-26の初期化フローを使用するクライアントも引き続きサポートされており、これらもサーバーセッションなしで動作します。

## Model Context Protocolとスキル

Model Context Protocolツールと<.localized_link href="/guides/features/agentic-coding/skills">スキル</.localized_link>は、その機能において重複する可能性があります。現在の重複状況を考慮し、同じワークフロー内で両方を混在させるのではなく、ワークフローごとに一つのアプローチを選択し、一貫して使用してください。

プラグインインストールをサポートするクライアントの場合、<.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link>を使用して両方を一緒にインストールしてください。

## 設定

クライアントのリモートModel Context Protocolサーバーとして`https://tuist.dev/mcp`を追加してください。サーバーの初期化手順と公開サーバーカードは、エージェントに外部の認証ドキュメントを取得またはフォローさせることなく、動的クライアント登録を用いたOAuth 2.0と標準的なブラウザ認可フローをインラインで説明しています。これらのサーバー全体の指示はワークフローガイダンスを一般的なものに保ちます：ツールの認証はローカルコマンドラインツールやビルドシステム統合を認証せず、エージェントは関連するTuistツールを通じて要求された変更を確認すべきです。ビルドシステム固有のセットアップと認証チェックは、統合ガイドとプロンプトに記載されています。Tuistは引き続き[Open Authorization](https://oauth.net/2/)ディスカバリーメタデータと現在の[auth.md protocol](https://workos.com/auth-md)を`https://tuist.dev/auth.md`で個別に公開しています。

組織のいずれかがシングルサインオンを強制している場合、ブラウザでクライアントを承認するにはその組織経由でサインインしたセッションが必要であり、必要に応じてTuistはまずプロバイダーにリダイレクトします。<.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">single sign-on</.localized_link>を参照してください。

このエンドポイントは、古いセッションベースのライフサイクルに加えて、ステートレスな`2026-07-28` Model Context Protocolリクエストライフサイクル（`server/discover`を含む）を受け入れます。既存のクライアントは現在の接続方法を继续使用できます。

Model Context Protocolイベントをサポートするクライアントは、プロジェクトイベントをサブスクライブできます。利用可能なイベントと配信要件については[Events](#events)を参照してください。

リモートブラウザ認証をすでにサポートしているクライアントは、ブラウザでの認証を継続できます。`auth.md`をサポートするクライアントとエージェントは、匿名で登録したり、信頼されたプロバイダーのIDアサーションを提示したり、サービス認証付きのEメールクレームを開始したりできます。登録によりTuist署名付きのIDアサーションが返され、エージェントはこれを標準トークンエンドポイントで1時間有効のアクセストークンと交換します。Tuistは公開署名鍵を公開し、標準的なトークン取り消しとプロバイダーのセキュリティイベント配信をサポートしています。

認証されていないエージェントは、Model Context Protocolエンドポイントから返される`WWW-Authenticate`ヘッダーを読み取り、保護リソースメタデータと認可サーバーメタデータを取得して、その`agent_auth.skill`URLに従う必要があります。Tuistは、言語モデル駆動型クライアントがネイティブクライアント統合に頼らずにフローを発見できるよう、未承認レスポンスボディにも同じローカルの`auth_md`URLを返します。デプロイメントローカルのドキュメントが、エンドポイント名、リクエストボディ、クレームポーリング、およびアサーション交換に関する信頼できる情報源となります。

エージェントがEメールクレームを開始する前に、ユーザーにTuistアカウントのEメールアドレスを確認してもらう必要があります。プロバイダーのプロフィール、Git設定、環境変数、またはセッションメタデータからそのアドレスを推測してはいけません。

このエンドポイントは`mcp`スコープグループを使用します。匿名の事前クレーム資格情報は機能の発見や公開統合ガイダンスの読み取りが可能ですが、サインインしたユーザーとしては扱われません。ブラウザ認可またはクレーム後、資格情報はユーザー範囲となり、各ツールはダッシュボードと同じ認可チェックを適用します。詳細については<.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>を参照してください。

ツールは、認証済みユーザーがすでに読み取り権限を持つプロジェクトに解決されます。XcodeおよびGradleビルドツールは、ビルドUUIDまたはダッシュボードURLを受け入れます。UUIDは正確に1つのプロジェクトを識別する必要があります。複数のプロジェクトに現れる場合、ツールは他のプロジェクトのレポートを選択する代わりに「見つかりません」を返します。プロジェクトスコープのダッシュボードおよびAPI読み取りは利用可能です。報告されるアクター識別子は未検証のラベルであり、資格情報や追加のアクセス権ではありません。

ビルド一覧および詳細ツールはオプションの`tuist_version`メタデータを公開します。XcodeおよびCargoの場合は報告用Tuist CLI、Gradleの場合はTuist Gradleプラグイン、Mixの場合は`tuist_ex`ライブラリです。Xcodeはまた、リンクされたプロジェクト生成イベントから`tuist_generation_version`を公開します。これはアップロード用CLIとは異なる場合があります。欠落している観測値はnullであり、サーバーや他のレポートから推測されることはありません。Bazelは既存の`bazel_version`を使用し、Struo実行詳細は`once_version`を公開します。これらのフィールドは報告されたバージョンを示すものであり、検証済みのIDやワイヤー契約バージョンではありません。RESTビルドエンドポイントも同じメタデータを公開します。既存の統合およびflaky-testスキルはバージョンフィールドに依存せず、ワークフローの変更は不要です。

顧客のアカウントを調査するTuistオペレーターは、すべての呼び出しを記録するTuistの内部運用ツールを通じてこれを行います。このエンドポイントへの直接接続では、ユーザー自身のメンバーシップを超えるアクセスは得られません。

### Pulse

Pulseは、`account_handle`で指定されるアカウントの運用メトリクス、ログ、トレース、およびエラーに対する読み取り専用ツールを公開します。最初の3つはPulseページとそのREST APIを反映しており、残りの5つはエージェントがテレメトリーを直接探索できるようにするもので、REST相当機能はありません。

| ツール | 目的 | `/api/accounts/:account_handle/pulse`以下のREST相当機能 |
| --- | --- | --- |
| `query_pulse` | Pulseページテーブル | `GET /:signal` |
| `get_pulse_analytics` | Pulseページウィジェット | `GET /:signal/analytics` |
| `get_pulse_error_issue` | 1つのエラ―課題とそのイベント | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | インスタントまたはレンジPromQL | なし |
| `list_pulse_labels` | ラベル名、または1つのラベルの値 | なし |
| `search_pulse_logs` | フィルター済みログエントリー | なし |
| `search_pulse_traces` | フィルター済みスパン | なし |
| `get_pulse_trace` | 1つのトレースのすべてのスパン | なし |

Pulseは、アカウントまたはプロジェクトが公開されている場合でも、サーバー構成組織の現在のメンバーに制限されています。ユーザー認証、またはユーザー関連付けられた`mcp`資格情報とアカウント読み取り権限が必要です。プロジェクトトークン、通常のアカウントトークン、匿名登録、および組織メンバーシップのないオペレーターアクセスは、Pulseへのアクセスを付与しません。資格情報は他のバックエンドやテレメトリーテナントを選択できず、サーバー構成アカウントのみがPulseテレメトリーを持つため、どのツールも他のアカウントのデータを読み取ることはできません。ブラウザエージェントは、そのページのアカウントスコープ内にあるPulseページ上でのみこれらのツールを受け取ります。

RESTにはユーザー資格情報が必要です。OAuthおよび`auth.md`ユーザー関連付けは`/mcp`エンドポイントでのみ利用可能です。関連するアカウントのメンバーシップや可視性に関係なく、現在のユーザーを持たないアカウント資格情報は拒否されます。

`query_pulse`は`signal`（`metrics`、`logs`、`traces`、または`errors`）、オプションの`query`、および`range`（`15m`、`1h`、`6h`、または`24h`、デフォルト`1h`）を取ります。メトリクスはPromQL式を受け入れます。ログ、トレース、およびエラーは、ログ本文、スパン名、およびエラ―課題タイトルに対してマッチングされる大文字小文字を区別しないリテラルテキストを受け入れます。デフォルトである`*`はすべてを選択します。トレース行は個々のスパンです。エラー行は課題です。サービスとフィンガープリントでグループ化されたイベントであり、そのイベント数、影響を受けたアカウント、ウィンドウ内の最初と最後の発生、および最新イベントのタイトル、原因、レベル、プラットフォームを含みます。テーブルは`search`、`page`（デフォルト`1`）、`page_size`（`1`–`100`、デフォルト`20`）、`sort_by`、および`sort_order`（`asc`または`desc`）を受け入れます。ソート列はシグナルに依存し、ツールスキーマに記載されています。フィルターには`service`、およびログとエラー用の`level`が含まれます。フィルター演算子は対応する`_op`引数（`eq`、`contains`、または`not_contains`）を使用し、デフォルトでは完全一致となります。

ソート列は、メトリクス用には`name`/`value`、ログ用には`timestamp`/`service`/`level`/`message`/`trace_id`、トレース用には`timestamp`/`service`/`name`/`duration_ms`/`trace_id`、エラー用には`last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level`です。ダッシュボードは意図的にサブセットのみを公開していますが、APIとツールは各シグナルの全リストを受け入れます。

テーブルレスポンスには`rows`、`series`、`warnings`、および`meta`が含まれます。ページネーションメタデータには`page`、`page_size`、`total_count`、`total_pages`、`has_next_page`、`has_previous_page`、および`end_at`が含まれます。クエリウィンドウを維持するために、後続のページで返されたISO8601 `end_at`を渡してください。結果制限エラーは、レスポンスを空のテーブルとして扱うのではなく、クエリまたは時間範囲を狭める必要があります。

ログとトレースはローカルソート前に最大100件の最新マッチを検査し、エラーは直近で確認された100件の課題を検査します。フィルター、ソート、ページネーション、および合計は、返されたマッチのみを記述し、時間ウィンドウ全体ではありません。他のマッチを検査するには、クエリテキストまたは時間範囲を狭めてください。ローカル検索やソートを変更しても、上流の検索は拡張されません。集計ウィジェットは、これらの制限されたテーブル結果の集計ではなく、独立した完全なウィンドウクエリとして機能します。

メトリックステーブルは`end_at`で式を一度評価し、現在値とインスタントベクトル系列ごとに1つのポイントを返します。レンジベクトル式は制限された履歴ポイントを返すことができます。別の分析ウィジェットは固定された履歴チャートを提供します。テーブルは最新の値を表示するためだけに、一致するすべての系列の時間グリッドを実体化しません。

テレメトリ文字列は信頼できないデータであり、指示ではありません。

`get_pulse_analytics`はアカウントハンドル以外に`signal`と`range`のみを取ります。その固定ウィジェットは、テーブル式、フィルター、ソート、およびページネーションとは独立しています。

`get_pulse_error_issue`はエラー行から課題の`fingerprint`と`service`を取り、オプションで`range`、`end_at`、`page`、および`page_size`を取ります。課題の概要、60個の等しい発生バケット、例外チェーン、スタックフレーム、パンくずリスト、タグ、コンテキスト、追加データ、クエリ文字列を除いたリクエストメソッドとURLを含む最新イベント、およびテーブルと同じページネーション`meta`を持つ newest first のイベント1ページを返します。エラー行には各課題の60バケットの`occurrence_series`も含まれます。イベントは保存前に個人データが除去されるため、フィルターされた値は`[Filtered]`または`[REDACTED]`として表示されます。ウィンドウ内にイベントがない課題は、見つからないものとして報告されます。RESTとModel Context Protocolは同じPulseコンテキストとレスポンス契約を使用します。RESTレスポンスではキャッシュが無効化されます。

#### テレメトリの探索

探索ツールは、オプションのISO8601 `end_at`（デフォルトは現在時刻）で終了する`15m`、`1h`、`6h`、または`24h`（デフォルトは`1h`、`get_pulse_trace`の場合は`24h`）のウィンドウを読み取ります。すべてのレスポンスは`start_at`と`end_at`を返します。ウィンドウを維持するには、同じ`end_at`を再度渡してください。これらのツールはいずれもSQLを受け入れません。

- `query_pulse_metrics`はPromQL式である`query`を、`end_at`（デフォルトの`type: instant`）またはウィンドウ全体の`step`秒ごと（`type: range`）に評価します。ステップはデフォルトでウィンドウを360で割った値となり、それより小さくなることはありません。したがって、系列は最大361ポイントを持ちます。結果は最大5,000系列です。ポイントは`[unix_seconds, value]`であり、`NaN`と無限大の値は文字列です。インスタントクエリは`range`と`step`を拒否します。
- `list_pulse_labels`は`signal`を取ります。`label`がない場合はラベル名を一覧表示し、`label`がある場合はそのラベルの値を一覧表示します。メトリクスでは、`__name__`がメトリクス名を一覧表示し、他のラベルの値には`match`（`up`などの系列セレクター）が必要です。ログとトレースのラベル値は`filters`を受け入れます。トレースラベル名はトレーススキーマから取得されるため、これを受け入れません。ログとトレースの値にはウィンドウ内のエントリー数が含まれ、頻度の高いものが先に表示されるため、サービス別エラーなどの内訳としても機能します。`search`はリテラルテキストを含む名前または値のみを保持し、`limit`は`1`–`1000`（デフォルト`100`）を受け入れます。ログラベル名の検出は、各種類の属性セットを最大1,000個検査し、フィルターが受け入れるキーのみを一覧表示します。
- `search_pulse_logs`は最大`limit`件のエントリー（`1`–`100`、デフォルト`50`）を、`newest`または`oldest`順で返します。本文に`text`を含み、すべてのフィルターに一致するものが対象です。各エントリーには、`severity_text`、`body`、`trace_id`、`span_id`、`scope_name`、およびマージされたリソースとログの`attributes`が含まれます。`span_id`と`scope_name`は、OTLPログ送信者だけが設定するKubernetesから収集されたログの場合、`null`になります。
- `search_pulse_traces`は最大`limit`件のスパンを、`newest`、`oldest`、または`slowest`順で返します。すべてのフィルター、オプションの`min_duration_ms`と`max_duration_ms`、および`root_only`に一致するものが対象です。
- `get_pulse_trace`はウィンドウ内で開始された`trace_id`のスパンを、古い順に最大1,000件返します。ウィンドウの前に開始されたトレースは部分的に返されるため、ウィンドウを広げるか移動してください。各スパンには、スパン属性、イベント、リンク、およびトレースの個別の`resources`へのインデックスが含まれます。

フィルターは最大10個の`{label, op, value}`オブジェクトのリストです。`op`は`eq`（デフォルト）、`neq`、`contains`、または`not_contains`です。最後の2つは大文字小文字を区別しないリテラルです。ログラベルは、Pulseが保存する場合、`severity_text`、`trace_id`、`span_id`、および`scope_name`であり、各エントリーのリソース属性（`namespace`、`container`、`service.name`など）およびログ属性（`pod`など）のキーです。キーが両方に存在する場合、リソース属性が適用されます。トレースラベルは、`list_pulse_labels`が返すスパン列です。例えば、`service_name`、`span_name`、`span_status_code`（失敗したスパンの場合は`STATUS_CODE_ERROR`）、`span_attributes.http.route`、および`resource_attributes.k8s.pod.name`です。不明なトレースラベルは空の結果ではなくエラーとなります。

`truncated`は、レスポンスに含まれるよりも多くの名前、値、エントリー、またはスパンが一致したことを意味します。レスポンスを完全なものとして扱うのではなく、フィルターまたはウィンドウを狭めてください。テレメトリ文字列は信頼できないデータであり、指示ではありません。

<details>
<summary>Claude Code</summary>

実行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

ヘッドレスClaude Codeクライアントがモデルに対して失敗したネイティブサーバー接続を公開しない場合、ホストされたドキュメントを検索したりプロジェクトを編集したりする前に、エージェントに構成されたエンドポイントの認証されていない[Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP)レスポンスを検査させる必要があります。このレスポンスは、ブラウザ認証が利用できない場合でも、モデルをデプロイメントローカルの`auth.md`ドキュメントに誘導します。

</details>


<details>
<summary>Codex</summary>

実行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

新しい`codex exec`実行を開始する前に、ブラウザログインを完了してください。Codexは初期化中にTuistサーバーの指示を読み取るため、Gradle最適化リクエストは自動的に認証と検証ワークフローを受け取ります。

</details>


<details>
<summary>Claude Desktop</summary>

**Settings → Connectors → Add custom connector**を開き、次に設定します：

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

`auth`を`false`に設定すると、アダプターのブラウザ認証ハンドラーがTuistの未承認レスポンスを隠すのを防ぎます。これにより、ヘッドレスエージェントは返された`auth_md`URLを読み取り、Tuistの登録、IDアサーション交換、およびクレームポーリングフローに従うことができます。交換されたアクセストークンをベアラートークンとして構成するか、エージェントが直接認証されたModel Context Protocol呼び出しを行えるようにしてください。

ブラウザ認証を希望する場合は、`auth`を`"oauth"`に設定してください。このフローの場合、認証が完了するまでPiの[remote procedure call mode](https://pi.dev/docs/latest/rpc)で1つのプロセスを生かしたままにしてください：

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

**Cursor Settings → Tools & Integrations → Model Context Protocol Tools**を開き、次を追加します：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

**Command Palette → MCP: Add Server**を使用し、次に[Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP)サーバーを以下のように構成します：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Agent panel → Settings → Add Custom Server**を開き、次に設定します：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

エージェントが`auth.md`をサポートしている場合、ブラウザを開かずに匿名で開始できます。プロバイダーIDがすでにリンクされている場合、信頼されたプロバイダーIDもブラウザなしで完了できます。サービス認証メール、匿名クレーム、または初回のプロバイダーリンクの場合、エージェントはTuist検証リンクと6桁のコードを表示します。リンクを開き、サインインして、Tuistページでエージェントのコードを入力してください。コードをエージェントに送り返さないでください。Tuistの認可サーバーメタデータは、デプロイメント独自の`/auth.md`を直接指しており、そこには正確なリクエストとポーリングの形状が含まれています。

## Amp orbsおよびClaude Codeクラウドセッションのエージェント

Tuistアカウントに接続されたサンドボックスで実行されるコーディングエージェントは、ブラウザや保存されたTuist資格情報なしで、独自のIDトークンを使用してエンドポイントに認証できます：

- アカウントが**Settings → Integrations → Amp**の下で接続したAmpワークスペースまたはプロジェクトの**Amp orbs**は、orbのIDトークンを送信します。Ampでは、サーバーの`Authorization`ヘッダーを`Bearer ${amp:id-token}`に設定します。AmpはサーバーURLのオリジン用にトークンを発行するため、URLはこのTuistインスタンス自身のアドレスである必要があり、有効期限が切れる前に更新されます。別のオリジン用に発行されたトークンは拒否されます。
- 接続されたClaude Code環境の**Claude Code cloud sessions**は、Tuistが`TUIST_OIDC_TOKEN`として渡すセッショントークンを送信します。ヘッダーを`Bearer ${TUIST_OIDC_TOKEN}`に設定します。

TuistのLinuxサンドボックスはサーバーを自動的に追加しません：同じIDでサインインするTuist CLIと、エージェントに結果をプロジェクトの履歴と照合するタイミングを指示するスキルを提供します。エージェントにもMCPツールを提供するには、上記のヘッダーを使用して、サーバーをAmpまたはClaude Codeの設定、あるいはプロジェクトの`.mcp.json`に追加してください。

これらのトークンは、接続されたアカウントのすべてのプロジェクトへの読み取り専用アクセス権限を与えます：`mcp`グループの読み取りスコープを持ち、テストのミュートやスキップなど、データの作成、変更、削除を行うスコープは持ちません。ワークスペースまたは環境を切断すると、次のリクエストでアクセスが停止し、アクセス権限はトークン自体の有効期間を超えません。複数のTuistアカウントに接続されたAmpワークスペースは、トークンが特定のアカウントを指定しないため拒否されます。接続がない場合、未承認レスポンスの`error_description`にその旨が表示されます。

この読み取り専用アクセスはModel Context Protocolエンドポイントにのみ適用されます。同じサンドボックス内のコマンドラインツールとビルドシステム統合は、引き続きトークンを接続のCIアクセスと交換します。

## WebMCP

[WebMCP](https://webmachinelearning.github.io/webmcp)をサポートするブラウザでは、Tuistのページが`document.modelContext`でツールを登録するため、ブラウザに組み込まれたエージェントは追加の構成なしでそれらを呼び出すことができます。呼び出しはTuistサーバー上で実行されます。

- **Website and documentation pages**は、ドキュメントおよびソースツール（`search_tuist`、`search_tuist_code`、`list_tuist_files`、および`read_tuist_file`）を登録します。サインインは不要です。
- サインインしている場合、**An account's dashboard pages**はそのアカウント用のTuist読み取り専用ツールを登録します。各ページは、表示内容に応じてプロジェクトのビルドシステム用のツールのみを登録します：GradleプロジェクトのビルドページはGradleビルドツールを取得し、テストページはテストおよびカバレッジツールを取得し、ランナーページはランナーツールを取得し、サンドボックスページはサンドボックスツールを取得します。すべてのページはまた、ドキュメントツール、`list_projects`、および`get_project`も取得します。ツールはサインインしたユーザーとして実行されるため、ダッシュボードで読み取れるデータと、現在閲覧しているアカウントのデータにのみアクセスできます。別のページまたはアカウントに移動すると、ツールはそのページのツールに置き換えられます。

データを作成、変更、または削除するツールはWebMCPでは利用できません。これは、ブラウザエージェントがユーザーが追加することなくツールを受け取り、ビルドおよびテストによって生成されるコンテンツを読み取るためです。これらのツールを使用するには、MCPクライアントを`/mcp`エンドポイントに接続してください。

組織がシングルサインオンを強制している場合は、そのプロバイダーを使用してダッシュボードにサインインし、ツールを使用してください。

## ビルドシステム統合は2つの資格情報を使用します

Model Context Protocolツールに使用される資格情報は、GradleプラグインまたはBazelのリモートサービスを認証しません。エージェントがGradleまたはBazel統合を編集または検証する前に、以下を実行する必要があります：

```bash
tuist auth whoami --url https://tuist.dev
```

そのコマンドが認証されていない場合、エージェントは停止し、ユーザーに以下を実行するように依頼する必要があります：

```bash
tuist auth login --url https://tuist.dev
```

ローカルまたはセルフホスト型デプロイメントの場合、両方のコマンドと`tuist.toml`内のURLを置き換えてください。すべての場所でホスト名のスペルを同一に保ってください。例えば、`localhost`と`127.0.0.1`は別々の保存された資格情報を使用します。


## 機能

### ツール

以下のツールは、Tuist Model Context Protocolサーバーを通じて利用可能です：

すべてのツールは、人間が読める説明とともに、明示的な入力および出力スキーマを公開します。成功した呼び出しは、公表された出力スキーマに準拠した構造化コンテンツを返し、さらに構造化コンテンツをまだ消費できないクライアント向けにテキストとしてシリアル化された同じ結果を返します。

`build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id`、または`cache_run_id`など、単一レコードの識別子を受け取るツールは、そのレコードのTuistダッシュボードURLも受け付けます。識別子を抽出するのではなく、ブラウザからURLを直接貼り付けてください。

`get_xcode_build`、`get_test_run`、`get_gradle_build`、および`get_project`には`side_quests`を含めることができます。これは、プロジェクトが使用していないものの、レコードが役立つと示すTuist機能です。それぞれに`id`、証拠を示す`tip`、および`docs`リンクがあります。エージェントはまずユーザーのリクエストを完了し、該当するサイドクエストに言説し、ユーザーが同意した場合のみアクションを実行することが求められます。これらは、ユーザーセッション、MCPトークン、またはエージェントIDで接続しているかどうかに関わらず、プロジェクトのアカウントメンバーにのみ返されます：

| ID | ツール | 推奨される状況 |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | Xcode 26以降で処理されたクリーンビルドが、キャッシュ可能なコンパイルタスクを実行しなかった場合。 |
| `gradle_build_cache` | `get_gradle_build` | ビルドがGradleのビルドキャッシュがいずれかのタスクのキーを計算せずにキャッシュ可能なタスクを実行した場合。これはビルドキャッシュが無効になっていたことを意味します。 |
| `flaky_test_quarantine` | `get_test_run` | 実行に不安定なテストがあり、プロジェクト内の有効な自動化がそれらをミュートまたはスキップしていない場合。Struoプロジェクトでは推奨されません。 |
| `test_sharding` | `get_test_run` | Tuistがシャード化できるビルドシステムにおいて、シャード化されていないCI実行が10分以上かかった場合。ヒントには、選択的テストがいつどれだけ多くのテストをすでにスキップしたかが記載されています。 |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | CI実行がGitHub Actions、Bitrise、GitLab CI、またはBuildkiteマシンを使用し、アカウントがTuist Runnersでジョブを実行したことがない場合。tuist.devのみ。 |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | GitHub Actionsの実行が、GitHubリポジトリに接続されていないプロジェクトに属している場合。 |
| `other_build_systems` | `get_project` | アカウントがサポートされているすべてのビルドシステムでTuistを使用していない場合。ヒントには他のビルドシステムを識別するファイルが一覧表示されるため、エージェントはリポジトリを確認できます。 |

#### ドキュメントおよびコミュニティ検索

この読み取り専用ツールは、ドキュメントウェブサイトを動かすのと同じ検索エンジンを使用して、Tuistのドキュメント、[アプリケーションプログラミングインターフェース](https://en.wikipedia.org/wiki/API)リファレンス、GitHubリリース、コミュニティフォーラム、およびGitHubイシューを検索します。リリース結果には、製品、バージョン、公開日、プレリリースステータスが含まれます。デフォルトでは安定版リリースが検索され、`include_prereleases`を使用するとプレリリースを含めることができます。このツールは、`https://tuist.dev/mcp`にあるTuistホストサーバーでのみ利用可能です。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `search_tuist` | 公開されているTuistドキュメント、アプリケーションプログラミングインターフェースリファレンス、GitHubリリース、コミュニティディスカッション、およびGitHubイシューを検索します。オプションで1つの`source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）に制限できます。 | `query` |

#### フィードバック

エージェントは、Tuistツールやプロンプトが期待通りに動作しなかった場合（混乱を招く結果、エラー、欠落データ、欠落機能など）、Tuistチームに通知できます。エージェントはレポートを提案し、ユーザーが同意した場合のみ送信することが求められます。各レポートはTuistサポートとの会話を開始し、サポートからメールで返信が届く場合があります。レポートには、エージェントの期待値、実際の発生事象、オプションの提案、あなたのTuistユーザーID、ハンドル、メールアドレス、所属組織が含まれます。エージェントは問題が発生したアカウントとプロジェクトを指定することもでき、チームはどの組織に対応すべきかを把握できます。受け入れられるのはあなたが所属するアカウントのみです。Tuistユーザーとしてサインインしているエージェントのみがレポートを送信でき、各ユーザーは1時間あたり最大10件のレポートを開くことができます。このツールは、`https://tuist.dev/mcp`にあるTuistホストサーバーでのみ利用可能です。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `report_feedback` | Tuistツールまたはプロンプトの問題を報告します。オプションで、発生した`tool_name`、`account_handle`および`project_handle`を指定し、`suggestion`を追加できます。 | `category`, `expected`, `actual` |

#### ソースに基づく回答

これらの読み取り専用ツールにより、エージェントはホストサーバーとともにデプロイされた正確な公開Tuistソースリビジョンを、現在の動作に依存する回答の信頼できる情報源として使用できます。`https://tuist.dev/mcp`でのみ利用可能です。

互換性のあるクライアントは、初期化中にツールのソースリビジョン、リンク、結果制限に関する事実上の説明を、インラインOAuth認証情報とともに受け取ります。これらの説明は回答スタイルや検証ワークフローを規定するものではありません。ユーザーは`ask_tuist`プロンプトを最初に呼び出さずに直接質問でき、プロンプトは明示的なソースに基づくワークフローのために引き続き利用可能です。

すべての操作には、並行性、期間、トラバース、読み取りバイト数、レスポンスサイズに対する固定制限があります。検索および一覧結果には`truncated`および`truncation_reason`フィールドが含まれます。結果が切り捨てられた場合は、結果を網羅的なものとして扱うのではなく、パス、ファイルパターン、または検索語句を狭めてください。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `search_tuist_code` | ソースファイルを検索することで、現在の動作、デフォルト、構成、機能ゲート、エラー処理、または文書化されていない詳細に関する質問に回答します。結果には周辺の行、リビジョン固定ソースリンク、およびスキャン統計が含まれます。 | `pattern` |
| `list_tuist_files` | 関連するパスが不明な場合に、ソースサブシステムまたは近隣のテストを発見します。一覧には深度と結果数の上限があります。 | なし |
| `read_tuist_file` | 関連するパスを見つけた後、実装ファイル、呼び出しサイト、またはテスト内の特定の行範囲を検査します。切り捨てられたレスポンスには継続用の`next_start_line`が提供されます。 | `path` |

#### プロジェクト

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_accounts` | 認証済みユーザーが利用可能な個人および組織アカウントハンドルを一覧表示し、各アカウントがプロジェクトを作成できるかどうかを含めます。 | なし |
| `get_organization` | 組織のメンバーディレクトリを取得します。保留中の招待にはダッシュボードと同じ管理者権限が必要です。招待受諾トークンは返されません。 | `account_handle` |
| `create_organization` | 認証済みユーザーのためにTuist組織を作成します。 | `handle` |
| `create_project` | 認証済みユーザーがアクセスできるアカウントの下にTuistプロジェクトを作成します。 | `account_handle`, `project_handle` |
| `add_organization_member` | 既存のTuistユーザーを組織に追加するか、既存メンバーの役割を更新します。`user`（デフォルト）、`admin`、または`viewer`を受け入れます。ビューアーはダッシュボードと実行を読み取ることができますが、変更はできません。 | `organization_handle`, `email` |
| `invite_organization_member` | 既存のTuistユーザーに属しているかどうかにかかわらず、メールアドレスを組織に招待します。Tuistは14日後に期限切れになる受諾リンクをメールで送信します。サーバーがメールを送信できない場合、`email_sent`は`false`になり、リンクをダッシュボードからコピーする必要があります。`user`（デフォルト）、`admin`、または`viewer`を受け入れます。組織管理者権限が必要です。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 保留中の組織招待をキャンセルし、そのリンクを受諾できなくします。組織管理者権限が必要です。 | `organization_handle`, `email` |
| `list_projects` | 認証済みユーザーがアクセス可能なすべてのプロジェクトを一覧表示します。 | なし |
| `get_project` | プロジェクトの構成と接続されたリポジトリURLを取得します。 | `account_handle`, `project_handle` |
| `connect_project_repository` | アカウントのGitHub AppインストールがアクセスできるGitHubリポジトリにプロジェクトをリンクします。プロジェクトはリポジトリのデフォルトブランチを採用します。プロジェクト管理者権限が必要です。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | プロジェクトのGitHubリポジトリへのリンクを削除します。プロジェクト管理者権限が必要です。 | `account_handle`, `project_handle` |

#### アカウントトークン

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_account_tokens` | トークン値を公開せずにアカウントトークンのメタデータを一覧表示します。 | `account_handle` |
| `get_account_token` | トークン値を公開せずにアカウントトークンのメタデータを取得します。 | `account_handle`, `token_id` |
| `list_project_tokens` | トークン値を公開せずにプロジェクトトークンのメタデータを一覧表示します。 | `account_handle`, `project_handle` |

#### 通知ルール

これらのツールは認証済みユーザー自身の通知ルールを管理します。新しいプレビューなどのイベントがルールのプロジェクト（リストされていない場合は通知可能な任意のプロジェクト）で発生し、条件を満たすと、Tuistアプリデバイスへのプッシュ通知などのアクションを実行します。ルールがないと通知は届きません。ユーザー認証が必要で、自分のルールに対してのみ動作し、自分が所属するアカウントのプロジェクトのみを受け入れます。ルールはすべてのアカウントにまたがるため、ダッシュボードページでは提供されません。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_notification_events` | ルールがサブスクライブできるイベントタイプを一覧表示し、それぞれに条件用のJSONスキーマを含めます。 | なし |
| `list_notification_condition_options` | プロジェクト内のイベントに対する条件値（最近のプレビューのトラックやブランチなど）を提案します。 | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 自分のルールを一覧表示します。 | なし |
| `create_notification_rule` | イベント、オプションのプロジェクトと条件、および少なくとも1つのアクションからルールを作成します。 | `event`, `actions` |
| `update_notification_rule` | ルールの有効状態、プロジェクト、条件、またはアクションを変更します。 | `rule_id` |
| `delete_notification_rule` | ルールを削除します。 | `rule_id` |

#### 継続的インテグレーションランナー

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_runner_jobs` | アカウントの継続的インテグレーションランナージョブを一覧表示します。 | `account_handle` |
| `get_runner_job` | 継続的インテグレーションランナージョブを取得します。マシンのメモリ不足、停止内容、変更事項が含まれます。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 継続的インテグレーションランナージョブで記録されたステップを一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 継続的インテグレーションランナージョブで記録されたマシンメトリクスを一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 継続的インテグレーションランナージョブのキャプチャされたログ行を最大500件一覧表示します。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | アカウントの継続的インテグレーションワークフロー集計を一覧表示します。 | `account_handle` |
| `list_runner_profiles` | アカウントの継続的インテグレーションランナープロファイルと、それぞれの`runs-on`ラベルを一覧表示します。 | `account_handle` |
| `get_runner_catalog` | ランナープロファイルが使用できるマシンシェイプとXcodeバージョンを一覧表示します。 | `account_handle` |
| `create_runner_profile` | プラットフォーム、マシンシェイプ、macOSの場合はXcodeバージョンを指定してランナープロファイルを作成します。オプションで、どのブランチがキャッシュボリュームを保存するかを設定できます。アカウント管理権限または`account:runners:write`スコープが必要です。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | ランナープロファイルのマシンシェイプ、Xcodeバージョン、またはカスタムキャッシュボリュームの変更を保存するブランチを変更します。省略されたフィールドは値を保持します。アカウント管理権限または`account:runners:write`スコープが必要です。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | ユーザー確認後にランナープロファイルを削除します。デフォルトプロファイルは削除できません。アカウント管理権限または`account:runners:write`スコープが必要です。 | `account_handle`, `profile_name` |

ランナーボリュームツールは、Volumesダッシュボードと同じデータを公開します。読み取りツールにはランナーアクセスが必要で、クリアするにはアカウント管理権限または`account:runners:write`スコープ、およびユーザー確認が必要です。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_runner_volumes` | 名前とリポジトリでフィルタリングし、ボリュームをソートおよびページネーションします。 | `account_handle` |
| `get_runner_volume` | リポジトリ、プラットフォーム、容量、使用済みスペース、最終使用日時。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | ページネーションされたジョブとワークフロー参照、キャッシュステータス、ヒット結果、マウント時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | ジョブによってマウントされたボリューム。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | ストレージ時系列、ジョブ実行、ヒット率、傾向。オプションの`volume_id`、`start`、`end`（ISO 8601）。デフォルトは7日、最大90日。 | `account_handle` |
| `delete_runner_volume` | ボリュームとその保存内容を削除します。実行中のジョブはプライベートコピーを保持しますが保存はできず、同じキーの後続ジョブは空から開始されます。 | `account_handle`, `volume_id` |

リストは`page`と`page_size`（最大100）を受け入れます。ボリューム在庫はさらに`name`と`repository`（完全一致、AND結合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）、`sort_order`（`asc`、`desc`）を受け入れます。不明な測定値とヒット結果は`null`のままです。キャッシュステータスはボリュームの変更が保存されたかどうかを示し、ジョブの成功を示すものではありません。

#### サンドボックス

サンドボックストールは、Sandboxesダッシュボードと同じデータとアクションを公開し、[API](https://tuist.dev/api/docs)と同じアクセス権を持ちます。アカウントメンバーはアカウント内のすべてのサンドボックスですべてのツールを使用できます。読み取り専用ビューアーは使用できません。アカウントでサンドボックスが有効になっている必要があります。ダッシュボードのサンドボックスページは読み取り専用ツールを登録します。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_sandboxes` | ステータス、シェイプ、タイムスタンプを含むサンドボックスをページネーションします。オプションの`search`（サンドボックス内のテキスト、Amp OrbまたはAnthropicセッションID）、`status`、`vcpus`、`sort_by`（`created`、`last_active`、`identifier`）、`sort_order`。 | `account_handle` |
| `get_sandbox` | サンドボックスのステータス、シェイプ、ノード、アーカイブ、タイムスタンプ。 | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU時間、作成されたサンドボックス数、セッション、セットアップ、起動までの所要時間、ピークvCPU、メモリ、ディスク（アカウント制限に対する比較）、傾向。オプションの`start`と`end`（ISO 8601）。デフォルトは30日、最大90日。 | `account_handle` |
| `create_sandbox` | 空のサンドボックスを起動し、実行開始時に返します。オプションの`platform`（`linux`または`darwin`）、`xcode_version`（macOSサンドボックスの正確なXcodeバージョン。ツールの説明に記載されているものから選択。`darwin`を意味します）、`repository`（macOSサンドボックスのgithub.com `owner/name`。アカウントのプロジェクトの1つに接続。Linux Claude Code環境にmacOSセットアップスクリプトがある場合、Macはその<.localized_link href="/guides/features/sandboxes/claude#remote-mac-snapshots">準備済みスナップショット</.localized_link>から起動）、`template`、`vcpus`（`memory_mb`付き。Linux: 2x4096、4x8192、8x16384、デフォルト2x4096。macOS: 8x8192、8x16384、8x24576、デフォルト8x8192）、`workspace_gb`、`lifetime_seconds`（実行コマンドがキャンセルされ、一時停止およびアーカイブされるまで実行可能な期間。ファイルを保持。デフォルト2時間、最大1日）。説明では、エージェントにリポジトリが使用するXcode（`.xcode-version`、mise、CI設定、ドキュメント）を見つけて渡すよう指示します。別のXcodeではリポジトリのキャッシュとスナップショットが見つからないためです。また、Macの`/opt/tuist/agent-guide.md`にあるガイドを読み、以下のシミュレーターツールでiOS Simulatorで実行中のアプリを表示します。Mac上のTuistは、リポジトリがバージョンをピン留めしている場合はそのバージョンを使用し、独自に<.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">アカウントのキャッシュを使用</.localized_link>します。 | `account_handle` |
| `pause_sandbox` | 実行中のサンドボックスをノードのディスクにスナップショット化します。 | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 一時停止中またはアーカイブ済みのサンドボックスを再開します。 | `account_handle`, `sandbox_id` |
| `extend_sandbox` | サンドボックスの有効期間を現在から再開します。オプションの`lifetime_seconds`（最大1日）。統合が所有するサンドボックスには有効期間がありません。 | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 一時停止中のサンドボックスのディスクをオブジェクトストレージに移動するキューに入れます。 | `account_handle`, `sandbox_id` |
| `delete_sandbox` | ユーザー確認後にサンドボックスとそのディスクを削除します。 | `account_handle`, `sandbox_id` |
| `list_sandbox_devices` | サンドボックスのデバイスと、その`id`、`name`、`platform`、`runtime`、`state`（`Booted`、`Shutdown`）。現在はmacOSサンドボックスのシミュレータ（iOSなど）です。Androidエミュレータはまだサポートされていません。 | `account_handle`, `sandbox_id` |
| `boot_sandbox_device` | 名前またはIDでデバイスを起動し、最大40秒間待機します。シミュレータはSimulatorアプリに表示されます。すでに起動済みのデバイスを起動しても成功します。 | `account_handle`, `sandbox_id`, `device` |
| `launch_sandbox_app` | 起動済みのデバイスでアプリを起動し、実行中は再起動します。`app_path`（サンドボックス内でビルドされた.app）を渡してまずインストールするか、インストール済みのアプリには`app_id`（iOSではバンドルID）を渡します。複数のデバイスが起動している場合はオプションの`device`。 | `account_handle`, `sandbox_id` |
| `open_sandbox_url` | ブラウザ（iOSではSafari）でウェブページを開くか、起動済みのデバイスでアプリのディープリンクを開きます。オプションの`device`。 | `account_handle`, `sandbox_id`, `url` |
| `get_sandbox_screenshot` | 起動済みのデバイス、または`target: screen`でサンドボックス全体のスクリーンを画像として返します。エージェントのコンテキストに収まるよう、長い辺が最大1600ピクセルのJPEGです。オプションの`device`。ディスク上のフルサイズPNGには`tuist sandbox screenshot`を使用してください。 | `account_handle`, `sandbox_id` |

デバイスツールはサンドボックス内で固定コマンドを実行します。渡したコマンドは実行せず、CLIの`tuist sandbox exec`のみが実行します。Linuxサンドボックスでは`devices_unsupported`、デバイスが起動するまでは`device_not_booted`、サンドボックスに存在しない名前またはIDでは`device_not_found`、欠落している`app_path`またはインストールされていないアプリでは`app_not_found`を返します。

サンドボックストールのエラーは、独自の行に安定したコード（例：`code: fleet_busy`）で始まり、その後に対応策が続きます。待機を伴うコードには`retry_after_seconds:`行が追加されます。APIはエラーボディで同じ`code`を送信します。すべてのホストがビジーの場合、`create_sandbox`は`fleet_busy`を返す前に最大25秒間待機します。

#### Ampワークスペース

これらのツールは、orbがトークンなしでTuistにサインインできるようにする<.localized_link href="/guides/server/authentication#amp-orbs">Ampワークスペース接続</.localized_link>を管理します。ダッシュボードの「統合」ページと同じ管理者専用権限を使用します。orb内のエージェントは、`$AMP_WORKSPACE_ID`および`$AMP_PROJECT_ID`から自身のIDを読み取ることができます。接続が許可するすべてのorbはアカウント内のすべてのプロジェクトにCIアクセス権を持つため、エージェントは接続前にユーザーに確認すべきです。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | アカウントに接続されているAmpワークスペースと、それぞれが制限されているプロジェクト（存在する場合）を一覧表示します。 | `account_handle` |
| `connect_amp_workspace` | Ampワークスペースを接続します。オプションの`project_id`は、1つのAmpプロジェクトのorbへのサインインに制限します。 | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | ワークスペースを切断します。そのorbがすでに持っているセッションは、期限切れになるまで有効です。 | `account_handle`, `connection_id` |

#### Claude環境

これらのツールは、Claude Managed Agentsのセルフホスト環境を接続し、設定 → 統合 → Claudeと同様に、セッションをTuistサンドボックスで実行します。アカウント管理権限とサンドボックスの有効化が必要です。エージェントはAnthropicのAPIで環境を作成できますが、環境キーを生成できるのはClaude Consoleのみであるため、エージェントはユーザーにそれを求めます。TuistはAnthropic APIキーまたはワークロードアイデンティティフェデレーションを使用してセッションを開始し、その資格情報で環境を取得してから保存します。Anthropic側のセットアップにはユーザー自身のAnthropic認証情報を使用しますが、Tuistはそれらを受け取りません。キーはクライアントとモデルを通過するため、明示的に指定してください。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_claude_environments` | 接続済みの環境とそれぞれが使用する認証情報、さらにフェデレーションルールが信頼すべき発行者URLとサブジェクトプレフィックスを一覧表示します。 | `account_handle` |
| `connect_claude_environment` | `api_key`で環境を接続するか、`organization_id`、`workspace_id`、`service_account_id`、`federation_rule_id`で接続します。オプションの`platform`、`vcpus`、`memory_mb`はサンドボックスの形状を設定します。 | `account_handle`, `environment_id`, `environment_key` |

#### Organization AI

これらのツールは、設定 → AIと同様に、組織のサーバーサイドAIタスクが使用するモデルを管理し、同じルール（組織管理者のみ、かつAI設定を持つ組織のみ）を共有します。`pulse_grouping`や`pulse_explanation`などの各タスクは、タスクルートが存在すればそれを使用し、なければデフォルトモデルを使用します。どちらも存在しない場合はリクエストを送信しません。すべてのツールは、各タスクの現在のモデルと、それがルート、デフォルト、または何も由来していないかを含む完全な構成を返します。プロバイダーの追加または編集にはAPIキーが必要であるため、ダッシュボードまたはREST API（`/api/accounts/{handle}/ai`）で行い、これらのツールでは行いません。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `get_organization_ai_configuration` | プロバイダー（キーなし）、モデル、デフォルトモデル、タスクルート、および各タスクの現在のモデルを読み取ります。 | `account_handle` |
| `save_organization_ai_model` | モデル（`name`、`provider_id`、`upstream_model_id`）を追加するか、`id`で更新します。 | `account_handle` |
| `remove_organization_ai_model` | モデルとそのタスクルートを削除します。 | `account_handle`, `model_id` |
| `set_organization_ai_default_model` | デフォルトモデルを選択するか、nullでクリアします。 | `account_handle`, `model_id` |
| `save_organization_ai_task_route` | `task`を設定済みの`model_id`にルーティングするか、`id`でルートを更新します。タスクには最大で1つのルートしか持てません。 | `account_handle` |
| `remove_organization_ai_task_route` | ルートを削除し、タスクが再びデフォルトモデルを使用するようにします。 | `account_handle`, `route_id` |
| `remove_organization_ai_provider` | プロバイダーをそのキー、モデル、およびそれらのルートとともに削除し、リンクされたClaude組織とのリンクを解除します。 | `account_handle`, `provider_id` |

#### Webhooks

Webhookツールは、ダッシュボードと同じ管理者専用権限を使用します。配信試行にはエンドポイント用に記録されたリクエストとレスポンスデータが含まれますが、エンドポイントの署名シークレットは含まれません。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_webhook_endpoints` | アカウントのWebhookエンドポイントを一覧表示します。 | `account_handle` |
| `get_webhook_endpoint` | Webhookエンドポイントを取得します。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | エンドポイントの配信試行を一覧表示します。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 配信試行を取得します。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcodeビルド

Xcode、Gradle、Bazel、Mix、Cargoのビルド詳細ツールは、既存の`custom_metadata: {tags, values}`構造を公開し、報告された場合はインフラストラクチャ観測値も含みます。値は文字列のまま保持され、不明なキーも保存されます。例えば、`tuist.cpu.available_processors`はランタイムで利用可能な論理プロセッサ数を示し、`tuist.gradle.max_workers`はGradleワーカー制限、`tuist.jvm.max_heap_bytes`はJVMヒープ制限であり、ホストメモリではありません。これらは信頼されていないクライアント観測値であり、検証済みのランナーIDではありません。欠落している観測値は欠落したままです。インポートされたログや古いクライアントにはインフラストラクチャメタデータがない場合があります。Struoメタデータは、調整されたクライアント/プロトコルの更新を待っています。

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_xcode_builds` | プロジェクトのXcodeビルド実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 特定のXcodeビルド実行に関する詳細情報を取得します。これには、生の`.xcactivitylog`を含むアーカイブの一時ダウンロードURLが含まれます。 | `build_run_id` |
| `list_xcode_build_targets` | 特定のXcodeビルド実行のビルドターゲットを一覧表示します。 | `build_run_id` |
| `list_xcode_build_files` | 特定のXcodeビルド実行でコンパイルされたファイルを一覧表示します。 | `build_run_id` |
| `list_xcode_build_steps` | ログテキストを除き、タイミングと結果を伴う記録済みビルドステップを一覧表示します。 | `build_run_id` |
| `get_xcode_build_step` | ログと切り捨てフラグを含む、記録済みのビルドステップを1つ取得します。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 特定のビルド実行のビルド問題（警告とエラー）を一覧表示します。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 特定のXcodeビルド実行のキャッシュ可能タスク（キャッシュヒット/ミス）を一覧表示します。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 特定のXcodeビルド実行の[コンテンツアドレサブルストレージ](https://en.wikipedia.org/wiki/Content-addressable_storage)出力を一覧表示します。 | `build_run_id` |

`list_xcode_build_steps`はデフォルトで20ステップずつページを返します（`page_size`で最大100）。ナビゲーションには`page`と`pagination_metadata`を使用します。`search`を使用してタイトル、プロジェクト、またはターゲットを一致させるか、正確な`project`、`target`、`category`（例：`swiftCompilation`）、および`status`（`success`または`failure`）でフィルタリングします。`duration_ms`でソートすると最も遅いものが先頭に表示され（デフォルト）、`start_ms`でソートすると時系列順になります。ステップIDは同順位を解消し、64ビット精度を完全に保持するために10進数文字列として返されます。IDはビルドごとにスコープされており、ビルド間で一致させてはいけません。

オプションの`start_ms`と`end_ms`は、ビルド開始からのミリ秒単位の時間範囲と重複するステップを選択します。終了時間は除外されます。どちらのツールも、ビルドUUIDまたはダッシュボードURLを`build_run_id`として受け入れます。返されたステップ`id`を`step_id`として変更せずに渡し、そのログを取得します。ログはステップあたり最大64 KiBを保持し、`log_truncated`が省略された出力を示します。

Xcodeビルドが処理されると、デフォルトでステップが収集されます。記録されたステップデータは90日間保持されます。リストレスポンスには`availability`が含まれます。記録されたステップが存在する場合は`available`（フィルタに一致するものがなくても）、ビルドがまだ処理中でステップがない場合は`processing`、ステップが記録されていないか期限切れの場合は`unavailable`となります。

同じ操作はHTTP APIの`GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps`および`GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}`で利用可能で、同じフィルタとページネーションをサポートします。どちらもビルドのプロジェクトへの読み取りアクセス権が必要です。

#### Gradleビルド

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 完全な認証、プロジェクト設定、Gradleプラグイン、キャッシュポリシー、および2回ビルドによる検証ワークフローを返します。エージェントは既存のAndroidまたはGradleプロジェクトを編集する前にこれを呼び出すべきです。 | なし |
| `list_gradle_builds` | カスタムメタデータを含むプロジェクトのGradleビルド実行を一覧表示します。オプションの`tag`パラメータを使用してカスタムタグでフィルタリングします。 | `account_handle`, `project_handle` |
| `get_gradle_build` | ビルドメタデータ、タスク/キャッシュカウント、および`failures`（各失敗したタスクと構成ステップの失敗メッセージ）を取得します。 | `build_run_id` |
| `list_gradle_build_tasks` | タスクの結果、複合ビルドID、キャッシュ可能性、増分ステータス、および失敗メッセージを一覧表示します。 | `build_run_id` |
| `list_gradle_build_steps` | 検索、メタデータ、および重複する時間フィルタを使用して、 timed タスク、構成、および変換を一覧表示します。 | `build_run_id` |
| `get_gradle_build_step` | 不透明なIDによって記録されたステップメタデータを検査します。失敗したタスクまたは構成ステップの`log`はその失敗メッセージです。 | `build_run_id`, `step_id` |

GradleおよびBazelのステップリストはデフォルトで20件の結果を返し（最大100件）、`search`、正確な`project`、`target`、`category`、`status`、重複する`start_ms` / `end_ms`フィルタ（終了は除外）、および`duration_ms`または`start_ms`での並べ替えをサポートします。返されたIDは変更せずに渡してください。これらはビルドごとにスコープされています。リストは`time_origin`と`coverage`を公開します。古いGradleレポートは、ビルド開始がアップロードされていないため`first_recorded_timestamp`を使用します。Bazelプロファイルは、`trace_profile`カバレッジと時間原点としての`profile_start`を使用して、すべての記録された間隔を公開します。古いビルドは保持されたBEPサマリーにフォールバックします。ソースレコードは90日後に期限切れになります。Bazelの詳細には、公開されている場合にサニタイズされたアクションログが含まれます。失敗したタスクまたは構成ステップのGradle詳細には、Tuist Gradleプラグインが`log`として報告した失敗メッセージが含まれます。これは、Gradleのコンソールが表示する例外メッセージとその原因チェーンであり、スタックトレースやタスク出力はなく、プロジェクト内のパスは相対パス化され、資格情報やその他のローカルパスは編集されています。ステップあたり最大16 KiB、ビルドあたり最大32の失敗ステップです。他のGradleステップ、古いプラグインバージョンによって報告されたビルド、および資格情報なしのレポートでは、`log`はnullになります。構成ステップは、失敗した場合に`failure`を報告し、それ以外の場合は`unknown`を報告します。`compare_builds`プロンプトはこのカバレッジを使用して、完全なBazelトレースと保持されたサマリーを区別し、より広範な呼び出し出力を確認する前に、エージェントをアクションの結果とログのためのステップ詳細へ誘導します。

単一ステップツール`get_gradle_build_step`および`get_bazel_build_step`はIDによってステップを取得し、時間フィルタを受け入れません。時間範囲でステップをフィルタリングするには、対応するリストツールを使用してください。

保持されたサマリーから返されたBazelステップIDは、一覧表示とステップ取得の間に完全なプロファイルが届いた場合でも読み取り可能です。ステップデータが期限切れになったインデックス付きプロファイルは、利用不可と報告されます。Gradleステップリストには、ゼロ期間のキャッシュ済みおよびスキップされた操作が含まれます。

#### Bazel呼び出し

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 認証、プロジェクト設定、Bazel構成、および検証ワークフローを返します。 | なし |
| `list_bazel_invocations` | 完了した[Bazel Build Event Protocol](https://bazel.build/remote/bep)呼び出しを新しい順に一覧表示します。ビルドメトリクス、制限された実行タイムライン、クリティカルパス診断、およびプロジェクトに関連付けられたリモートキャッシュ合計を含みます。`status`、`git_branch`、`git_commit_sha`、`is_ci`、および`command`でフィルタリングします。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | ビルドメトリクス、制限された実行タイムライン、クリティカルパス診断、および関連するリモートキャッシュ合計を含む、完了したBazel呼び出しを1つ取得します。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | フィルタと明示的なカバレッジを伴う、記録されたBazelプロファイル間隔を一覧表示します。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 記録されたBazelステップと、その公開されたアクション結果およびサニタイズされたログを検査します。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_remote_actions` | 呼び出しに対してTuistリモート実行が実行したアクションを、ニーモニック、ターゲット、アクションダイジェスト、終了コード、実行パス、およびフェーズタイミングとともに一覧表示します。オプションの`sort_by`（`duration`または`queued_at`）、`failed`、および`mnemonic`フィルタ。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_remote_action` | 1つのリモートアクションのargv、環境（シークレットのように見える値はマスク）、プラットフォーム、作業ディレクトリ、出力パス、ワーカー、終了コード、stdoutおよびstderrの最初の16 KiB、stderrで認識されたコンパイラ`errors`、フェーズタイミング、およびアクションダイジェストを取得します。 | `account_handle`, `project_handle`, `invocation_id`, `action_id` |
| `get_bazel_remote_action_log` | バイトオフセットによって、リモートアクションのstdoutまたはstderrの最大64 KiBを読み取ります。デフォルトではストリームの末尾です。長いストリームは全体がコピーされるか、それより長い場合は最初の16 KiBと最後の16 MiBが保持されます。`recorded`は利用可能な範囲を一覧表示します。 | `account_handle`, `project_handle`, `invocation_id`, `action_id`, `stream` |
| `list_bazel_invocation_logs` | Bazel呼び出しに対してキャプチャされたサニタイズされたログを実行順に一覧表示します。Bazelの進捗出力の制限された末尾と`test.log`アーティファクトを含みます。オプションの`stream`（`stdout`または`stderr`）、`source`（`progress`または`test_log`）、`target_label`、および`errors`フィルタで結果を絞り込めます。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bazel呼び出しに対してキャプチャされたサニタイズされたログチャンクを1つ取得します。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 操作、エンドポイント、および観測時刻を含む生のBazelリモートキャッシュ観測を一覧表示します。オプションで呼び出し、結果、または操作に絞り込めます。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 生のBazelリモートキャッシュ観測を1つ取得します。 | `account_handle`, `project_handle`, `cache_event_id` |

#### リモート実行

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `get_remote_execution_activity` | プロジェクトで現在実行中およびキューイングされているBazel呼び出しとリモートアクションを一覧表示します。各アクションの呼び出し、ニーモニック、ターゲット、アクションダイジェスト、マシンサイズ、およびその状態に入った時点を含みます。実行ゲートウェイが事前に準備したVM上で実行するアクションは、完了するまで一覧に表示されません。 | `account_handle`, `project_handle` |
| `get_remote_execution_usage` | プロジェクトのリモート実行と`[from, to)`期間中の測定された実行時間を、合計、マシンサイズ別、ディスパッチモード別、および時間・日・月別に取得します。期間はデフォルトで過去30日で、最大366日まで指定できます。 | `account_handle`, `project_handle` |

`list_bazel_invocations`フィルタは完全一致であり、同じ秒で完了した呼び出しは呼び出しID順に並べられます。ブランチ上の最新の失敗した呼び出しを見つけるには、`status: "failure"`、`git_branch`、および`page_size: 1`を指定して呼び出します。RESTエンドポイント`GET /api/projects/{account_handle}/{project_handle}/bazel/invocations`も同じフィルタを受け付けます。

`list_bazel_build_steps`で`remote_execution: true`を設定し、インデックス付きプロファイルから安全に関連付けられたサーバーフェーズタイミングを持つアクションのみを返します。一覧および詳細レスポンスは、オプションのnull許容値である`remote_queue_ms`、`remote_input_fetch_ms`、`remote_execution_ms`、および`remote_output_upload_ms`を公開します。値はアクション内の再試行を含む記録されたフェーズの合計です。欠落またはnull値はゼロではなく利用不可を意味します。これらはプロファイル観測値であり、課金対象の使用量や新規実行の証明ではありません。キャッシュされたサーバー結果には実行メタデータが含まれる可能性があるためです。クライアントアップロードは除外されます。古く不明確なプロファイルでは、リモート作業が発生していても一致するアクションが返されない場合があります。ステップRESTエンドポイントも同じ`remote_execution=true`フィルタを受け付けます。ダッシュボードの「リモート実行」タブも同じクエリと90日間の保持期間を使用します。

テストログには、元となったテスト結果の`target_label`と試行`status`が含まれているため、`target_label: "//foo:bar_test"`はそのターゲットのテストログのみを返します。`errors: true`は失敗した試行のテストログと、Bazelのレポーターが`ERROR:`、`FAIL:`、または`TIMEOUT:`で始まる行を含むstderr進捗チャンクを返します。進捗出力はターゲットに帰属せず、帰属が記録される前に書き込まれたログはフィールドが空になります。失敗したアクションとその出力は、`list_bazel_build_steps`からターゲットごとに利用でき、テストケースごとの失敗はテスト実行ツールから利用できます。

#### Cargoビルド

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_cargo_builds` | プロジェクトのCargoビルドを新しい順に一覧表示します。`git_branch`、`status`、`is_ci`、または`command`でフィルタリングします。Cargoテスト実行結果はこのビルド一覧ではなく、テストツールを通じて利用できます。 | `account_handle`, `project_handle` |
| `get_cargo_build` | ビルドメタデータ、集計キャッシュカウンター、および診断情報付きで最大500件の記録されたコンパイラジョブを取得します。`compilations_truncated`は省略されたジョブを示します。診断情報は返されたジョブのみを対象とします。 | `account_handle`, `project_handle`, `build_id` |

`get_cargo_build`で`include_cache_inspection: true`を設定し、検証されたタスク決定とCAS操作を4 MBに制限して取得します。デフォルトでは、また記録が欠落しているか無効な場合、`cache_inspection`はnullです。部分キャプチャの`truncated`フラグを尊重してください。転送は各タスクヒットのローカル/リモート起源を確立しません。HTTP詳細エンドポイントも同じクエリパラメータを受け付けます。

#### Mixビルド

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_mix_builds` | プロジェクトのMix（Elixir）コンパイルビルドを新しい順に一覧表示します。カスタムメタデータを含みます。`git_branch`、`status`、`is_ci`、または`mix_env`でフィルタリングします。 | `account_handle`, `project_handle` |
| `get_mix_build` | ビルドメタデータ、診断カウント、および依存関係キャッシュの概要を取得します。 | `account_handle`, `project_handle`, `build_id` |

#### ビルドトレース

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `get_build_trace` | Xcode、Gradle、Bazel、またはMixビルドのタイムラインを、[Perfetto](https://ui.perfetto.dev)で開けるトレースファイルとしてダウンロードするためのリンクを取得します。 | `account_handle`, `project_handle`, `build_id` |

`build_id`はビルド実行ID（Bazelの場合は呼び出しID）またはビルドのダッシュボードURLです。返された`trace_url`は[Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSONファイルを提供します。リンクを持っている人は誰でも、他の認証情報なしで`expires_at`（呼び出しから1時間後）までそのビルドのトレースをダウンロードできます。エージェントは`curl`でダウンロードし、Perfettoで開くためにあなたに渡すか、Perfettoの`trace_processor`でクエリできます。トレースには、並列性によってレーンにパックされた記録されたステップ、ビルド全体にわたるトラック、およびビルドがマシンのメトリクスを記録した場合のCPUおよびメモリカウンターが含まれます。ログを除き、上記のステップツールと同じデータを保持します。ダッシュボードは各ビルドの「タイムライン」タブから同じファイルを提供します。

#### Struo実行

<a id="once-runs"></a>

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_once_runs` | プロジェクトのStruo実行を新しい順に一覧表示します。`kind`（`build`、`test`、または`generic`）、`status`、`is_ci`、または`git_branch`でフィルタリングします。完了していない実行のステータスは`in_progress`です。 | `account_handle`, `project_handle` |
| `get_once_run` | アクション合計、キャッシュ概要、およびテスト実行の場合はテスト合計を含む実行を取得します。 | `account_handle`, `project_handle`, `run_id` |

Cargoビルド、Mixビルド、およびStruo実行IDはプロジェクト内で一意です。同じ読み取りはHTTP API経由で`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds`、および`.../once/runs`で利用でき、それぞれに1つのIDに対する詳細エンドポイントがあります。

#### タスク、アクション、モジュール、およびファイル

これらのプロジェクトスコープのツールは、実行をまたぐ永続的なビルド識別子を検査します。`list_build_entities`から始め、返された安定した`id`と同じ`kind`を`get_build_entity`または`list_build_entity_history`に渡し、`account_handle`と`project_handle`も一緒に指定します。ビルドや呼び出しの識別子は不要です。

| ツール | 説明 | 必須パラメータ |
| --- | --- | --- |
| `list_build_entities` | プロジェクトのビルド全体で確認できる、ある種類のタスク、モジュール、アクション、またはファイルを一覧表示します。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 選択した期間のネイティブ識別子と分析データを含む1つのビルドエンティティを取得します。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 1つのビルドエンティティの記録された実行、コンパイル、またはキャッシュイベントを新しい順に一覧表示します。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | ツールチェーン | 履歴リスト |
| --- | --- | --- |
| `bazel_actions` | Bazelアクション | BEPで報告されたアクション実行 |
| `gradle_tasks` | Gradleタスク | タスク実行 |
| `xcode_modules` | Xcodeモジュール | コンパイルとモジュールキャッシュイベント |
| `once_actions` | Struoアクション | 実行 |
| `mix_files` | Mixコンパイル済みファイル | コンパイル |
| `mix_modules` | Mixコンパイル済みモジュール | コンパイル |
| `cargo_crates` | Cargoクレート | 記録されたrustc呼び出し |

これらのツールは段階的に展開されており、有効化されているプロジェクトのデータのみを返します。他のプロジェクトでは空の結果ではなくエラーを返します。種類はそのビルドツールチェーンを使用しているプロジェクトでのみ利用可能です。ツールは制限付きの`start_at`/`end_at`フィルタ、`environment`（`any`、`ci`、または`local`）、および正確な`branch`を受け入れます。`list_build_entities`は`q`を受け付け、`list_build_entity_history`は不透明な`after`/`before`カーソルをサポートします。不明なタイミングまたはキャッシュ観測はゼロやミスにならず、利用不可のままとなります。履歴は既存の実行ツールを使用したドリルダウンのために、記録された親とネイティブ実行を参照します。

`get_build_entity`のメトリクスには、タイミングが記録された観測数である`duration_samples`が含まれます。実際のゼロdurationはカウントされますが、タイミング欠落はカウントされません。この数は観測数より少ない場合があり、利用不可のduration統計はnullのままです。

Xcodeモジュールのdurationは、ビルドログ内の測定されたターゲットコンパイルから取得されます。モジュールキャッシュの解決やコンパイル作業のないターゲットはdurationサンプルに貢献しません。コンパイル観測はXcodeビルドを参照し、キャッシュイベントは生成コマンドまたはキャッシュコマンドを参照します。

Bazelアクションはターゲットラベル、ニーモニック、および構成された主要出力によって識別され、入力依存のキャッシュダイジェストに頼ることなく個別のアクションと構成を区別します。履歴はキャッシュルックアップやトレースプロファイルフェーズではなく、BEPで報告された実行を記録します。完全な実行カバレッジには`--build_event_publish_all_actions`が必要です。アーティファクト配信はベストエフォートであるため、観測の欠落は作業が行われなかった証拠ではありません。安定した識別子や実行開始情報を持たない古いKuraペイロードは受け入れられますがインデックスされません。終了時間の測定値がない場合は利用不可のままとなり、実際のゼロdurationはカウントされます。

Mixモジュールのdurationは含まれるファイルのコンパイルを測定するものであり、独立して測定されたモジュール作業ではありません。Struoアクションは、クライアントがターゲットマッピングを報告した場合、宣言されたターゲット/ケーパビリティ/インデックススロットを使用します。診断ラベルだけでは安定した識別子になりません。既存のクライアントと実行レベルのツールは変更なくサポートされます。

Cargoクレートは、記録された正確なクレートルート、名前、および種類によってグループ化されます。チェックアウトパスの変更により履歴が分割される可能性があり、ビルドプロファイル、機能、およびターゲットトリプルは区別されません。履歴はrustc呼び出しを測定するものであり、ファイルごとの作業やキャッシュヒットではありません。欠落したジョブは削除や完全なワークスペース在庫の確立にはなりません。

分析読み取りにはメモリと実行時間の制限があります。クエリがこれらの制限を超えると、ツールは空の結果を捏造する代わりにエラーを返します。

新しい観測はデプロイ後にインデックスされます。この機能は既存の実行テレメトリをバックフィルしません。識別子メタデータは<.localized_link href="/guides/server/data-retention">データ保持ポリシー</.localized_link>の下で個々の観測よりも長期間存続します。

#### テスト

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_test_runs` | プロジェクトのテスト実行を一覧表示します。それぞれに`selective_testing_strategy`が含まれます。`selective_testing`（カバレッジベースの選択のフォールバックを含む`coverage`、または`module_hash`）でフィルタリングします。`query`フィールドは`git_branch`、`scheme`、`status`、および`selective_testing`です。`field:"value"`は完全一致、`field~"value"`は大文字小文字を区別しない部分一致（`selective_testing`では使用不可）であり、先頭の`-`はどちらの演算子も否定します。例えば、`-git_branch~"gh-readonly-queue"`はマージキューブランチを除外します。空白で区切られたクエリフィルタと明示的な引数はANDセマンティクスで結合されます。 | `account_handle`, `project_handle` |
| `get_test_run` | テスト実行の詳細メトリクスを取得します。これには、独自のコードカバレッジ（`coverage`：測定されたかどうか、行数と数値、部分的かダーティなチェックアウトから実行されたか）、選択的テストの概要（`selective_testing`：戦略、ベースラインコミット、要求・選択・スキップ・推定テスト数。テスト選択の有効性計算に使用）、結果バンドル（`.xcresult`）とそれを実行したコマンドのセッションアーカイブ（CLIログ）の一時的なダウンロードURL、またはコマンドが実行にリンクされていない場合は`null`が含まれます。シャーディングされた実行の`result_bundle_url`は最初に報告したシャードのバンドルです。`shard_result_bundles`にはCI再試行を含むすべてのシャードレポートのバンドルがシャードインデックスとステータスとともに一覧表示されるため、失敗したテストなしで失敗したシャードを検査できます。 | `test_run_id` |
| `list_test_module_runs` | 特定のテスト実行に対するテストモジュール実行を一覧表示します。 | `test_run_id` |
| `list_test_suite_runs` | 特定のテスト実行に対するテストスイート実行を一覧表示します。オプションでモジュールによるフィルタリングが可能です。 | `test_run_id` |
| `list_test_cases` | プロジェクトのテストケースを一覧表示します（`flaky`などのフィルタをサポート）。 | `account_handle`, `project_handle` |
| `get_test_case` | 信頼性率、不安定率、および実行回数を含むテストケースの詳細メトリクスを取得します。 | `test_case_id` または `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | テストケース実行を一覧表示します。オプションでテストケースまたはテスト実行によるフィルタリングが可能です。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 特定のテストケース実行の失敗詳細と繰り返し回数を取得し、その実行のカバレッジベースの選択でテストが保持された場合はその理由（`selective_testing`：決定、理由、一致した変更ファイル、およびシャード）も取得します。 | `test_case_run_id` |
| `list_test_case_run_attachments` | テストケース実行の添付ファイルを一覧表示します。各添付ファイルには一時的なダウンロードURLが含まれます。 | `test_case_run_id` |
| `list_test_case_events` | ミュートやスキップなど、テストケースの状態変化を一覧表示します。 | `test_case_id` |
| `update_test_case` | テストケースの状態または不安定分類を更新します。変更により、外部サービスを含む設定済みのWebhookエンドポイントにイベントが送信されます。 | `test_case_id` または `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | テスト実行の選択的テストターゲット結果を一覧表示します。 | `test_run_id` |
| `list_selective_testing_tests` | テスト実行のカバレッジベースの選択によって決定・選択・スキップされたテストを、各決定の理由、選択させた変更ファイル、そのシャード、および実行での結果とともに一覧表示します。`decision`、`reason`、または`search`でフィルタリングします。 | `test_run_id` |
| `list_selective_testing_changed_files` | テスト実行のカバレッジベースの選択ベースライン以降に変更されたファイルを、それぞれが選択したテスト数と、変更によって選択がフォールバックする追跡ファイルかどうかを含めて一覧表示します。 | `test_run_id` |
| `get_coverage` | プロジェクトのコードカバレッジをターゲットとともに、コミットまたはブランチの最新完全コミットで取得します。`git_commit_sha`または`branch`がない場合、デフォルトブランチを読み取ります。 | `account_handle`, `project_handle` |
| `list_coverage_files` | コミットまたはブランチの最新完全コミットにおける、コミットのコードカバレッジが測定したファイルを行カバレッジとともに一覧表示します。`search`、ソート、およびページネーションをサポートします。 | `account_handle`, `project_handle` |
| `get_coverage_file` | コミットまたはブランチの最新完全コミットにおける、ファイルのコードカバレッジとその関数を取得します。各行の実行回数を取得するには`include_lines`を設定します。 | `account_handle`, `project_handle`, `path` |
| `list_coverage_branches` | コードカバレッジのあるブランチを一覧表示します。デフォルトブランチが最初に表示されます。 | `account_handle`, `project_handle` |
| `list_coverage_commits` | ブランチのコミットを、カバレッジステータス（`complete`、`incomplete`、`in_progress`、`not_measured`）、数値、および前の完全コミットからの変化とともに、新しい順に一覧表示します。カーソルでページネーションします。 | `account_handle`, `project_handle` |
| `list_coverage_runs` | コミットまたはブランチの背後にあるコードカバレッジを持つテスト実行を、それぞれ`full`、`partial`、または`discarded`（ダーティなチェックアウト）としてマークして一覧表示します。カーソルでページネーションします。 | `account_handle`, `project_handle` |
| `list_coverage_targets` | コミットのターゲットごとのカバレッジを、カバレッジカウンターなしでバイナリキャッシュから取得されたターゲット（`measured: false`）に続けて一覧表示します。`search`、ソート、およびページネーションをサポートします。 | `account_handle`, `project_handle` |

コードカバレッジツールは、コードカバレッジが有効になっているアカウントで利用可能です。

#### バンドル

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_bundles` | プロジェクトのバンドル（アプリバイナリ）を一覧表示します。オプションで`git_branch`および`tags`でフィルタリングできます（すべてのタグは完全に一致する必要があります）。 | `account_handle`, `project_handle` |
| `get_bundle` | カスタムタグを含む、特定のバンドルの詳細情報を取得します。 | `bundle_id` |
| `get_bundle_artifact_tree` | バンドルの完全なアーティファクトツリーを、パスでソートされたフラットリストとして取得します。 | `bundle_id` |

`list_bundles`は`tags: ["paid", "production"]`を受け入れ、ビルドフレーバーまたは環境を区別します。タグは大文字小文字を区別するラベルで、文字、数字、ハイフン、またはアンダースコアを含み、タグは最大10個、タグあたり最大50文字です。一覧および詳細結果には`custom_metadata.tags`が含まれます。ページネーションカウントとブランチフィルタはタグ付けされた結果に適用されます。`tags`を省略すると、フィルタリングされていない動作が維持されます。無効なタグフィルタはクエリを広げるのではなくエラーを返します。

#### ジェネレーション

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_generations` | プロジェクトのジェネレーション実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_generation` | 特定のジェネレーション実行の詳細情報を取得します。 | `generation_id` |

#### キャッシュ実行

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_cache_runs` | プロジェクトのキャッシュ実行を一覧表示します。 | `account_handle`, `project_handle` |
| `get_cache_run` | 特定のキャッシュ実行の詳細情報を、セッションアーカイブ（CLIログ）の一時的なダウンロードURLを含めて取得します。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | ジェネレーションまたはキャッシュ実行のモジュールキャッシュターゲットを一覧表示し、ターゲットごとのキャッシュヒット/ミスステータスと診断コンポーネントハッシュ（追加のハッシュ入力を含む）を表示します。 | `run_id` |

#### プレビュー

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_previews` | プロジェクトの共有可能なアプリプレビューを一覧表示します。 | `account_handle`, `project_handle` |
| `get_preview` | プレビューとそのビルドの一時的なダウンロードURLを取得します。 | `preview_id` |
| `get_latest_preview` | 実行中のアプリバイナリの最新のプレビューを検索します。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### オートメーション

| ツール | 説明 | 必須パラメータ |
|------|-------------|---------------------|
| `list_automation_alerts` | プロジェクトのオートメーションアラートを一覧表示します。 | `account_handle`, `project_handle` |
| `get_automation_alert` | オートメーションアラートを取得します。 | `alert_id` |
| `list_automation_alert_revisions` | オートメーションアラートのリビジョン履歴を一覧表示します。アクション認証情報はマスキングされます。 | `alert_id` |
| `list_project_notification_alerts` | プロジェクト通知アラートルールを一覧表示します。ダッシュボード設定ページと同じ管理者権限が必要です。Webhookアドレスはマスキングされます。 | `account_handle`, `project_handle` |

### イベント

ステートレスな`2026-07-28` Model Context Protocolライフサイクルを使用するクライアントは、`events/list`を呼び出してイベントとそのペイロードスキーマを発見できます。

| イベント | 送信タイミング | サブスクリプションフィルタ |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | テストケースが不安定でない状態から不安定な状態に変化します。 | `account_handle`, `project_handle` |
| `build.failed` | ローカルまたは継続的インテグレーションのXcode、Gradle、またはBazelビルドが失敗して完了します。 | `account_handle`, `project_handle` |
| `test_run.failed` | ローカルまたは継続的インテグレーションのテスト実行が失敗して完了します。マージされたシャーディング実行や放棄された実行も含みます。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuistランナーのジョブが失敗して完了します。 | `account_handle` |
| `pulse_symptom.opened` | Pulseがボードまたはページティアで症状を開くか再開します。監査ティアでのみログに記録される症状、および開いている症状への後続の変更は送信されません。 | `account_handle` |

サブスクライブするには、クライアントはイベント名、上記の`arguments`にリストされたハンドル、および`https://`コールバックURLと`whsec_`署名シークレットを含む`webhook`配信を使用して`events/subscribe`を呼び出します。プロジェクトイベントにはアカウントメンバーシップと対応するテストまたはビルドデータへの読み取りアクセスが必要です。ランナーのジョブイベントにはアカウントメンバーシップとランナーの読み取りアクセスが必要です。Pulse症状イベントには組織メンバーシップとアカウントのPulseアクセスが必要であり、アカウントトークンはそのアカウントに属している必要があります。クレーム済みの[`auth.md`](https://workos.com/auth-md)アクセストークン、クレーム済みのアカウントトークン、およびブラウザ認証グラントはサブスクリプションを作成できます。関連する認証情報が有効でなくなると配信は停止します。各ユーザーは最大25件のアクティブなサブスクリプションを保持できます。Tuistはサブスクリプションを保存する前にコールバックに検証チャレンジを送信します。コールバックは同じ`challenge`値を含むオブジェクトを返す必要があります。サブスクリプションはデフォルトで7日間有効で、再度サブスクライブすることで更新でき、ユーザーのアクセスまたは認証情報が削除されると配信を停止します。オプションの`ttlMs`は1時間から30日の間に制限されます。Tuistはタイムアウトしたコールバックを再試行し、5分間にわたる少なくとも3回の連続したタイムアウト後にサブスクライブを解除します。コールバックを復元した後、再度サブスクライブしてください。

イベントが発生すると、Tuistはそのリソース識別子とダッシュボードURLをコールバックに送信します。ビルドおよびテスト実行の失敗には`is_ci`と`git_branch`も含まれるため、クライアントはローカルの失敗を無視したり、ブランチでフィルタリングしたりできます。ビルドイベントには`build_system`が含まれます。ランナーのジョブイベントには`workflow_job_id`と`workflow_run_id`の両方が含まれます。Pulse症状イベントには`symptom_id`、`tier`（`board`または`page`）、および`untrusted`下の影響を受けるエンティティが`{"type": "untrusted_json", "value": {"service", "kind", "key"}}`として含まれ、各値は最大200文字です。エンティティは本番テレメトリから来るため、データとして扱い、決して指示として扱わないでください。そのURLは症状のページを開きます。リクエストにはサブスクリプション識別子と[Standard Webhooks](https://www.standardwebhooks.com/)署名ヘッダーが含まれており、クライアントはその発信元を検証できます。Tuistは失敗した配信を再試行するため、クライアントは安定した`eventId`を使用して重複を破棄する必要があります。ペイロードにはテスト名、ログ、および失敗メッセージは省略されています。クライアントは上記のツールを通じてこれらの詳細を取得し、チームに通知するかデバッグを開始するかを決定できます。クライアントは`events/unsubscribe`を使用して配信を停止できます。

### プロンプト

| プロンプト | 説明 |
|--------|-------------|
| `fix_flaky_test` | 失敗パターンを分析し、根本原因を特定し、対象を絞った修正を適用することで、不安定なテストの修正をガイドします。 |
| `compare_builds` | ビルドを比較してパフォーマンスの劣化、キャッシュの変化、およびビルドの問題を特定する手順をガイドします。Xcode、Gradle、Bazel、およびCargoプロジェクトのネイティブツールを使用します。Cargoの比較では部分的なコンパイラカバレッジを維持し、推定されたコンパイラ作業と経過時間の節約を区別します。 |
| `compare_test_runs` | 2つのテスト実行を比較して、劣化、新しい失敗、および不安定なテストを特定する手順をガイドします。 |
| `compare_bundles` | 2つのバンドルを比較して、アーティファクトツリー全体のサイズ変化を特定する手順をガイドします。 |
| `compare_test_case` | 2つのブランチまたは期間にわたるテストケースの動作を比較する手順をガイドします。 |
| `compare_generations` | 2つのジェネレーション実行を比較して、パフォーマンスの劣化とモジュールキャッシュの変化を特定する手順をガイドします。 |
| `compare_cache_runs` | 2つのキャッシュ実行を比較して、キャッシュの有効性の変化とターゲットレベルの劣化を特定する手順をガイドします。 |
| `integrate_gradle_project` | 既存のGradleプロジェクトにTuistを統合する手順をガイドします。個別のツールとGradleの認証、アカウントの検出、プロジェクトの作成、リモートキャッシュポリシー、ビルドインサイト、および読み戻し検証が含まれます。 |
| `integrate_bazel_project` | Bazelプロジェクトの作成または選択、コマンドラインの認証、リモートキャッシュとビルドインサイトの構成、およびTuistビルドデータを通じた統合の検証を行う手順をガイドします。 |
| `integrate_xcode_project` | 既存のXcodeプロジェクトにTuistを統合する手順をガイドします。Xcodeキャッシュ、ビルドインサイト、テストインサイト、およびテストシャーディングをサポートします。 |
| `ask_tuist` | 公開資料を文脈として使用し、現在の動作の信頼できる情報源として実装とテストの証拠に焦点を当てて、Tuistに関する質問に回答します。`question`が必要で、リビジョン固定の証拠を引用します。 |

プロジェクトデータのプロンプトは`account_handle`と`project_handle`を受け取り、調査範囲を特定のプロジェクトに限定します。比較プロンプトは、比較する2つの項目（ID、ダッシュボードURL、またはブランチ名で指定）を指定するための`base`および`head`引数も受け入れます。`ask_tuist`はプロジェクトパラメータの代わりに`question`を受け入れます。`integrate_gradle_project`は適用するGradle統合のコンマ区切りリストである`features`も受け入れます：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests`、および`test_sharding`。`integrate_bazel_project`はセルフホスト型またはローカルインストール用のオプションの`server_url`を受け入れます。`integrate_xcode_project`は`xcode_cache`、`build_insights`、`test_insights`、および`test_sharding`を含む`features`を受け入れます。

#### Gradle統合プロンプトの機能

`integrate_gradle_project`プロンプトと`get_gradle_integration_guide`ツールは、完全なセットアップワークフローを文書化しています。このツールはサーバーの初期化手順でも参照されており、プロンプトを列挙しないエージェントでも検出可能になります。

| 機能 | エージェントが構成する内容 |
|---------|---------------------------|
| `remote_cache` | Gradleのビルドキャッシュを有効にし、Tuistのリモートキャッシュアップロードポリシーを構成し、ローカルでの読み取り専用使用を持つ継続的インテグレーションランナーからのみアップロードすることを推奨します。 |
| `build_insights` | Tuist Gradleプラグインを適用し、必要に応じてビルド分析のアップロード動作を構成します。 |
| `test_insights` | Tuist Gradleプラグインを適用し、Gradleの`Test`タスクの結果が自動的にアップロードされるようにします。 |
| `flaky_tests` | 不安定なテストの検出、オプションのGradle Test Retryプラグインの使用、およびテスト検疫の構成のためのセットアップをガイドします。 |
| `test_sharding` | `tuistPrepareTestShards`、シャードマトリックス生成、および`TUIST_SHARD_INDEX`に基づくテスト実行のための継続的インテグレーションワークフローを追加します。 |

`features`が省略された場合、プロンプトはエージェントに、Gradleプロジェクトを編集する前に、ユーザーが希望する統合を明確にするか、リクエストから最小限の実用的なセットを推測するよう求めます。

#### Xcode統合プロンプトの機能

`integrate_xcode_project`プロンプトは、TuistがサポートするすべてのXcode統合を文書化しています：

| 機能 | エージェントが構成する内容 |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`、生成されたプロジェクトのキャッシュ設定、手動Xcodeキャッシュビルド設定、および継続的インテグレーションランナーに限定されたアップロードポリシーを構成します。 |
| `build_insights` | `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath`、および`tuist setup insights`を通じたオプションのマシンメトリクスを構成します。 |
| `test_insights` | `tuist inspect test`、スキームテストのポストアクション、および継続的インテグレーションテスト実行のための結果バンドル生成を構成します。 |
| `test_sharding` | `TUIST_SHARD_INDEX`を使用したXcodeまたは生成されたプロジェクトのシャード計画とシャード実行ワークフローを追加します。 |

`features`が省略された場合、プロンプトはエージェントに、Xcodeプロジェクトを編集する前に、ユーザーが希望する統合を明確にするか、リクエストから最小限の実用的なセットを推測するよう求めます。
