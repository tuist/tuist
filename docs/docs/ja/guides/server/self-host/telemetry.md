---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# テレメトリー{#telemetry}

Prometheus](https://prometheus.io/)と[Grafana](https://grafana.com/)のような可視化ツールを使用して、Tuistサーバーによって収集されたメトリクスを取り込み、ニーズに合わせたカスタムダッシュボードを作成することができます。Prometheusのメトリクスは、ポート9091の`/metrics`
エンドポイント経由で提供されます。Prometheusの[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)は10_000秒未満に設定する必要があります（デフォルトの15秒を維持することをお勧めします）。

## ポストホッグ分析{#posthog-analytics}

Tuistは[PostHog](https://posthog.com/)と統合し、ユーザー行動分析およびイベントトラッキングを行います。これにより、ユーザーがTuistサーバーとどのようにやりとりしているかを理解し、機能の使用状況を追跡し、マーケティングサイト、ダッシュボード、APIドキュメント全体のユーザー行動について洞察を得ることができます。

### 構成{#posthog-configuration}

PostHogの統合はオプションで、適切な環境変数を設定することで有効にすることができます。設定すると、Tuistは自動的にユーザーイベント、ページビュー、ユーザージャーニーを追跡します。

| 環境変数                    | 説明                       | 必須  | デフォルト | 例                                                 |
| ----------------------- | ------------------------ | --- | ----- | ------------------------------------------------- |
| `tuist_posthog_api_key` | PostHogプロジェクトのAPIキー      | いいえ |       | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `tuist_posthog_url`     | PostHog API のエンドポイント URL | いいえ |       | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
Analytics は、`TUIST_POSTHOG_API_KEY` と`TUIST_POSTHOG_URL`
の両方が設定されている場合にのみ有効になります。どちらかの変数がない場合、アナリティクス・イベントは送信されません。
<!-- -->
:::

### 特徴{#posthog-features}

PostHogを有効にすると、Tuistは自動的に追跡する：

- **ユーザー識別** ：ユーザーは固有のIDとメールアドレスによって識別される
- **ユーザーエイリアス** ：ユーザーを識別しやすくするために、アカウント名でエイリアスを作成します。
- **グループ分析** ：ユーザーは、選択したプロジェクトと組織でグループ化され、セグメント化された分析が可能になります。
- **ページセクション** ：イベントには、アプリケーションのどのセクションがそれらを生成したかを示すスーパー・プロパティが含まれます：
  - `marketing` - マーケティングページや公開コンテンツからのイベント
  - `dashboard` - メインアプリケーションのダッシュボードと認証されたエリアからのイベント
  - `api-docs` - API ドキュメントページのイベント
- **ページビュー** ：Phoenix LiveViewを使ったページナビゲーションの自動トラッキング
- **カスタムイベント** ：機能使用とユーザーインタラクションのためのアプリケーション固有のイベント

### プライバシーへの配慮{#posthog-privacy}

- 認証されたユーザーの場合、PostHogはそのユーザー固有のIDを識別名として使用し、そのEメールアドレスを含みます。
- 匿名ユーザーの場合、PostHogはデータをローカルに保存しないように、メモリのみの永続性を使用します。
- すべてのアナリティクスは、ユーザーのプライバシーを尊重し、データ保護のベストプラクティスに従います。
- PostHogのデータは、PostHogのプライバシーポリシーおよびお客様の設定に従って処理されます。

## エリクサーの測定基準{#elixir-metrics}

デフォルトでは、Elixirランタイム、BEAM、Elixir、いくつかのライブラリのメトリクスが含まれています。以下は表示されるメトリクスの一部です：

- [アプリケーション]{1｝
- [ビーム](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)。
- [フェニックス](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- フェニックス・ライブビュー](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
  [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [エクト](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [オーバン](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)。

どのメトリクスが利用可能で、どのように使用するかを知るには、これらのページをチェックすることをお勧めします。

## ラン・メトリクス{#runs-metrics}

Tuist Runに関連するメトリクスのセット。

### `tuist_runs_total` (カウンター){#tuist_runs_total-counter}

トゥイスト・ランの総数。

#### タグ{#tuist-runs-total-tags}

| タグ      | 説明                                       |
| ------- | ---------------------------------------- |
| `名称`    | `build` 、`test` など、実行された`tuist` コマンドの名前。 |
| `is_ci` | 実行者がCIか開発者マシンかを示すブール値。                   |
| `ステータス` | `0`成功の場合`` ,`1`失敗の場合`` .                 |

### `tuist_runs_duration_milliseconds` (ヒストグラム){#tuist_runs_duration_milliseconds-histogram}

各Tuistの実行時間の合計（ミリ秒単位）。

#### タグ{#tuist-runs-duration-miliseconds-tags}

| タグ      | 説明                                       |
| ------- | ---------------------------------------- |
| `名称`    | `build` 、`test` など、実行された`tuist` コマンドの名前。 |
| `is_ci` | 実行者がCIか開発者マシンかを示すブール値。                   |
| `ステータス` | `0`成功の場合`` ,`1`失敗の場合`` .                 |

## キャッシュ・メトリクス{#cache-metrics}

Tuist Cacheに関連するメトリクスのセット。

### `tuist_cache_events_total` (カウンター){#tuist_cache_events_total-counter}

バイナリー・キャッシュ・イベントの総数。

#### タグ{#tuist-cache-events-total-tags}

| タグ        | 説明                                        |
| --------- | ----------------------------------------- |
| `イベントタイプ` | `local_hit`,`remote_hit`,`miss` のいずれかとなる。 |

### `tuist_cache_uploads_total` (カウンター){#tuist_cache_uploads_total-counter}

バイナリーキャッシュへのアップロード数。

### `tuist_cache_uploaded_bytes` (sum){#tuist_cache_uploaded_bytes-sum}

バイナリキャッシュにアップロードされたバイト数。

### `tuist_cache_downloads_total` (カウンター){#tuist_cache_downloads_total-counter}

バイナリーキャッシュへのダウンロード数。

### `tuist_cache_downloaded_bytes` (sum){#tuist_cache_downloaded_bytes-sum}

バイナリキャッシュからダウンロードされたバイト数。

---

## プレビュー指標{#previews-metrics}

プレビュー機能に関連するメトリクスのセット。

### `tuist_previews_uploads_total` (sum){#tuist_previews_uploads_total-counter}

アップロードされたプレビューの総数。

### `tuist_previews_downloads_total` (sum){#tuist_previews_downloads_total-counter}

ダウンロードされたプレビューの総数。

---

## ストレージ・メトリクス{#storage-metrics}

リモート・ストレージ（s3など）への成果物の保存に関するメトリクスのセット。

::: チップ
<!-- -->
これらのメトリクスは、ストレージ操作のパフォーマンスを理解し、潜在的なボトルネックを特定するのに有用である。
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (ヒストグラム){#tuist_storage_get_object_size_size_bytes-histogram}

リモート・ストレージから取得したオブジェクトのサイズ（バイト）。

#### タグ{#tuist-storage-get-object-size-size-bytes-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |


### `tuist_storage_get_object_size_duration_miliseconds` (ヒストグラム){#tuist_storage_get_object_size_duration_miliseconds-histogram}

リモート・ストレージからオブジェクト・サイズをフェッチする時間（ミリ秒）。

#### タグ{#tuist-storage-get-object-size-duration-miliseconds-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |


### `tuist_storage_get_object_size_count` (counter){#tuist_storage_get_object_size_count-counter}

オブジェクト・サイズがリモート・ストレージからフェッチされた回数。

#### タグ{#tuist-storage-get-object-size-count-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_delete_all_objects_duration_milliseconds` (ヒストグラム){#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

リモート・ストレージからすべてのオブジェクトを削除する時間（ミリ秒）。

#### タグ{#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| タグ            | 説明                       |
| ------------- | ------------------------ |
| `プロジェクト・スラッグ` | オブジェクトが削除されるプロジェクトのスラッグ。 |


### `tuist_storage_delete_all_objects_count` (counter){#tuist_storage_delete_all_objects_count-counter}

すべてのプロジェクト・オブジェクトがリモート・ストレージから削除された回数。

#### タグ{#tuist-storage-delete-all-objects-count-tags}

| タグ            | 説明                       |
| ------------- | ------------------------ |
| `プロジェクト・スラッグ` | オブジェクトが削除されるプロジェクトのスラッグ。 |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (ヒストグラム){#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

リモート・ストレージへのアップロードを開始する時間（ミリ秒）。

#### タグ{#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_multipart_start_upload_duration_count` (counter){#tuist_storage_multipart_start_upload_duration_count-counter}

リモートストレージへのアップロードが開始された回数。

#### タグ{#tuist-storage-multipart-start-upload-duration-count-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |


### `tuist_storage_get_object_as_string_duration_milliseconds` (ヒストグラム){#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

リモートストレージから文字列としてオブジェクトをフェッチする時間（ミリ秒）。

#### タグ{#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_get_object_as_string_count` (count){#tuist_storage_get_object_as_string_count-count}

オブジェクトがリモートストレージから文字列としてフェッチされた回数。

#### タグ{#tuist-storage-get-object-as-string-count-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |


### `tuist_storage_check_object_existence_duration_milliseconds` (ヒストグラム){#tuist_storage_check_object_existence_duration_milliseconds-histogram}

リモート・ストレージ内のオブジェクトの存在をチェックする時間（ミリ秒）。

#### タグ{#tuist-storage-check-object-existence-duration-milliseconds-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_check_object_existence_count` (count){#tuist_storage_check_object_existence_count-count}

リモートストレージでオブジェクトの存在を確認した回数。

#### タグ{#tuist-storage-check-object-existence-count-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (ヒストグラム){#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

リモート・ストレージ内のオブジェクトのダウンロード指定URLを生成する時間（ミリ秒）。

#### タグ{#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |


### `tuist_storage_generate_download_presigned_url_count` (count){#tuist_storage_generate_download_presigned_url_count-count}

リモート・ストレージ内のオブジェクトに対してダウンロード用URLが生成された回数。

#### タグ{#tuist-storage-generate-download-presigned-url-count-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (ヒストグラム){#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

リモート・ストレージ内のオブジェクトの部品アップロード指定URLを生成する時間（ミリ秒）。

#### タグ{#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |
| `パート番号`     | アップロードされるオブジェクトの品番。           |
| `アップロード`    | マルチパートアップロードのアップロードID。        |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count){#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

リモート・ストレージ内のオブジェクトに対して、部品アップロード指定URLが生成された回数。

#### タグ{#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |
| `パート番号`     | アップロードされるオブジェクトの品番。           |
| `アップロード`    | マルチパートアップロードのアップロードID。        |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (ヒストグラム){#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

リモートストレージへのアップロード完了までの時間（ミリ秒）。

#### タグ{#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |
| `アップロード`    | マルチパートアップロードのアップロードID。        |


### `tuist_storage_multipart_complete_upload_count` (count){#tuist_storage_multipart_complete_upload_count-count}

リモート・ストレージへのアップロードが完了した合計回数。

#### タグ{#tuist-storage-multipart-complete-upload-count-tags}

| タグ          | 説明                            |
| ----------- | ----------------------------- |
| `オブジェクト・キー` | リモート・ストレージ内のオブジェクトのルックアップ・キー。 |
| `アップロード`    | マルチパートアップロードのアップロードID。        |

---

## 認証メトリクス{#authentication-metrics}

認証に関連する一連のメトリクス。

### `tuist_authentication_token_refresh_error_total` (カウンタ){#tuist_authentication_token_refresh_error_total-counter}

トークン・リフレッシュ・エラーの総数。

#### タグ{#tuist-authentication-token-refresh-error-total-tags}

| タグ        | 説明                                                              |
| --------- | --------------------------------------------------------------- |
| `クリバージョン` | エラーが発生したTuist CLIのバージョン。                                        |
| `理由`      | `invalid_token_type` または`invalid_token` のようなトークン・リフレッシュ・エラーの理由。 |

---

## プロジェクト指標{#projects-metrics}

プロジェクトに関連するメトリクスのセット。

### `tuist_projects_total` (last_value){#tuist_projects_total-last_value}

プロジェクトの総数。

---

## 勘定科目{#accounts-metrics}

アカウント（ユーザーと組織）に関連するメトリクスのセット。

### `tuist_accounts_organizations_total` (last_value){#tuist_accounts_organizations_total-last_value}

組織の総数。

### `tuist_accounts_users_total` (last_value){#tuist_accounts_users_total-last_value}

ユーザーの総数。


## データベース・メトリクス{#database-metrics}

データベース接続に関連するメトリクスのセット。

### `tuist_repo_pool_checkout_queue_length` (last_value){#tuist_repo_pool_checkout_queue_length-last_value}

データベース接続に割り当てられるのを待っているデータベースクエリの数。

### `tuist_repo_pool_ready_conn_count` (last_value){#tuist_repo_pool_ready_conn_count-last_value}

データベースクエリに割り当て可能なデータベース接続の数。


### `tuist_repo_pool_db_connection_connected` (counter){#tuist_repo_pool_db_connection_connected-counter}

データベースへの接続数。

### `tuist_repo_pool_db_connection_disconnected` (counter){#tuist_repo_pool_db_connection_disconnected-counter}

データベースから切断された接続の数。

## HTTPメトリクス{#http-metrics}

TuistのHTTP経由での他のサービスとの相互作用に関連するメトリクスのセット。

### `tuist_http_request_count` (counter){#tuist_http_request_count-last_value}

発信HTTPリクエスト数。

### `tuist_http_request_duration_nanosecond_sum` (sum){#tuist_http_request_duration_nanosecond_sum-last_value}

発信リクエストの継続時間(コネクションに割り当てられるまでの待ち時間を 含む)の合計。

### `tuist_http_request_duration_nanosecond_bucket` (配布){#tuist_http_request_duration_nanosecond_bucket-distribution}
発信リクエストの持続時間の分布(コネクションに割り当てられるまでの待ち時間を含む)。

### `tuist_http_queue_count` (counter){#tuist_http_queue_count-counter}

プールから取得されたリクエストの数。

### `tuist_http_queue_duration_nanoseconds_sum` (sum){#tuist_http_queue_duration_nanoseconds_sum-sum}

プールから接続を取得するのにかかる時間。

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum){#tuist_http_queue_idle_time_nanoseconds_sum-sum}

コネクションが取得待ちのアイドル状態であった時間。

### `tuist_http_queue_duration_nanoseconds_bucket` (ディストリビューション){#tuist_http_queue_duration_nanoseconds_bucket-distribution}

プールから接続を取得するのにかかる時間。

### `tuist_http_queue_idle_time_nanoseconds_bucket` (ディストリビューション){#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

コネクションが取得待ちのアイドル状態であった時間。

### `tuist_http_connection_count` (counter){#tuist_http_connection_count-counter}

確立された接続の数。

### `tuist_http_connection_duration_nanoseconds_sum` (sum){#tuist_http_connection_duration_nanoseconds_sum-sum}

ホストとの接続を確立するのにかかる時間。

### `tuist_http_connection_duration_nanoseconds_bucket` (配布){#tuist_http_connection_duration_nanoseconds_bucket-distribution}

ホストに対して接続を確立するのにかかる時間の分布。

### `tuist_http_send_count` (counter){#tuist_http_send_count-counter}

プールからコネクションに割り当てられた後、送信されたリクエストの数。

### `tuist_http_send_duration_nanoseconds_sum` (sum){#tuist_http_send_duration_nanoseconds_sum-sum}

プールからのコネクションに割り当てられたリクエストが完了するまでの時間。

### `tuist_http_send_duration_nanoseconds_bucket` (配布){#tuist_http_send_duration_nanoseconds_bucket-distribution}

プールからのコネクションに割り当てられたリクエストが完了するまでの時間の分布。

### `tuist_http_receive_count` (counter){#tuist_http_receive_count-counter}

送信したリクエストから受け取った応答の数。

### `tuist_http_receive_duration_nanoseconds_sum` (sum){#tuist_http_receive_duration_nanoseconds_sum-sum}

回答の受信に費やされた時間。

### `tuist_http_receive_duration_nanoseconds_bucket` (配布){#tuist_http_receive_duration_nanoseconds_bucket-distribution}

回答の受信に費やされた時間の分布。

### `tuist_http_queue_available_connections` (last_value){#tuist_http_queue_available_connections-last_value}

キューで利用可能なコネクション数。

### `tuist_http_queue_in_use_connections` (last_value){#tuist_http_queue_in_use_connections-last_value}

使用中のキュー接続数。
