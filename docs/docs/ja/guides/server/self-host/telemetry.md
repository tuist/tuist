---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# テレメトリ{#telemetry}

[Prometheus](https://prometheus.io/) を使用して Tuist
サーバーが収集したメトリクスをインポートし、[Grafana](https://grafana.com/)
などの可視化ツールを使って、ニーズに合わせたカスタムダッシュボードを作成できます。 Prometheusメトリクスは、ポート9091の`/metrics`
エンドポイント経由で提供されます。Prometheusの
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
は10,000秒未満に設定してください（デフォルトの15秒のままにすることを推奨します）。

## PostHog アナリティクス{#posthog-analytics}

Tuistは、ユーザー行動分析とイベント追跡のために[PostHog](https://posthog.com/)と連携しています。これにより、ユーザーがTuistサーバーとどのようにやり取りしているかを把握し、機能の利用状況を追跡し、マーケティングサイト、ダッシュボード、APIドキュメント全体におけるユーザー行動に関する洞察を得ることができます。

### 設定{#posthog-configuration}

PostHog との統合はオプションであり、適切な環境変数を設定することで有効化できます。設定が完了すると、Tuist
はユーザーイベント、ページビュー、およびユーザージャーニーを自動的に追跡します。

| 環境変数                    | 説明                     | 必須  | デフォルト | 例                                                 |
| ----------------------- | ---------------------- | --- | ----- | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | PostHogプロジェクトのAPIキー    | いいえ |       | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | PostHog APIのエンドポイントURL | いいえ |       | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
アナリティクスは、`TUIST_POSTHOG_API_KEY` および`TUIST_POSTHOG_URL`
の両方が設定されている場合にのみ有効になります。いずれかの変数が欠けている場合、アナリティクスイベントは送信されません。
<!-- -->
:::

### 機能{#posthog-features}

PostHogが有効になっている場合、Tuistは自動的に以下を追跡します：

- **ユーザー識別**: ユーザーは固有のIDとメールアドレスによって識別されます
- **ユーザーエイリアス**: ユーザーは識別しやすくするため、アカウント名でエイリアスが設定されています
- **グループ分析**: セグメント分析を行うため、ユーザーは選択したプロジェクトおよび組織ごとにグループ分けされます
- **ページセクション**: イベントには、アプリケーションのどのセクションで生成されたかを示すスーパープロパティが含まれています:
  - `marketing` - マーケティングページおよび公開コンテンツからのイベント
  - `ダッシュボード` - メインアプリケーションのダッシュボードおよび認証済みエリアからのイベント
  - `api-docs` - APIドキュメントページからのイベント
- **ページビュー**: Phoenix LiveView を使用したページナビゲーションの自動追跡
- **カスタムイベント**: 機能の使用やユーザー操作に関するアプリケーション固有のイベント

### プライバシーに関する注意事項{#posthog-privacy}

- 認証済みユーザーの場合、PostHogはユーザーの一意のIDを識別子として使用し、メールアドレスを含めます
- 匿名ユーザーの場合、PostHogはデータをローカルに保存しないよう、メモリのみの永続化を使用します
- すべての分析はユーザーのプライバシーを尊重し、データ保護のベストプラクティスに従っています
- PostHogのデータは、PostHogのプライバシーポリシーおよびお客様の設定に従って処理されます

## Elixir メトリクス{#elixir-metrics}

デフォルトでは、Elixirランタイム、BEAM、Elixir、および使用しているライブラリの一部に関するメトリクスが含まれます。以下は、表示されるメトリクスの例です：

- [アプリケーション](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

利用可能な指標やその使用方法については、これらのページを確認することをお勧めします。

## メトリクスの実行{#runs-metrics}

Tuist Runs に関連する一連のメトリクス。

### `tuist_runs_total` (カウンター){#tuist_runs_total-counter}

Tuist Runsの総数。

#### タグ{#tuist-runs-total-tags}

| Tag     | 説明                                          |
| ------- | ------------------------------------------- |
| `名前`    | 実行された`のtuist` コマンドの名前。例：`build` 、`test` など。 |
| `is_ci` | 実行者がCI環境か開発者のマシンかを示すブール値。                   |
| `ステータス` | `0` （`が成功した場合）`,`1` （`が失敗した場合）`.            |

### `tuist_runs_duration_milliseconds` (ヒストグラム){#tuist_runs_duration_milliseconds-histogram}

各tuistの実行にかかる合計時間（ミリ秒単位）。

#### タグ{#tuist-runs-duration-miliseconds-tags}

| Tag     | 説明                                          |
| ------- | ------------------------------------------- |
| `名前`    | 実行された`のtuist` コマンドの名前。例：`build` 、`test` など。 |
| `is_ci` | 実行者がCI環境か開発者のマシンかを示すブール値。                   |
| `ステータス` | `0` （`が成功した場合）`,`1` （`が失敗した場合）`.            |

## キャッシュメトリクス{#cache-metrics}

Tuist Cache に関連する一連のメトリクス。

### `tuist_cache_events_total` (カウンター){#tuist_cache_events_total-counter}

バイナリキャッシュイベントの総数。

#### タグ{#tuist-cache-events-total-tags}

| Tag          | 説明                                                        |
| ------------ | --------------------------------------------------------- |
| `event_type` | `（local_hit）、` 、`（remote_hit）、` 、または`（miss）、` のいずれかになります。 |

### `tuist_cache_uploads_total` (カウンター){#tuist_cache_uploads_total-counter}

バイナリキャッシュへのアップロード回数。

### `tuist_cache_uploaded_bytes` (sum){#tuist_cache_uploaded_bytes-sum}

バイナリキャッシュにアップロードされたバイト数。

### `tuist_cache_downloads_total` (カウンター){#tuist_cache_downloads_total-counter}

バイナリキャッシュへのダウンロード数。

### `tuist_cache_downloaded_bytes` (sum){#tuist_cache_downloaded_bytes-sum}

バイナリキャッシュからダウンロードされたバイト数。

---

## プレビューの指標{#previews-metrics}

プレビュー機能に関連する一連の指標。

### `tuist_previews_uploads_total` (合計){#tuist_previews_uploads_total-counter}

アップロードされたプレビューの総数。

### `tuist_previews_downloads_total` (合計){#tuist_previews_downloads_total-counter}

ダウンロードされたプレビューの総数。

---

## ストレージメトリクス{#storage-metrics}

リモートストレージ（例：S3）におけるアーティファクトの保存に関連する一連の指標。

::: チップ
<!-- -->
これらの指標は、ストレージ操作のパフォーマンスを把握し、潜在的なボトルネックを特定するのに役立ちます。
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (ヒストグラム){#tuist_storage_get_object_size_size_bytes-histogram}

リモートストレージから取得したオブジェクトのサイズ（バイト単位）。

#### タグ{#tuist-storage-get-object-size-size-bytes-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |


### `tuist_storage_get_object_size_duration_miliseconds` (ヒストグラム){#tuist_storage_get_object_size_duration_miliseconds-histogram}

リモートストレージからオブジェクトサイズを取得するのにかかった時間（ミリ秒単位）。

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

### `tuist_storage_delete_all_objects_duration_milliseconds` (ヒストグラム){#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

リモートストレージからすべてのオブジェクトを削除するのにかかる時間（ミリ秒単位）。

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


### `tuist_storage_multipart_start_upload_duration_milliseconds` (ヒストグラム){#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

リモートストレージへのアップロードを開始するまでの時間（ミリ秒単位）。

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


### `tuist_storage_get_object_as_string_duration_milliseconds` (ヒストグラム){#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

リモートストレージからオブジェクトを文字列として取得するのにかかる時間（ミリ秒単位）。

#### タグ{#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_get_object_as_string_count` (count){#tuist_storage_get_object_as_string_count-count}

リモートストレージから文字列としてオブジェクトが取得された回数。

#### タグ{#tuist-storage-get-object-as-string-count-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |


### `tuist_storage_check_object_existence_duration_milliseconds` (ヒストグラム){#tuist_storage_check_object_existence_duration_milliseconds-histogram}

リモートストレージ内のオブジェクトの存在を確認する処理にかかる時間（ミリ秒単位）。

#### タグ{#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_check_object_existence_count` (count){#tuist_storage_check_object_existence_count-count}

リモートストレージ内でオブジェクトの存在が確認された回数。

#### タグ{#tuist-storage-check-object-existence-count-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (ヒストグラム){#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

リモートストレージ内のオブジェクトに対して、ダウンロード用事前署名済みURLを生成するのにかかる時間（ミリ秒単位）。

#### タグ{#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |


### `tuist_storage_generate_download_presigned_url_count` (count){#tuist_storage_generate_download_presigned_url_count-count}

リモートストレージ内のオブジェクトに対して、ダウンロード用事前署名済みURLが生成された回数。

#### タグ{#tuist-storage-generate-download-presigned-url-count-tags}

| Tag         | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (ヒストグラム){#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

リモートストレージ内のオブジェクトに対するパートアップロード用事前署名済みURLを生成するのにかかる時間（ミリ秒単位）。

#### タグ{#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Tag           | 説明                            |
| ------------- | ----------------------------- |
| `オブジェクト・キー`   | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |
| `part_number` | アップロードされるオブジェクトの部品番号。         |
| `upload_id`   | マルチパートアップロードのアップロードID。        |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count){#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

リモートストレージ内のオブジェクトに対して、部分アップロードの事前署名済みURLが生成された回数。

#### タグ{#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Tag           | 説明                            |
| ------------- | ----------------------------- |
| `オブジェクト・キー`   | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |
| `part_number` | アップロードされるオブジェクトの部品番号。         |
| `upload_id`   | マルチパートアップロードのアップロードID。        |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (ヒストグラム){#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

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

## 認証指標{#authentication-metrics}

認証に関連する一連の指標。

### `tuist_authentication_token_refresh_error_total` (カウンター){#tuist_authentication_token_refresh_error_total-counter}

トークン更新エラーの総数。

#### タグ{#tuist-authentication-token-refresh-error-total-tags}

| Tag           | 説明                                                                |
| ------------- | ----------------------------------------------------------------- |
| `cli_version` | エラーが発生したTuist CLIのバージョン。                                          |
| `理由`          | `、invalid_token_type、` 、または`、invalid_token、` などのトークン更新エラーが発生する理由。 |

---

## プロジェクトの指標{#projects-metrics}

プロジェクトに関連する一連の指標。

### `tuist_projects_total` (last_value){#tuist_projects_total-last_value}

プロジェクトの総数。

---

## アカウント指標{#accounts-metrics}

アカウント（ユーザーおよび組織）に関連する一連の指標。

### `tuist_accounts_organizations_total` (last_value){#tuist_accounts_organizations_total-last_value}

組織の総数。

### `tuist_accounts_users_total` (last_value){#tuist_accounts_users_total-last_value}

ユーザー総数。


## データベースのメトリクス{#database-metrics}

データベース接続に関連する一連のメトリクス。

### `tuist_repo_pool_checkout_queue_length` (last_value){#tuist_repo_pool_checkout_queue_length-last_value}

データベース接続に割り当てられるのを待機している、キューに滞留しているデータベースクエリの数。

### `tuist_repo_pool_ready_conn_count` (last_value){#tuist_repo_pool_ready_conn_count-last_value}

データベースクエリに割り当て可能なデータベース接続の数。


### `tuist_repo_pool_db_connection_connected` (カウンター){#tuist_repo_pool_db_connection_connected-counter}

データベースへの接続が確立された数。

### `tuist_repo_pool_db_connection_disconnected` (カウンター){#tuist_repo_pool_db_connection_disconnected-counter}

データベースから切断された接続の数。

## HTTP メトリクス{#http-metrics}

TuistがHTTP経由で他のサービスとやり取りする際のメトリクス一式。

### `tuist_http_request_count` (カウンター){#tuist_http_request_count-last_value}

送信されるHTTPリクエストの数。

### `tuist_http_request_duration_nanosecond_sum` (sum){#tuist_http_request_duration_nanosecond_sum-last_value}

送信リクエストの合計所要時間（接続の割り当て待ち時間を含む）。

### `tuist_http_request_duration_nanosecond_bucket` (分布){#tuist_http_request_duration_nanosecond_bucket-distribution}
送信リクエストの所要時間の分布（接続への割り当て待ち時間を含む）。

### `tuist_http_queue_count` (カウンター){#tuist_http_queue_count-counter}

プールから取得されたリクエストの数。

### `tuist_http_queue_duration_nanoseconds_sum` (sum){#tuist_http_queue_duration_nanoseconds_sum-sum}

プールから接続を取得するのにかかる時間。

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum){#tuist_http_queue_idle_time_nanoseconds_sum-sum}

接続が取得されるのを待機している間のアイドル時間。

### `tuist_http_queue_duration_nanoseconds_bucket` (分布){#tuist_http_queue_duration_nanoseconds_bucket-distribution}

プールから接続を取得するのにかかる時間。

### `tuist_http_queue_idle_time_nanoseconds_bucket` (分布){#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

接続が取得されるのを待機している間のアイドル時間。

### `tuist_http_connection_count` (カウンター){#tuist_http_connection_count-counter}

確立された接続の数。

### `tuist_http_connection_duration_nanoseconds_sum` (sum){#tuist_http_connection_duration_nanoseconds_sum-sum}

ホストへの接続を確立するのにかかる時間。

### `tuist_http_connection_duration_nanoseconds_bucket` (分布){#tuist_http_connection_duration_nanoseconds_bucket-distribution}

ホストへの接続確立にかかる時間の分布。

### `tuist_http_send_count` (カウンター){#tuist_http_send_count-counter}

プールから割り当てられた接続に対して送信されたリクエストの数。

### `tuist_http_send_duration_nanoseconds_sum` (sum){#tuist_http_send_duration_nanoseconds_sum-sum}

プールから接続が割り当てられた後、リクエストが完了するまでの時間。

### `tuist_http_send_duration_nanoseconds_bucket` (分布){#tuist_http_send_duration_nanoseconds_bucket-distribution}

プールから接続が割り当てられた後、リクエストが完了するまでの所要時間の分布。

### `tuist_http_receive_count` (カウンター){#tuist_http_receive_count-counter}

送信したリクエストに対して受け取った応答の数。

### `tuist_http_receive_duration_nanoseconds_sum` (sum){#tuist_http_receive_duration_nanoseconds_sum-sum}

回答の受信に要した時間。

### `tuist_http_receive_duration_nanoseconds_bucket` (分布){#tuist_http_receive_duration_nanoseconds_bucket-distribution}

応答の受信に要した時間の分布。

### `tuist_http_queue_available_connections` (last_value){#tuist_http_queue_available_connections-last_value}

キュー内で利用可能な接続数。

### `tuist_http_queue_in_use_connections` (last_value){#tuist_http_queue_in_use_connections-last_value}

使用中のキュー接続の数。
