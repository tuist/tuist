---
{
  "title": "テレメトリ",
  "titleTemplate": ":title | セルフホスティング | サーバー | ガイド | Tuist",
  "description": "Prometheus メトリクス、OpenTelemetry トレース、ログ転送で Tuist サーバーを監視します。"
}
---
# テレメトリ {#telemetry}

Tuist は、**メトリクス**（Prometheus）、**トレース**（OpenTelemetry）、**ログ**（Loki 互換）という 3 つの相補的な観測性シグナルを提供します。これらはすべて任意で、独立して有効化できます。

## 分散トレーシング（OpenTelemetry） {#opentelemetry}

Tuist は分散トレーシングのために [OpenTelemetry](https://opentelemetry.io/) をサポートしています。有効にすると、サーバーは HTTP リクエスト（Phoenix および Bandit）、データベースクエリ（Ecto）、送信 HTTP 呼び出し（Finch）、Broadway メッセージ処理のトレースを発行します。これらのトレースにより、リクエストのレイテンシを把握し、低速なクエリを特定し、サービス間でのリクエストを追跡できます。

### 設定 {#opentelemetry-configuration}

トレースのエクスポートを有効にするには、次の環境変数を設定してください。

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry Collector の gRPC エンドポイント（例: Grafana Alloy、Jaeger、または OTLP 互換のコレクター） | いいえ | | `http://localhost:4317` |

この変数が設定されていない場合、トレーシングは無効になり、オーバーヘッドは発生しません。

### インストルメント対象ライブラリ {#opentelemetry-instrumented-libraries}

トレーシングが有効になると、以下のライブラリは自動的にインストルメントされます。

- **Bandit** - HTTP サーバー接続スパン
- **Phoenix** - リクエストライフサイクルスパン（コントローラーアクション、LiveView）
- **Ecto** - クエリメタデータ付きデータベースクエリスパン
- **Finch** - 送信 HTTP クライアントリクエストスパン
- **Broadway** - メッセージ処理パイプラインスパン

### Grafana Alloy を使用した設定例 {#opentelemetry-alloy-example}

コレクターとして [Grafana Alloy](https://grafana.com/docs/alloy/latest/) を使用する場合は、OTLP トレースを受信し、それをトレーシングバックエンド（例: Grafana Cloud Tempo）に転送するように設定してください。

```alloy
otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "0.0.0.0:4317"
  }
  output {
    traces = [otelcol.exporter.otlp.your_backend.input]
  }
}
```

次に、`TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` を Alloy インスタンス（例: `http://alloy:4317`）に向けるように設定します。

## ログ転送（Loki） {#log-forwarding}

Tuist はアプリケーションログを [Loki](https://grafana.com/oss/loki/) 互換のエンドポイントに転送できます。これにより、メトリクスやトレースと合わせてログを一元化し、完全な観測性を実現できます。ログは Loki HTTP プッシュ API（`/loki/api/v1/push`）経由でプッシュされ、`app`、`env`、および `level` のラベルが含まれます。

### 設定 {#log-forwarding-configuration}

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_LOKI_URL` | Loki 互換プッシュ API エンドポイントのベース URL | いいえ | | `http://localhost:3100` |

この変数が設定されていない場合、ログ転送は無効になります。

### Grafana Alloy を使用した設定例 {#log-forwarding-alloy-example}

Grafana Alloy は、その [`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/) コンポーネントを使用してローカルログリレーとして動作できます。

```alloy
loki.source.api "default" {
  http {
    listen_address = "0.0.0.0"
    listen_port    = 3100
  }
  forward_to             = [loki.write.your_backend.receiver]
  use_incoming_timestamp = true
}

loki.write "your_backend" {
  endpoint {
    url = "https://your-loki-instance/loki/api/v1/push"
    basic_auth {
      username = "your-username"
      password = "your-password"
    }
  }
}
```

次に、`TUIST_LOKI_URL=http://alloy:3100` を設定します。

また、プッシュ API を公開している Loki インスタンスに `TUIST_LOKI_URL` を直接向けることもできます。

## Prometheus メトリクス {#prometheus-metrics}

Tuist サーバーが収集したメトリクスを [Prometheus](https://prometheus.io/) と [Grafana](https://grafana.com/) などの可視化ツールを使って取り込み、ニーズに合わせたカスタムダッシュボードを作成できます。Prometheus メトリクスはポート 9091 の `/metrics` エンドポイント経由で提供されます。Prometheus の [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) は 10_000 秒未満に設定してください（観測性とメトリクス取り込みコストのバランスを取るため、30 秒を推奨します）。

## リアルユーザーモニタリング {#real-user-monitoring}

Tuist は、提供される JavaScript にバンドルされた [Grafana Faro](https://grafana.com/oss/faro/) Web SDK を使用して、マーケティングサイト、ドキュメント、およびダッシュボードからのブラウザパフォーマンスを報告できます。Core Web Vitals（Largest Contentful Paint を含む）、キャッチされなかったエラー、ページビューをキャプチャし、それらをあなたが実行する [Faro receiver](https://grafana.com/docs/alloy/latest/reference/components/faro/faro.receiver/) に投稿します。たとえば、Grafana Alloy の `faro.receiver` コンポーネントを使用すると、Loki と Tempo に転送されます。

### 設定 {#real-user-monitoring-configuration}

| 環境変数 | 説明 | 必須 | デフォルト | 例 |
| --- | --- | --- | --- | --- |
| `TUIST_FARO_COLLECTOR_URL` | ブラウザが Faro ペイロードを投稿する URL | いいえ | | `/-/faro` |

> [!NOTE]
> リアルユーザーモニタリングは、`TUIST_FARO_COLLECTOR_URL` が設定されている場合のみ有効になります。設定されていない場合、ブラウザテレメトリは収集されず、サードパーティ製スクリプトも読み込まれません。

`/-/faro` のような同一オリジンパスを使用すると、クロスオリジンリクエストを回避し、ブラウザのコンテンツセキュリティポリシーを変更せずに済みます。イングレス経由で Faro レシーバーに向けるように設定してください。

### 収集対象 {#real-user-monitoring-collected}

- **Web Vitals**: LCP、CLS、INP、FCP、TTFB。ブラウザによって自動的にキャプチャされます
- **ページビュー**: ロード時および Phoenix LiveView ナビゲーション時に記録されます
- **ビュー**: 各ペイロードには、それを生成したセクションが含まれます — `marketing`、`docs`、`dashboard`、または `api-docs`
- **エラー**: キャッチされなかった例外と処理されなかった Promise の拒否

### プライバシーに関する考慮事項 {#real-user-monitoring-privacy}

- ユーザー識別情報は付与されません。ペイロードにはユーザー ID、メールアドレス、アカウント情報は含まれません
- セッションは訪問をまたいで永続化されないため、ブラウザストレージには何も書き込まれません
- コンソールキャプチャは無効になっているため、アプリケーションログ出力がブラウザから送信されることはありません

## Elixir メトリクス {#elixir-metrics}

デフォルトでは、Elixir ランタイム、BEAM、Elixir、および使用しているライブラリの一部のメトリクスを含めています。以下は、確認できるメトリクスの一例です。

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

利用可能なメトリクスとその使用方法を確認するため、これらのページをチェックすることを推奨します。

## Runs メトリクス {#runs-metrics}

Tuist Runs に関連するメトリクスのセットです。

### `tuist_runs_total`（カウンター） {#tuist_runs_total-counter}

Tuist Runs の総数です。

#### タグ {#tuist-runs-total-tags}

| タグ | 説明 |
|--- | ---- |
| `name` | 実行された `tuist` コマンドの名前（例: `build`、`test` など） |
| `is_ci` | 実行環境が CI か開発者のマシンかを示すブール値です。 |
| `status` | `success`の場合は`0`、`failure`の場合は`1`。 |

### `tuist_runs_duration_milliseconds`（ヒストグラム） {#tuist_runs_duration_milliseconds-histogram}

各 tuist 実行の合計所要時間（ミリ秒単位）。

#### タグ {#tuist-runs-duration-miliseconds-tags}

| タグ | 説明 |
|--- | ---- |
| `name` | 実行された `tuist` コマンドの名前（例: `build`、`test` など） |
| `is_ci` | 実行環境が CI か開発者のマシンかを示すブール値です。 |
| `status` | `success`の場合は`0`、`failure`の場合は`1`。 |

## キャッシュメトリクス {#cache-metrics}

Tuist Cache に関連するメトリクスのセットです。

### `tuist_cache_events_total`（カウンター） {#tuist_cache_events_total-counter}

バイナリキャッシュイベントの総数です。

#### タグ {#tuist-cache-events-total-tags}

| タグ | 説明 |
|--- | ---- |
| `event_type` | `local_hit`、`remote_hit`、または `miss` のいずれかになります。 |

### `tuist_cache_uploads_total`（カウンター） {#tuist_cache_uploads_total-counter}

バイナリキャッシュへのアップロード回数です。

### `tuist_cache_uploaded_bytes`（合計） {#tuist_cache_uploaded_bytes-sum}

バイナリキャッシュにアップロードされたバイト数です。

### `tuist_cache_downloads_total`（カウンター） {#tuist_cache_downloads_total-counter}

バイナリキャッシュからのダウンロード回数です。

### `tuist_cache_downloaded_bytes`（合計） {#tuist_cache_downloaded_bytes-sum}

バイナリキャッシュからダウンロードされたバイト数です。

---

## プレビューメトリクス {#previews-metrics}

プレビュー機能に関連するメトリクスのセットです。

### `tuist_previews_uploads_total`（合計） {#tuist_previews_uploads_total-counter}

アップロードされたプレビューの総数です。

### `tuist_previews_downloads_total`（合計） {#tuist_previews_downloads_total-counter}

ダウンロードされたプレビューの総数です。

---

## ストレージメトリクス {#storage-metrics}

リモートストレージ（例: S3）におけるアーティファクトの保存に関連するメトリクスのセットです。

> [!TIP]
> これらのメトリクスは、ストレージ操作のパフォーマンスを理解し、潜在的なボトルネックを特定するのに役立ちます。


### `tuist_storage_get_object_size_size_bytes`（ヒストグラム） {#tuist_storage_get_object_size_size_bytes-histogram}

リモートストレージから取得したオブジェクトのサイズ（バイト単位）です。

#### タグ {#tuist-storage-get-object-size-size-bytes-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |


### `tuist_storage_get_object_size_duration_miliseconds`（ヒストグラム） {#tuist_storage_get_object_size_duration_miliseconds-histogram}

リモートストレージからオブジェクトのサイズを取得する際の所要時間（ミリ秒単位）。

#### タグ {#tuist-storage-get-object-size-duration-miliseconds-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |


### `tuist_storage_get_object_size_count`（カウンター） {#tuist_storage_get_object_size_count-counter}

リモートストレージからオブジェクトのサイズを取得した回数です。

#### タグ {#tuist-storage-get-object-size-count-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |

### `tuist_storage_delete_all_objects_duration_milliseconds`（ヒストグラム） {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

リモートストレージからすべてのオブジェクトを削除する際の所要時間（ミリ秒単位）。

#### タグ {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| タグ | 説明 |
|--- | ---- |
| `project_slug` | オブジェクトが削除されるプロジェクトのスラッグです。 |


### `tuist_storage_delete_all_objects_count`（カウンター） {#tuist_storage_delete_all_objects_count-counter}

リモートストレージからプロジェクトのすべてのオブジェクトを削除した回数です。

#### タグ {#tuist-storage-delete-all-objects-count-tags}

| タグ | 説明 |
|--- | ---- |
| `project_slug` | オブジェクトが削除されるプロジェクトのスラッグです。 |


### `tuist_storage_multipart_start_upload_duration_milliseconds`（ヒストグラム） {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

リモートストレージへのアップロードを開始する際の所要時間（ミリ秒単位）。

#### タグ {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |

### `tuist_storage_multipart_start_upload_duration_count`（カウンター） {#tuist_storage_multipart_start_upload_duration_count-counter}

リモートストレージへのアップロードを開始した回数です。

#### タグ {#tuist-storage-multipart-start-upload-duration-count-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |


### `tuist_storage_get_object_as_string_duration_milliseconds`（ヒストグラム） {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

リモートストレージからオブジェクトを文字列として取得する際の所要時間（ミリ秒単位）。

#### タグ {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |

### `tuist_storage_get_object_as_string_count`（カウント） {#tuist_storage_get_object_as_string_count-count}

リモートストレージからオブジェクトを文字列として取得した回数です。

#### タグ {#tuist-storage-get-object-as-string-count-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |


### `tuist_storage_check_object_existence_duration_milliseconds`（ヒストグラム） {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

リモートストレージ内のオブジェクトの存在を確認する際の所要時間（ミリ秒単位）。

#### タグ {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |

### `tuist_storage_check_object_existence_count`（カウント） {#tuist_storage_check_object_existence_count-count}

リモートストレージでオブジェクトの存在を確認した回数です。

#### タグ {#tuist-storage-check-object-existence-count-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds`（ヒストグラム） {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

リモートストレージ内のオブジェクトのダウンロード用署名付きURLを生成する際の所要時間（ミリ秒単位）。

#### タグ {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |


### `tuist_storage_generate_download_presigned_url_count`（カウント） {#tuist_storage_generate_download_presigned_url_count-count}

リモートストレージ内のオブジェクトのダウンロード用署名付きURLを生成した回数です。

#### タグ {#tuist-storage-generate-download-presigned-url-count-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds`（ヒストグラム） {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

リモートストレージ内のオブジェクトのパートアップロード用署名付きURLを生成する際の所要時間（ミリ秒単位）。

#### タグ {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |
| `part_number` | アップロード中のオブジェクトのパート番号です。 |
| `upload_id` | マルチパートアップロードのアップロードIDです。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count`（カウント） {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

リモートストレージ内のオブジェクトのパートアップロード用署名付きURLを生成した回数です。

#### タグ {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |
| `part_number` | アップロード中のオブジェクトのパート番号です。 |
| `upload_id` | マルチパートアップロードのアップロードIDです。 |

### `tuist_storage_multipart_complete_upload_duration_milliseconds`（ヒストグラム） {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

リモートストレージへのアップロードを完了する際の所要時間（ミリ秒単位）。

#### タグ {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |
| `upload_id` | マルチパートアップロードのアップロードIDです。 |


### `tuist_storage_multipart_complete_upload_count`（カウント） {#tuist_storage_multipart_complete_upload_count-count}

リモートストレージへのアップロードが完了した総回数です。

#### タグ {#tuist-storage-multipart-complete-upload-count-tags}

| タグ | 説明 |
|--- | ---- |
| `object_key` | リモートストレージ内のオブジェクトのルックアップキーです。 |
| `upload_id` | マルチパートアップロードのアップロードIDです。 |

---

## 認証メトリクス {#authentication-metrics}

認証に関連するメトリクスのセットです。

### `tuist_authentication_token_refresh_error_total`（カウンター） {#tuist_authentication_token_refresh_error_total-counter}

トークン更新エラーの総数です。

#### タグ {#tuist-authentication-token-refresh-error-total-tags}

| タグ | 説明 |
|--- | ---- |
| `cli_version` | エラーが発生したTuist CLIのバージョンです。 |
| `reason` | トークン更新エラーの理由（例: `invalid_token_type` または `invalid_token`）。 |

---

## プロジェクトメトリクス {#projects-metrics}

プロジェクトに関連するメトリクスのセットです。

### `tuist_projects_total`（最新値） {#tuist_projects_total-last_value}

プロジェクトの総数です。

---

## アカウントメトリクス {#accounts-metrics}

アカウント（ユーザーと組織）に関連するメトリクスのセットです。

### `tuist_accounts_organizations_total`（最新値） {#tuist_accounts_organizations_total-last_value}

組織の総数です。

### `tuist_accounts_users_total`（最新値） {#tuist_accounts_users_total-last_value}

ユーザーの総数です。


## データベースメトリクス {#database-metrics}

データベース接続に関連するメトリクスのセットです。

リポジトリプールメトリクスは内部で100msごとにサンプリングされ、`/metrics` でPrometheusに公開されます。以下の `last_value` メトリクスは、スクレイプ時点での最新のプール状態を示します。後述のプレッシャーメトリクスは、それらの100msサンプルから導出された合計値であり、次のスクレイプ前に回復した場合でも、短時間の飽和ウィンドウを検出しやすくします。

### `tuist_repo_pool_checkout_queue_length`（最新値） {#tuist_repo_pool_checkout_queue_length-last_value}

データベース接続への割り当てを待ってキューに入っているデータベースクエリの数です。

#### タグ {#tuist_repo_pool_checkout_queue_length-tags}

| タグ | 説明 |
|--- | ---- |
| `repo` | メトリクスを発行したリポジトリ（例: `postgres`、`clickhouse_read`、または `clickhouse_write`）。 |
| `database` | 基盤となるデータベースタイプ（例: `postgres` または `clickhouse`）。 |

### `tuist_repo_pool_ready_conn_count`（最新値） {#tuist_repo_pool_ready_conn_count-last_value}

データベースクエリへの割り当て準備ができているデータベース接続の数です。

#### タグ {#tuist_repo_pool_ready_conn_count-tags}

| タグ | 説明 |
|--- | ---- |
| `repo` | メトリクスを発行したリポジトリ（例: `postgres`、`clickhouse_read`、または `clickhouse_write`）。 |
| `database` | 基盤となるデータベースタイプ（例: `postgres` または `clickhouse`）。 |

### `tuist_repo_pool_size`（最新値） {#tuist_repo_pool_size-last_value}

プールで構成された接続数です。

#### タグ {#tuist_repo_pool_size-tags}

| タグ | 説明 |
|--- | ---- |
| `repo` | メトリクスを発行したリポジトリ（例: `postgres`、`clickhouse_read`、または `clickhouse_write`）。 |
| `database` | 基盤となるデータベースタイプ（例: `postgres` または `clickhouse`）。 |

### `tuist_repo_pool_checkout_queue_total_samples_sum`（合計） {#tuist_repo_pool_checkout_queue_total_samples_sum-sum}

実行されたリポジトリプールポーリングの総数（ポーリングごとに1ずつ増加）。ビジー率や飢餓率を計算する際の分母として使用します: `rate(busy_samples) / rate(total_samples)` または `rate(starved_samples) / rate(total_samples)`。

#### タグ {#tuist_repo_pool_checkout_queue_total_samples_sum-tags}

| タグ | 説明 |
|--- | ---- |
| `repo` | メトリクスを発行したリポジトリ（例: `postgres`、`clickhouse_read`、または `clickhouse_write`）。 |
| `database` | 基盤となるデータベースタイプ（例: `postgres` または `clickhouse`）。 |

### `tuist_repo_pool_checkout_queue_observed_sum`（合計） {#tuist_repo_pool_checkout_queue_observed_sum-sum}

リポジトリプールポーリング全体で観測されたキューイングされたチェックアウト要求の合計です。最新のキュー長サンプルだけでは検出できない、プールの競合の短期的なバーストを検出するのに役立ちます。

#### タグ {#tuist_repo_pool_checkout_queue_observed_sum-tags}

| タグ | 説明 |
|--- | ---- |
| `repo` | メトリクスを発行したリポジトリ（例: `postgres`、`clickhouse_read`、または `clickhouse_write`）。 |
| `database` | 基盤となるデータベースタイプ（例: `postgres` または `clickhouse`）。 |

### `tuist_repo_pool_checkout_queue_busy_samples_sum`（合計） {#tuist_repo_pool_checkout_queue_busy_samples_sum-sum}

少なくとも1つのデータベースチェックアウト要求がキューで待機していたリポジトリプールポーリングの数です。

#### タグ {#tuist_repo_pool_checkout_queue_busy_samples_total-tags}

| タグ | 説明 |
|--- | ---- |
| `repo` | メトリクスを発行したリポジトリ（例: `postgres`、`clickhouse_read`、または `clickhouse_write`）。 |
| `database` | 基盤となるデータベースタイプ（例: `postgres` または `clickhouse`）。 |

### `tuist_repo_pool_checkout_queue_starved_samples_sum`（合計） {#tuist_repo_pool_checkout_queue_starved_samples_sum-sum}

チェックアウト要求がキューイングされ、利用可能な接続がなかったリポジトリプールポーリングの数です。ここで持続的な増加が見られる場合、通常はプールが飽和状態であることを意味します。

#### タグ {#tuist_repo_pool_checkout_queue_starved_samples_total-tags}

| タグ | 説明 |
|--- | ---- |
| `repo` | メトリクスを発行したリポジトリ（例: `postgres`、`clickhouse_read`、または `clickhouse_write`）。 |
| `database` | 基盤となるデータベースタイプ（例: `postgres` または `clickhouse`）。 |

### `tuist_repo_pool_db_connection_connected`（カウンター） {#tuist_repo_pool_db_connection_connected-counter}

データベースに確立された接続の数です。

### `tuist_repo_pool_db_connection_disconnected`（カウンター） {#tuist_repo_pool_db_connection_disconnected-counter}

データベースから切断された接続の数です。

#### タグ {#tuist_repo_pool_db_connection_connected_and_disconnected-tags}

| タグ | 説明 |
|--- | ---- |
| `tag` | 発行元リポジトリを識別するDBConnectionリスナーのタグです。 |

## HTTPメトリクス {#http-metrics}

TuistがHTTP経由で他のサービスとやり取りする際に関連するメトリクスのセットです。

### `tuist_http_request_count`（カウンター） {#tuist_http_request_count-last_value}

送信されたHTTPリクエストの数です。

### `tuist_http_request_duration_nanosecond_sum`（合計） {#tuist_http_request_duration_nanosecond_sum-last_value}

送信リクエストの所要時間の合計（接続への割り当て待ち時間を含む）。

### `tuist_http_request_duration_nanosecond_bucket`（分布） {#tuist_http_request_duration_nanosecond_bucket-distribution}
送信リクエストの所要時間の分布（接続への割り当て待ち時間を含む）。

### `tuist_http_queue_count`（カウンター） {#tuist_http_queue_count-counter}

プールから取得されたリクエストの数です。

### `tuist_http_queue_duration_nanoseconds_sum`（合計） {#tuist_http_queue_duration_nanoseconds_sum-sum}

プールから接続を取得するのに要する時間です。

### `tuist_http_queue_idle_time_nanoseconds_sum`（合計） {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

取得待ちの間、接続がアイドル状態だった時間です。

### `tuist_http_queue_duration_nanoseconds_bucket`（分布） {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

プールから接続を取得するのに要する時間です。

### `tuist_http_queue_idle_time_nanoseconds_bucket`（分布） {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

取得待ちの間、接続がアイドル状態だった時間です。

### `tuist_http_connection_count`（カウンター） {#tuist_http_connection_count-counter}

確立された接続の数です。

### `tuist_http_connection_duration_nanoseconds_sum`（合計） {#tuist_http_connection_duration_nanoseconds_sum-sum}

ホストへの接続を確立するのに要する時間です。

### `tuist_http_connection_duration_nanoseconds_bucket`（分布） {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

ホストへの接続を確立するのに要する時間の分布です。

### `tuist_http_send_count`（カウンター） {#tuist_http_send_count-counter}

プールからの接続に割り当てられた後に送信されたリクエストの数です。

### `tuist_http_send_duration_nanoseconds_sum`（合計） {#tuist_http_send_duration_nanoseconds_sum-sum}

プールからの接続に割り当てられた後にリクエストが完了するまでに要する時間です。

### `tuist_http_send_duration_nanoseconds_bucket`（分布） {#tuist_http_send_duration_nanoseconds_bucket-distribution}

プールからの接続に割り当てられた後にリクエストが完了するまでに要する時間の分布です。

### `tuist_http_receive_count`（カウンター） {#tuist_http_receive_count-counter}

送信されたリクエストから受信したレスポンスの数です。

### `tuist_http_receive_duration_nanoseconds_sum`（合計） {#tuist_http_receive_duration_nanoseconds_sum-sum}

レスポンスの受信に費やした時間です。

### `tuist_http_receive_duration_nanoseconds_bucket`（分布） {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

レスポンスの受信に費やした時間の分布です。

### `tuist_http_queue_available_connections`（最新値） {#tuist_http_queue_available_connections-last_value}

キューで利用可能な接続の数です。

### `tuist_http_queue_in_use_connections`（最新値） {#tuist_http_queue_in_use_connections-last_value}

使用中のキュー接続の数です。
