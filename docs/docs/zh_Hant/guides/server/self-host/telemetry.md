---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# 遙測{#telemetry}

您可以透過 [Prometheus](https://prometheus.io/) 匯入由 Tuist 伺服器收集的指標，並使用
[Grafana](https://grafana.com/) 等視覺化工具，建立符合您需求的自訂儀表板。 Prometheus 指標是透過`/metrics`
端點在 9091 埠提供服務。Prometheus 的
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
應設定為小於 10,000 秒（我們建議維持預設的 15 秒）。

## PostHog 分析{#posthog-analytics}

Tuist 整合了 [PostHog](https://posthog.com/) 進行使用者行為分析與事件追蹤。這讓您能夠了解使用者如何與您的 Tuist
伺服器互動、追蹤功能使用情況，並深入分析行銷網站、儀表板及 API 文件中的使用者行為。

### 設定{#posthog-configuration}

PostHog 整合為選用功能，可透過設定相應的環境變數啟用。設定完成後，Tuist 將自動追蹤使用者事件、頁面瀏覽次數及使用者旅程。

| 環境變數                    | 說明                   | 必填  | 預設  | 範例                                                |
| ----------------------- | -------------------- | --- | --- | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | 您的 PostHog 專案 API 金鑰 | 不   |     | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | PostHog API 端點網址     | 不   |     | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
僅當同時設定了`TUIST_POSTHOG_API_KEY` 以及`TUIST_POSTHOG_URL`
時，分析功能才會啟用。若任一變數缺失，將不會傳送任何分析事件。
<!-- -->
:::

### 功能{#posthog-features}

當啟用 PostHog 時，Tuist 會自動追蹤：

- **使用者識別**: 使用者透過其唯一 ID 和電子郵件地址進行識別
- **使用者別名**: 使用者會以其帳號名稱作為別名，以便於辨識
- **群組分析**: 系統會根據使用者所選的專案和組織將其分組，以便進行分段分析
- **頁面區段**: 事件包含超屬性，用以標示其由應用程式的哪個區段產生：
  - `marketing` - 來自行銷頁面與公開內容的活動
  - `儀表板` - 來自主應用程式儀表板及已驗證區域的事件
  - `api-docs` - API 文件頁面中的事件
- **頁面瀏覽量**: 使用 Phoenix LiveView 自動追蹤頁面導航
- **自訂事件**: 針對功能使用與使用者互動的應用程式專用事件

### 隱私考量{#posthog-privacy}

- 對於已驗證的使用者，PostHog 會使用使用者的唯一 ID 作為獨特識別碼，並包含其電子郵件地址
- 對於匿名使用者，PostHog 採用僅記憶體儲存機制，以避免在本地儲存資料
- 所有分析工具均尊重使用者隱私，並遵循資料保護的最佳實務
- PostHog 資料的處理方式將遵循 PostHog 的隱私權政策及您的設定

## Elixir 指標{#elixir-metrics}

預設情況下，我們會納入 Elixir 執行環境、BEAM、Elixir 以及我們所使用部分函式庫的指標。以下是您可能會看到的部分指標：

- [應用程式](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

我們建議您查閱這些頁面，以了解可用的指標及其使用方法。

## 執行指標{#runs-metrics}

一組與 Tuist Runs 相關的指標。

### `tuist_runs_total` (計數器){#tuist_runs_total-counter}

Tuist Runs 的總數。

#### 標籤{#tuist-runs-total-tags}

| 標籤      | 說明                                    |
| ------- | ------------------------------------- |
| `name`  | 已執行的`tuist` 指令名稱，例如`build` 、`test` 等。 |
| `is_ci` | 一個布林值，用以標示執行者是 CI 還是開發者的機器。           |
| `狀態`    | `0` 若`成功`,`1` 若`失敗`.                  |

### `tuist_runs_duration_milliseconds` (直方圖){#tuist_runs_duration_milliseconds-histogram}

每次 tuist 執行所耗費的總時間（單位：毫秒）。

#### 標籤{#tuist-runs-duration-miliseconds-tags}

| 標籤      | 說明                                    |
| ------- | ------------------------------------- |
| `name`  | 已執行的`tuist` 指令名稱，例如`build` 、`test` 等。 |
| `is_ci` | 一個布林值，用以標示執行者是 CI 還是開發者的機器。           |
| `狀態`    | `0` 若`成功`,`1` 若`失敗`.                  |

## 快取指標{#cache-metrics}

一組與 Tuist Cache 相關的指標。

### `tuist_cache_events_total` (計數器){#tuist_cache_events_total-counter}

二進位快取事件的總數。

#### 標籤{#tuist-cache-events-total-tags}

| 標籤           | 說明                                            |
| ------------ | --------------------------------------------- |
| `event_type` | 可為以下任一形式：`local_hit` 、`remote_hit` ，或`miss` 。 |

### `tuist_cache_uploads_total` (計數器){#tuist_cache_uploads_total-counter}

上傳至二進位快取的次數。

### `tuist_cache_uploaded_bytes` (sum){#tuist_cache_uploaded_bytes-sum}

上傳至二進位快取的位元組數。

### `tuist_cache_downloads_total` (計數器){#tuist_cache_downloads_total-counter}

二進位快取的下載次數。

### `tuist_cache_downloaded_bytes` (sum){#tuist_cache_downloaded_bytes-sum}

從二進位快取下載的位元組數。

---

## 預覽指標{#previews-metrics}

一組與預覽功能相關的指標。

### `tuist_previews_uploads_total` (總數){#tuist_previews_uploads_total-counter}

已上傳的預覽總數。

### `tuist_previews_downloads_total` (總計){#tuist_previews_downloads_total-counter}

已下載的預覽總數。

---

## 儲存指標{#storage-metrics}

一組與遠端儲存空間（例如 S3）中儲存體相關的指標。

::: tip
<!-- -->
這些指標有助於了解儲存操作的效能，並找出潛在的瓶頸。
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (直方圖){#tuist_storage_get_object_size_size_bytes-histogram}

從遠端儲存空間擷取之物件的大小（以位元組為單位）。

#### 標籤{#tuist-storage-get-object-size-size-bytes-tags}

| 標籤           | 說明              |
| ------------ | --------------- |
| `object_key` | 遠端儲存空間中該物件的查詢鍵。 |


### `tuist_storage_get_object_size_duration_miliseconds` (直方圖){#tuist_storage_get_object_size_duration_miliseconds-histogram}

從遠端儲存空間擷取物件大小所需的耗時（單位：毫秒）。

#### 標籤{#tuist-storage-get-object-size-duration-miliseconds-tags}

| 標籤           | 說明              |
| ------------ | --------------- |
| `object_key` | 遠端儲存空間中該物件的查詢鍵。 |


### `tuist_storage_get_object_size_count` (計數器){#tuist_storage_get_object_size_count-counter}

從遠端儲存空間擷取物件大小的次數。

#### 標籤{#tuist-storage-get-object-size-count-tags}

| 標籤           | 說明              |
| ------------ | --------------- |
| `object_key` | 遠端儲存空間中該物件的查詢鍵。 |

### `tuist_storage_delete_all_objects_duration_milliseconds` (直方圖){#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

從遠端儲存空間刪除所有物件所需的時間（單位：毫秒）。

#### 標籤{#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| 標籤             | 說明               |
| -------------- | ---------------- |
| `project_slug` | 正在刪除其物件之專案的專案代號。 |


### `tuist_storage_delete_all_objects_count` (計數器){#tuist_storage_delete_all_objects_count-counter}

從遠端儲存空間中刪除所有專案物件的次數。

#### 標籤{#tuist-storage-delete-all-objects-count-tags}

| 標籤             | 說明               |
| -------------- | ---------------- |
| `project_slug` | 正在刪除其物件之專案的專案代號。 |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (直方圖){#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

開始上傳至遠端儲存空間所需的時間（以毫秒為單位）。

#### 標籤{#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| 標籤           | 說明              |
| ------------ | --------------- |
| `object_key` | 遠端儲存空間中該物件的查詢鍵。 |

### `tuist_storage_multipart_start_upload_duration_count` (計數器){#tuist_storage_multipart_start_upload_duration_count-counter}

已嘗試上傳至遠端儲存空間的次數。

#### 標籤{#tuist-storage-multipart-start-upload-duration-count-tags}

| 標籤           | 說明              |
| ------------ | --------------- |
| `object_key` | 遠端儲存空間中該物件的查詢鍵。 |


### `tuist_storage_get_object_as_string_duration_milliseconds` (直方圖){#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

從遠端儲存空間擷取物件作為字串所需的耗時（單位：毫秒）。

#### 標籤{#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| 標籤           | 說明              |
| ------------ | --------------- |
| `object_key` | 遠端儲存空間中該物件的查詢鍵。 |

### `tuist_storage_get_object_as_string_count` (count){#tuist_storage_get_object_as_string_count-count}

從遠端儲存空間以字串形式取得該物件的次數。

#### 標籤{#tuist-storage-get-object-as-string-count-tags}

| 標籤           | 說明              |
| ------------ | --------------- |
| `object_key` | 遠端儲存空間中該物件的查詢鍵。 |


### `tuist_storage_check_object_existence_duration_milliseconds` (直方圖){#tuist_storage_check_object_existence_duration_milliseconds-histogram}

檢查遠端儲存空間中物件是否存在的耗時（單位：毫秒）。

#### 標籤{#tuist-storage-check-object-existence-duration-milliseconds-tags}

| 標籤           | 說明              |
| ------------ | --------------- |
| `object_key` | 遠端儲存空間中該物件的查詢鍵。 |

### `tuist_storage_check_object_existence_count` (count){#tuist_storage_check_object_existence_count-count}

在遠端儲存空間中檢查物件是否存在之次數。

#### 標籤{#tuist-storage-check-object-existence-count-tags}

| 標籤           | 說明              |
| ------------ | --------------- |
| `object_key` | 遠端儲存空間中該物件的查詢鍵。 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (直方圖){#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

為遠端儲存空間中的物件產生預簽署下載網址所需的時間（單位：毫秒）。

#### 標籤{#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| 標籤           | 說明              |
| ------------ | --------------- |
| `object_key` | 遠端儲存空間中該物件的查詢鍵。 |


### `tuist_storage_generate_download_presigned_url_count` (count){#tuist_storage_generate_download_presigned_url_count-count}

針對遠端儲存空間中的物件，已生成預簽署下載連結的次數。

#### 標籤{#tuist-storage-generate-download-presigned-url-count-tags}

| 標籤           | 說明              |
| ------------ | --------------- |
| `object_key` | 遠端儲存空間中該物件的查詢鍵。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (直方圖){#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

為遠端儲存空間中的物件產生部分上傳預簽名 URL 所耗費的時間（單位：毫秒）。

#### 標籤{#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| 標籤            | 說明              |
| ------------- | --------------- |
| `object_key`  | 遠端儲存空間中該物件的查詢鍵。 |
| `part_number` | 上傳物件的型號。        |
| `upload_id`   | 多部分上傳的上傳 ID。    |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count){#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

針對遠端儲存空間中的物件，已產生部分上傳預簽名 URL 的次數。

#### 標籤{#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| 標籤            | 說明              |
| ------------- | --------------- |
| `object_key`  | 遠端儲存空間中該物件的查詢鍵。 |
| `part_number` | 上傳物件的型號。        |
| `upload_id`   | 多部分上傳的上傳 ID。    |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (直方圖){#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

上傳至遠端儲存空間所需的時間（單位為毫秒）。

#### 標籤{#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| 標籤           | 說明              |
| ------------ | --------------- |
| `object_key` | 遠端儲存空間中該物件的查詢鍵。 |
| `upload_id`  | 多部分上傳的上傳 ID。    |


### `tuist_storage_multipart_complete_upload_count` (count){#tuist_storage_multipart_complete_upload_count-count}

上傳至遠端儲存空間的總次數。

#### 標籤{#tuist-storage-multipart-complete-upload-count-tags}

| 標籤           | 說明              |
| ------------ | --------------- |
| `object_key` | 遠端儲存空間中該物件的查詢鍵。 |
| `upload_id`  | 多部分上傳的上傳 ID。    |

---

## 驗證指標{#authentication-metrics}

一組與驗證相關的指標。

### `tuist_authentication_token_refresh_error_total` (計數器){#tuist_authentication_token_refresh_error_total-counter}

標記刷新錯誤的總數。

#### 標籤{#tuist-authentication-token-refresh-error-total-tags}

| 標籤            | 說明                                                    |
| ------------- | ----------------------------------------------------- |
| `cli_version` | 發生錯誤的 Tuist CLI 版本。                                   |
| `原因`          | 發生代幣刷新錯誤的原因，例如`invalid_token_type` 或`invalid_token` 。 |

---

## 專案指標{#projects-metrics}

一組與專案相關的指標。

### `tuist_projects_total` (last_value){#tuist_projects_total-last_value}

專案總數。

---

## 帳戶指標{#accounts-metrics}

一組與帳戶（使用者和組織）相關的指標。

### `tuist_accounts_organizations_total` (last_value){#tuist_accounts_organizations_total-last_value}

組織總數。

### `tuist_accounts_users_total` (last_value){#tuist_accounts_users_total-last_value}

使用者總數。


## 資料庫指標{#database-metrics}

一組與資料庫連線相關的指標。

### `tuist_repo_pool_checkout_queue_length` (last_value){#tuist_repo_pool_checkout_queue_length-last_value}

排隊等待分配至資料庫連線的資料庫查詢數量。

### `tuist_repo_pool_ready_conn_count` (last_value){#tuist_repo_pool_ready_conn_count-last_value}

可供分配給資料庫查詢的資料庫連線數量。


### `tuist_repo_pool_db_connection_connected` (計數器){#tuist_repo_pool_db_connection_connected-counter}

已建立至資料庫的連線數。

### `tuist_repo_pool_db_connection_disconnected` (計數器){#tuist_repo_pool_db_connection_disconnected-counter}

已從資料庫中斷開的連線數量。

## HTTP 指標{#http-metrics}

一組與 Tuist 透過 HTTP 與其他服務進行互動相關的指標。

### `tuist_http_request_count` (計數器){#tuist_http_request_count-last_value}

發出的 HTTP 請求數量。

### `tuist_http_request_duration_nanosecond_sum` (sum){#tuist_http_request_duration_nanosecond_sum-last_value}

外發請求的總耗時（包含等待分配連線所花費的時間）。

### `tuist_http_request_duration_nanosecond_bucket` (分佈){#tuist_http_request_duration_nanosecond_bucket-distribution}
外發請求的持續時間分佈（包含其等待被分配至連線所花費的時間）。

### `tuist_http_queue_count` (計數器){#tuist_http_queue_count-counter}

從池中擷取的請求數量。

### `tuist_http_queue_duration_nanoseconds_sum` (sum){#tuist_http_queue_duration_nanoseconds_sum-sum}

從連接池中擷取連接所需的時間。

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum){#tuist_http_queue_idle_time_nanoseconds_sum-sum}

連線處於閒置狀態並等待被取用的時間。

### `tuist_http_queue_duration_nanoseconds_bucket` (分佈){#tuist_http_queue_duration_nanoseconds_bucket-distribution}

從連接池中擷取連接所需的時間。

### `tuist_http_queue_idle_time_nanoseconds_bucket` (分佈){#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

連線處於閒置狀態並等待被取用的時間。

### `tuist_http_connection_count` (計數器){#tuist_http_connection_count-counter}

已建立的連線數量。

### `tuist_http_connection_duration_nanoseconds_sum` (sum){#tuist_http_connection_duration_nanoseconds_sum-sum}

建立與主機連線所需的時間。

### `tuist_http_connection_duration_nanoseconds_bucket` (分佈){#tuist_http_connection_duration_nanoseconds_bucket-distribution}

建立與主機連線所需時間的分布。

### `tuist_http_send_count` (計數器){#tuist_http_send_count-counter}

自連接池分配連接後，已發送的請求數量。

### `tuist_http_send_duration_nanoseconds_sum` (sum){#tuist_http_send_duration_nanoseconds_sum-sum}

請求從連接池分配到連接後，完成所需的時間。

### `tuist_http_send_duration_nanoseconds_bucket` (分佈){#tuist_http_send_duration_nanoseconds_bucket-distribution}

請求從連接池分配至連接後，完成所需時間的分布。

### `tuist_http_receive_count` (計數器){#tuist_http_receive_count-counter}

已發送請求所收到的回應數量。

### `tuist_http_receive_duration_nanoseconds_sum` (sum){#tuist_http_receive_duration_nanoseconds_sum-sum}

接收回應所花費的時間。

### `tuist_http_receive_duration_nanoseconds_bucket` (分佈){#tuist_http_receive_duration_nanoseconds_bucket-distribution}

接收回應所花費時間的分布。

### `tuist_http_queue_available_connections` (last_value){#tuist_http_queue_available_connections-last_value}

佇列中可用的連線數。

### `tuist_http_queue_in_use_connections` (last_value){#tuist_http_queue_in_use_connections-last_value}

目前正在使用的佇列連線數量。
