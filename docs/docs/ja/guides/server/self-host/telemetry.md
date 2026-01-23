---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# テレメトリー{#telemetry}

Tuistサーバーが収集したメトリクスは[Prometheus](https://prometheus.io/)と[Grafana](https://grafana.com/)などの可視化ツールで取り込み、ニーズに合わせたカスタムダッシュボードを作成できます。
Prometheusメトリクスは、` の/metricsエンドポイント（`
、ポート9091）経由で提供されます。Prometheusの[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)は10_000秒未満に設定してください（デフォルトの15秒を維持することを推奨します）。

## PostHog アナリティクス{#posthog-analytics}

Tuistはユーザー行動分析とイベント追跡のために[PostHog](https://posthog.com/)と連携します。これにより、ユーザーがTuistサーバーとどのようにやり取りしているかを理解し、機能の使用状況を追跡し、マーケティングサイト、ダッシュボード、APIドキュメント全体にわたるユーザー行動に関する洞察を得ることができます。

### 設定{#posthog-configuration}

PostHogの統合はオプションであり、適切な環境変数を設定することで有効化できます。設定すると、Tuistはユーザーイベント、ページビュー、ユーザージャーニーを自動的に追跡します。

| 環境変数                    | 説明                      | 必須  | デフォルト | 例                                                 |
| ----------------------- | ----------------------- | --- | ----- | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | あなたのPostHogプロジェクトAPIキー  | いいえ |       | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | PostHog API エンドポイント URL | いいえ |       | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
`TUIST_POSTHOG_API_KEY` と`TUIST_POSTHOG_URL`
の両方が設定されている場合にのみ、アナリティクスが有効になります。いずれかの変数が欠けている場合、アナリティクスイベントは送信されません。
<!-- -->
:::

### 機能{#posthog-features}

PostHogが有効な場合、Tuistは自動的に以下を追跡します：

- **ユーザー識別**: ユーザーは固有のIDとメールアドレスで識別されます
- **ユーザーエイリアシング**: 識別を容易にするため、ユーザーはアカウント名でエイリアス化されます
- **グループ分析**: ユーザーは選択したプロジェクトと組織ごとにグループ化され、セグメント化された分析が可能です
- **ページセクション**: イベントには、アプリケーションのどのセクションで生成されたかを示すスーパープロパティが含まれます:
  - `marketing` - マーケティングページおよび公開コンテンツからのイベント
  - `dashboard` - メインアプリケーションのダッシュボードおよび認証済みエリアからのイベント
  - `api-docs` - APIドキュメントページからのイベント
- **ページビュー**: Phoenix LiveView を使用したページナビゲーションの自動追跡
- **カスタムイベント**: 機能使用とユーザー操作に関するアプリケーション固有のイベント

### プライバシーに関する考慮事項{#posthog-privacy}

- 認証済みユーザーの場合、PostHogはユーザー固有のIDを一意の識別子として使用し、メールアドレスを含めます
- 匿名ユーザーの場合、PostHogはデータをローカルに保存しないようメモリのみによる永続化を使用します
- すべての分析はユーザーのプライバシーを尊重し、データ保護のベストプラクティスに従います
- PostHogのデータは、PostHogのプライバシーポリシーおよびお客様の設定に従って処理されます

## Elixir metrics{#elixir-metrics}

デフォルトでは、Elixirランタイム、BEAM、Elixir、および使用しているライブラリの一部に関するメトリクスを含みます。以下は、確認できるメトリクスの例です：

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

利用可能な指標とその使用方法については、該当ページを確認することをお勧めします。

## 実行メトリクス{#runs-metrics}

Tuist Runsに関連する一連の指標。

### `tuist_runs_total` (カウンター){#tuist_runs_total-counter}

Tuist Runsの総数。

#### タグ{#tuist-runs-total-tags}

| Tag      | 説明                                        |
| -------- | ----------------------------------------- |
| `name`   | 実行された`tuistの` コマンド名（例：`build` 、`test` など） |
| `is_ci`  | 実行環境がCIサーバーか開発者マシンかを示すブール値。               |
| `status` | ``` 0`の成功時`,`1`の失敗時`.                     |

### `tuist_runs_duration_milliseconds` (histogram){#tuist_runs_duration_milliseconds-histogram}

各tuistの実行時間の合計（ミリ秒単位）。

#### タグ{#tuist-runs-duration-miliseconds-tags}

| Tag      | 説明                                        |
| -------- | ----------------------------------------- |
| `name`   | 実行された`tuistの` コマンド名（例：`build` 、`test` など） |
| `is_ci`  | 実行環境がCIサーバーか開発者マシンかを示すブール値。               |
| `status` | ``` 0`の成功時`,`1`の失敗時`.                     |

## キャッシュメトリクス{#cache-metrics}

Tuist Cacheに関連する一連のメトリクス。

### `tuist_cache_events_total` (カウンター){#tuist_cache_events_total-counter}

バイナリキャッシュイベントの総数。

#### タグ{#tuist-cache-events-total-tags}

| Tag          | 説明                                             |
| ------------ | ---------------------------------------------- |
| `event_type` | `local_hit` 、`remote_hit` 、 または`miss` のいずれかです。 |

### `tuist_cache_uploads_total` (カウンター){#tuist_cache_uploads_total-counter}

バイナリキャッシュへのアップロード回数。

### `tuist_cache_uploaded_bytes` (合計){#tuist_cache_uploaded_bytes-sum}

バイナリキャッシュにアップロードされたバイト数。

### `tuist_cache_downloads_total` (カウンター){#tuist_cache_downloads_total-counter}

バイナリキャッシュへのダウンロード回数。

### `tuist_cache_downloaded_bytes` (合計){#tuist_cache_downloaded_bytes-sum}

バイナリキャッシュからダウンロードされたバイト数。

---

## プレビュー指標{#previews-metrics}

プレビュー機能に関連する一連の指標。

### `tuist_previews_uploads_total` (合計){#tuist_previews_uploads_total-counter}

アップロードされたプレビューの総数。

### `tuist_previews_downloads_total` (合計){#tuist_previews_downloads_total-counter}

ダウンロードされたプレビューの総数。

---

## ストレージ指標{#storage-metrics}

リモートストレージ（例：s3）におけるアーティファクトの保存に関連する一連のメトリクス。

::: チップ
<!-- -->
これらの指標は、ストレージ操作のパフォーマンスを理解し、潜在的なボトルネックを特定するのに役立ちます。
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (histogram){#tuist_storage_get_object_size_size_bytes-histogram}

リモートストレージから取得したオブジェクトのサイズ（バイト単位）。

#### タグ{#tuist-storage-get-object-size-size-bytes-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |


### `tuist_storage_get_object_size_duration_miliseconds` (histogram){#tuist_storage_get_object_size_duration_miliseconds-histogram}

リモートストレージからオブジェクトサイズを取得する時間（ミリ秒単位）。

#### タグ{#tuist-storage-get-object-size-duration-miliseconds-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |


### `tuist_storage_get_object_size_count` (counter){#tuist_storage_get_object_size_count-counter}

リモートストレージからオブジェクトサイズが取得された回数。

#### タグ{#tuist-storage-get-object-size-count-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_delete_all_objects_duration_milliseconds` （ヒストグラム）{#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

リモートストレージから全てのオブジェクトを削除する時間（ミリ秒単位）。

#### タグ{#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Tag            | 説明                             |
| -------------- | ------------------------------ |
| `project_slug` | オブジェクトが削除されるプロジェクトのプロジェクトスラッグ。 |


### `tuist_storage_delete_all_objects_count` (カウンター){#tuist_storage_delete_all_objects_count-counter}

リモートストレージからすべてのプロジェクトオブジェクトが削除された回数。

#### タグ{#tuist-storage-delete-all-objects-count-tags}

| Tag            | 説明                             |
| -------------- | ------------------------------ |
| `project_slug` | オブジェクトが削除されるプロジェクトのプロジェクトスラッグ。 |


### `tuist_storage_multipart_start_upload_duration_milliseconds` （ヒストグラム）{#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

リモートストレージへのアップロード開始までの時間（ミリ秒単位）。

#### タグ{#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_multipart_start_upload_duration_count` (カウンター){#tuist_storage_multipart_start_upload_duration_count-counter}

リモートストレージへのアップロードが開始された回数。

#### タグ{#tuist-storage-multipart-start-upload-duration-count-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histogram){#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

リモートストレージからオブジェクトを文字列として取得する時間（ミリ秒単位）。

#### タグ{#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_get_object_as_string_count` (count){#tuist_storage_get_object_as_string_count-count}

リモートストレージからオブジェクトが文字列として取得された回数。

#### タグ{#tuist-storage-get-object-as-string-count-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |


### `tuist_storage_check_object_existence_duration_milliseconds` (histogram){#tuist_storage_check_object_existence_duration_milliseconds-histogram}

リモートストレージ内のオブジェクトの存在を確認する時間（ミリ秒単位）。

#### タグ{#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_check_object_existence_count` (count){#tuist_storage_check_object_existence_count-count}

リモートストレージにおけるオブジェクトの存在確認回数。

#### タグ{#tuist-storage-check-object-existence-count-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histogram){#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

リモートストレージ内のオブジェクトに対して事前署名済みダウンロードURLを生成する時間（ミリ秒単位）。

#### タグ{#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |


### `tuist_storage_generate_download_presigned_url_count` (count){#tuist_storage_generate_download_presigned_url_count-count}

リモートストレージ内のオブジェクトに対して事前署名済みダウンロードURLが生成された回数。

#### タグ{#tuist-storage-generate-download-presigned-url-count-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` （ヒストグラム）{#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

リモートストレージ内のオブジェクトに対する部分アップロード事前署名URLを生成する時間（ミリ秒単位）。

#### タグ{#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Tag           | 説明                            |
| ------------- | ----------------------------- |
| `オブジェクト・キー`   | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |
| `part_number` | アップロード対象オブジェクトの部品番号。          |
| `upload_id`   | マルチパートアップロードのアップロードID。        |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count){#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

リモートストレージ内のオブジェクトに対して、事前署名済みURLがアップロードされた回数。

#### タグ{#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Tag           | 説明                            |
| ------------- | ----------------------------- |
| `オブジェクト・キー`   | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |
| `part_number` | アップロード対象オブジェクトの部品番号。          |
| `upload_id`   | マルチパートアップロードのアップロードID。        |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` （ヒストグラム）{#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

リモートストレージへのアップロード完了までの所要時間（ミリ秒単位）。

#### タグ{#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |
| `upload_id` | マルチパートアップロードのアップロードID。        |


### `tuist_storage_multipart_complete_upload_count` (count){#tuist_storage_multipart_complete_upload_count-count}

リモートストレージへのアップロードが完了した総回数。

#### タグ{#tuist-storage-multipart-complete-upload-count-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |
| `upload_id` | マルチパートアップロードのアップロードID。        |

---

## 認証メトリクス{#authentication-metrics}

認証に関連する一連の指標。

### `tuist_authentication_token_refresh_error_total` （カウンター）{#tuist_authentication_token_refresh_error_total-counter}

トークン更新エラーの総数。

#### タグ{#tuist-authentication-token-refresh-error-total-tags}

| Tag           | 説明                                                    |
| ------------- | ----------------------------------------------------- |
| `cli_version` | エラーが発生したTuist CLIのバージョン。                              |
| `理由`          | トークン更新エラーの原因例：`invalid_token_type` または`invalid_token` |

---

## プロジェクト指標{#projects-metrics}

プロジェクトに関連する一連の指標。

### `tuist_projects_total` (last_value){#tuist_projects_total-last_value}

プロジェクトの総数。

---

## アカウント指標{#accounts-metrics}

アカウント（ユーザーおよび組織）に関連する一連の指標。

### `tuist_accounts_organizations_total` (last_value){#tuist_accounts_organizations_total-last_value}

組織の総数。

### `tuist_accounts_users_total` (last_value){#tuist_accounts_users_total-last_value}

総ユーザー数。


## データベース指標{#database-metrics}

データベース接続に関連する一連のメトリクス。

### `tuist_repo_pool_checkout_queue_length` (last_value){#tuist_repo_pool_checkout_queue_length-last_value}

データベース接続に割り当てられるのを待機しているキュー内のデータベースクエリの数。

### `tuist_repo_pool_ready_conn_count` (last_value){#tuist_repo_pool_ready_conn_count-last_value}

データベースクエリに割り当て可能な状態にあるデータベース接続の数。


### `tuist_repo_pool_db_connection_connected` (カウンター){#tuist_repo_pool_db_connection_connected-counter}

データベースに確立された接続の数。

### `tuist_repo_pool_db_connection_disconnected` (カウンター){#tuist_repo_pool_db_connection_disconnected-counter}

データベースから切断された接続の数。

## HTTPメトリクス{#http-metrics}

TuistがHTTP経由で他のサービスとやり取りする際に関連する一連のメトリクス。

### `tuist_http_request_count` (カウンター){#tuist_http_request_count-last_value}

送信されるHTTPリクエストの数。

### `tuist_http_request_duration_nanosecond_sum` (合計){#tuist_http_request_duration_nanosecond_sum-last_value}

送信リクエストの合計時間（接続割り当て待ち時間を含む）。

### `tuist_http_request_duration_nanosecond_bucket` (distribution){#tuist_http_request_duration_nanosecond_bucket-distribution}
送信リクエストの所要時間分布（接続割り当て待機時間を含む）。

### `tuist_http_queue_count` （カウンター）{#tuist_http_queue_count-counter}

プールから取得されたリクエストの数。

### `tuist_http_queue_duration_nanoseconds_sum` (合計){#tuist_http_queue_duration_nanoseconds_sum-sum}

プールから接続を取得するのにかかる時間。

### `tuist_http_queue_idle_time_nanoseconds_sum` (合計){#tuist_http_queue_idle_time_nanoseconds_sum-sum}

接続が取得待機状態でアイドル状態だった時間。

### `tuist_http_queue_duration_nanoseconds_bucket` (distribution){#tuist_http_queue_duration_nanoseconds_bucket-distribution}

プールから接続を取得するのにかかる時間。

### `tuist_http_queue_idle_time_nanoseconds_bucket` (distribution){#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

接続が取得待機状態でアイドル状態だった時間。

### `tuist_http_connection_count` (カウンター){#tuist_http_connection_count-counter}

確立された接続の数。

### `tuist_http_connection_duration_nanoseconds_sum` (合計値){#tuist_http_connection_duration_nanoseconds_sum-sum}

ホストに対する接続確立にかかる時間。

### `tuist_http_connection_duration_nanoseconds_bucket` (distribution){#tuist_http_connection_duration_nanoseconds_bucket-distribution}

ホストに対する接続確立時間の分布。

### `tuist_http_send_count` (カウンター){#tuist_http_send_count-counter}

プールから接続に割り当てられた後に送信されたリクエストの数。

### `tuist_http_send_duration_nanoseconds_sum` (合計値){#tuist_http_send_duration_nanoseconds_sum-sum}

プールから接続に割り当てられた後、リクエストが完了するまでの所要時間。

### `tuist_http_send_duration_nanoseconds_bucket` (distribution){#tuist_http_send_duration_nanoseconds_bucket-distribution}

プールから接続に割り当てられた後、リクエストが完了するまでの時間の分布。

### `tuist_http_receive_count` (カウンター){#tuist_http_receive_count-counter}

送信したリクエストから受信した応答の数。

### `tuist_http_receive_duration_nanoseconds_sum` (合計){#tuist_http_receive_duration_nanoseconds_sum-sum}

応答を受信するのに要した時間。

### `tuist_http_receive_duration_nanoseconds_bucket` (distribution){#tuist_http_receive_duration_nanoseconds_bucket-distribution}

応答受信に要した時間の分布。

### `tuist_http_queue_available_connections` (last_value){#tuist_http_queue_available_connections-last_value}

キュー内で利用可能な接続数。

### `tuist_http_queue_in_use_connections` (last_value){#tuist_http_queue_in_use_connections-last_value}

使用中のキュー接続の数。
