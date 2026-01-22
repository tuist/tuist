---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# 遙測{#telemetry}

您可透過 [Prometheus](https://prometheus.io/) 及 [Grafana](https://grafana.com/)
等視覺化工具匯入 Tuist 伺服器收集的指標，建立符合需求的自訂儀表板。 Prometheus 指標透過`/metrics` 端點於 9091
埠提供服務。Prometheus 的
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
應設定為低於 10_000 秒（建議維持預設值 15 秒）。

## PostHog 分析{#posthog-analytics}

Tuist 整合 [PostHog](https://posthog.com/) 進行使用者行為分析與事件追蹤。此功能可協助您理解使用者與 Tuist
伺服器的互動模式、追蹤功能使用狀況，並深入掌握行銷網站、儀表板及 API 文件中的使用者行為。

### 設定{#posthog-configuration}

PostHog 整合為可選功能，可透過設定相應環境變數啟用。配置完成後，Tuist 將自動追蹤使用者事件、頁面瀏覽次數及使用者旅程。

| 環境變數                    | 說明                   | 必填  | 預設  | 範例                                                |
| ----------------------- | -------------------- | --- | --- | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | 您的 PostHog 專案 API 金鑰 | 不   |     | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | PostHog API 端點網址     | 不   |     | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
分析功能僅在同時配置以下兩項時啟用：`TUIST_POSTHOG_API_KEY` 及`TUIST_POSTHOG_URL`
若任一變數缺失，將不會發送分析事件。
<!-- -->
:::

### 功能{#posthog-features}

啟用 PostHog 時，Tuist 會自動追蹤：

- **使用者識別碼** ：使用者透過其唯一識別碼與電子郵件地址進行識別
- **使用者別名設定**: 使用者將以帳號名稱作為別名，以便更容易辨識
- **群組分析**: 用戶將依據其選定的專案與組織進行分組，以實現分段分析
- **頁面區段**: Events 包含指示應用程式哪個區段產生事件的超級屬性：
  - `行銷` - 來自行銷頁面與公開內容的活動
  - `儀表板` - 來自主應用程式儀表板及驗證區域的事件
  - `api-docs` - 來自 API 文件頁面的事件
- **頁面瀏覽量**: 透過 Phoenix LiveView 自動追蹤頁面導覽
- **自訂事件**: 功能使用與使用者互動的應用程式專屬事件

### 隱私考量{#posthog-privacy}

- 對於已驗證的使用者，PostHog 會使用使用者唯一識別碼作為區別標識，並包含其電子郵件地址
- 對於匿名使用者，PostHog採用純記憶體持久化機制，避免在本地儲存資料
- 所有分析工具均尊重用戶隱私，並遵循資料保護最佳實踐
- PostHog 數據將依據 PostHog 隱私權政策及您的設定進行處理

## Elixir 指標{#elixir-metrics}

預設情況下，我們會包含 Elixir 執行階段、BEAM、Elixir 以及部分使用函式庫的計量數據。以下是您可能看到的計量項目：

- [應用程式](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [鳳凰](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [鳳凰直播](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

建議查閱相關頁面以了解可用指標及其使用方式。

## 運行指標{#runs-metrics}

一組與 Tuist Runs 相關的指標。

### `tuist_runs_total` (計數器){#tuist_runs_total-counter}

總計的 Tuist Runs 數。

#### 標籤{#tuist-runs-total-tags}

| 標籤      | 說明                                      |
| ------- | --------------------------------------- |
| `name`  | ` 執行過的`tuist 指令名稱，例如：`build` ` test` 等。 |
| `is_ci` | 一個布林值，用於標示執行者是 CI 還是開發者的機器。             |
| `狀態`    | `` 0 當`成功時為`` ,`1 當`失敗時為 ` .            |

### `tuist_runs_duration_milliseconds` (直方圖){#tuist_runs_duration_milliseconds-histogram}

每次 tuist 運行的總持續時間（單位：毫秒）。

#### 標籤{#tuist-runs-duration-miliseconds-tags}

| 標籤      | 說明                                      |
| ------- | --------------------------------------- |
| `name`  | ` 執行過的`tuist 指令名稱，例如：`build` ` test` 等。 |
| `is_ci` | 一個布林值，用於標示執行者是 CI 還是開發者的機器。             |
| `狀態`    | `` 0 當`成功時為`` ,`1 當`失敗時為 ` .            |

## 快取指標{#cache-metrics}

一組與 Tuist 快取相關的指標。

### `tuist_cache_events_total` (計數器){#tuist_cache_events_total-counter}

二進位快取事件的總數。

#### 標籤{#tuist-cache-events-total-tags}

| 標籤           | 說明                                           |
| ------------ | -------------------------------------------- |
| `event_type` | 可為以下任一形式：`local_hit`,`remote_hit`, 或`miss` 。 |

### `tuist_cache_uploads_total` (計數器){#tuist_cache_uploads_total-counter}

上傳至二進位快取的次數。

### `tuist_cache_uploaded_bytes` (sum){#tuist_cache_uploaded_bytes-sum}

上傳至二進位快取的位元組數量。

### `tuist_cache_downloads_total` (計數器){#tuist_cache_downloads_total-counter}

下載至二進位快取的次數。

### `tuist_cache_downloaded_bytes` (sum){#tuist_cache_downloaded_bytes-sum}

從二進位快取下載的位元組數。

---

## 預覽指標{#previews-metrics}

一組與預覽功能相關的指標。

### `tuist_previews_uploads_total` (sum){#tuist_previews_uploads_total-counter}

已上傳的預覽總數。

### `tuist_previews_downloads_total` (sum){#tuist_previews_downloads_total-counter}

已下載的預覽總數。

---

## 儲存指標{#storage-metrics}

一組與遠端儲存（例如 S3）中儲存工件相關的指標。

::: tip
<!-- -->
這些指標有助於理解儲存操作的效能表現，並識別潛在的瓶頸。
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (直方圖){#tuist_storage_get_object_size_size_bytes-histogram}

從遠端儲存空間擷取物件的大小（以位元組為單位）。

#### 標籤{#tuist-storage-get-object-size-size-bytes-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |


### `tuist_storage_get_object_size_duration_miliseconds` (直方圖){#tuist_storage_get_object_size_duration_miliseconds-histogram}

從遠端儲存空間擷取物件大小所需的時間（單位：毫秒）。

#### 標籤{#tuist-storage-get-object-size-duration-miliseconds-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |


### `tuist_storage_get_object_size_count` (計數器){#tuist_storage_get_object_size_count-counter}

從遠端儲存空間擷取物件大小的次數。

#### 標籤{#tuist-storage-get-object-size-count-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |

### `tuist_storage_delete_all_objects_duration_milliseconds` (直方圖){#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

從遠端儲存空間刪除所有物件所需的時間（單位：毫秒）。

#### 標籤{#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| 標籤             | 說明              |
| -------------- | --------------- |
| `project_slug` | 正在刪除物件之專案的專案別名。 |


### `tuist_storage_delete_all_objects_count` (計數器){#tuist_storage_delete_all_objects_count-counter}

從遠端儲存空間刪除所有專案物件的次數。

#### 標籤{#tuist-storage-delete-all-objects-count-tags}

| 標籤             | 說明              |
| -------------- | --------------- |
| `project_slug` | 正在刪除物件之專案的專案別名。 |


### `tuist_storage_multipart_start_upload_duration_milliseconds` （直方圖）{#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

啟動上傳至遠端儲存空間的持續時間（單位：毫秒）。

#### 標籤{#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |

### `tuist_storage_multipart_start_upload_duration_count` (計數器){#tuist_storage_multipart_start_upload_duration_count-counter}

上傳至遠端儲存空間的啟動次數。

#### 標籤{#tuist-storage-multipart-start-upload-duration-count-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |


### `tuist_storage_get_object_as_string_duration_milliseconds` (直方圖){#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

從遠端儲存空間以字串形式擷取物件所需的時間（單位：毫秒）。

#### 標籤{#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |

### `tuist_storage_get_object_as_string_count` (count){#tuist_storage_get_object_as_string_count-count}

從遠端儲存空間以字串形式擷取物件的次數。

#### 標籤{#tuist-storage-get-object-as-string-count-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |


### `tuist_storage_check_object_existence_duration_milliseconds` (直方圖){#tuist_storage_check_object_existence_duration_milliseconds-histogram}

檢查物件在遠端儲存空間中是否存在的持續時間（單位：毫秒）。

#### 標籤{#tuist-storage-check-object-existence-duration-milliseconds-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |

### `tuist_storage_check_object_existence_count` (計數){#tuist_storage_check_object_existence_count-count}

在遠端儲存空間中檢查物件存在次數的頻率。

#### 標籤{#tuist-storage-check-object-existence-count-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (直方圖){#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

為遠端儲存物件生成預簽署下載網址所需的時間（單位：毫秒）。

#### 標籤{#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |


### `tuist_storage_generate_download_presigned_url_count` (計數){#tuist_storage_generate_download_presigned_url_count-count}

遠端儲存空間中物件的預簽名下載網址生成次數。

#### 標籤{#tuist-storage-generate-download-presigned-url-count-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (直方圖){#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

生成遠端儲存物件之部分上傳預簽署網址所需時間（單位：毫秒）。

#### 標籤{#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |
| `零件編號`       | 上傳物件的零件編號。     |
| `上傳編號`       | 多部分上傳的傳輸標識碼。   |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (計數){#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

遠端儲存空間中物件的預簽名部分上傳網址生成次數。

#### 標籤{#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |
| `零件編號`       | 上傳物件的零件編號。     |
| `上傳編號`       | 多部分上傳的傳輸標識碼。   |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (直方圖){#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

完成上傳至遠端儲存空間所需的時間（單位：毫秒）。

#### 標籤{#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |
| `上傳編號`       | 多部分上傳的傳輸標識碼。   |


### `tuist_storage_multipart_complete_upload_count` (計數){#tuist_storage_multipart_complete_upload_count-count}

上傳至遠端儲存空間的總完成次數。

#### 標籤{#tuist-storage-multipart-complete-upload-count-tags}

| 標籤           | 說明             |
| ------------ | -------------- |
| `object_key` | 遠端儲存空間中物件的查詢鍵。 |
| `上傳編號`       | 多部分上傳的傳輸標識碼。   |

---

## 驗證指標{#authentication-metrics}

一組與驗證相關的指標。

### `tuist_authentication_token_refresh_error_total` (計數器){#tuist_authentication_token_refresh_error_total-counter}

總共發生多少次標記刷新錯誤。

#### 標籤{#tuist-authentication-token-refresh-error-total-tags}

| 標籤            | 說明                                                   |
| ------------- | ---------------------------------------------------- |
| `cli_version` | 發生錯誤的 Tuist CLI 版本。                                  |
| `原因`          | 令牌刷新錯誤的原因，例如：`invalid_token_type` 或`invalid_token` 。 |

---

## 專案指標{#projects-metrics}

一組與專案相關的指標。

### `tuist_projects_total` (last_value){#tuist_projects_total-last_value}

專案總數。

---

## 帳戶指標{#accounts-metrics}

一組與帳戶（使用者及組織）相關的指標。

### `tuist_accounts_organizations_total` (last_value){#tuist_accounts_organizations_total-last_value}

組織總數。

### `tuist_accounts_users_total` (last_value){#tuist_accounts_users_total-last_value}

總用戶數。


## 資料庫指標{#database-metrics}

一組與資料庫連線相關的指標。

### `tuist_repo_pool_checkout_queue_length` (last_value){#tuist_repo_pool_checkout_queue_length-last_value}

佇列中等待分配至資料庫連線的資料庫查詢數量。

### `tuist_repo_pool_ready_conn_count` (last_value){#tuist_repo_pool_ready_conn_count-last_value}

可分配至資料庫查詢的資料庫連線數量。


### `tuist_repo_pool_db_connection_connected` (計數器){#tuist_repo_pool_db_connection_connected-counter}

已建立至資料庫的連線數量。

### `tuist_repo_pool_db_connection_disconnected` (計數器){#tuist_repo_pool_db_connection_disconnected-counter}

已從資料庫斷開連接的連線數量。

## HTTP 指標{#http-metrics}

一組與 Tuist 透過 HTTP 與其他服務互動相關的指標。

### `tuist_http_request_count` (計數器){#tuist_http_request_count-last_value}

外發的 HTTP 請求數量。

### `tuist_http_request_duration_nanosecond_sum` (sum){#tuist_http_request_duration_nanosecond_sum-last_value}

外發請求的總耗時（包含等待分配至連線所耗費的時間）。

### `tuist_http_request_duration_nanosecond_bucket` (distribution){#tuist_http_request_duration_nanosecond_bucket-distribution}
外發請求的持續時間分佈（包含等待分配至連線所耗費的時間）。

### `tuist_http_queue_count` (計數器){#tuist_http_queue_count-counter}

從資源池中檢索到的請求數量。

### `tuist_http_queue_duration_nanoseconds_sum` (sum){#tuist_http_queue_duration_nanoseconds_sum-sum}

從連接池中檢索連接所需的時間。

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum){#tuist_http_queue_idle_time_nanoseconds_sum-sum}

連接處於閒置狀態等待被檢索的時間長度。

### `tuist_http_queue_duration_nanoseconds_bucket` (distribution){#tuist_http_queue_duration_nanoseconds_bucket-distribution}

從連接池中檢索連接所需的時間。

### `tuist_http_queue_idle_time_nanoseconds_bucket` (distribution){#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

連接處於閒置狀態等待被檢索的時間長度。

### `tuist_http_connection_count` (計數器){#tuist_http_connection_count-counter}

已建立的連接數量。

### `tuist_http_connection_duration_nanoseconds_sum` (sum){#tuist_http_connection_duration_nanoseconds_sum-sum}

建立與主機連線所需的時間。

### `tuist_http_connection_duration_nanoseconds_bucket` (distribution){#tuist_http_connection_duration_nanoseconds_bucket-distribution}

建立連線至主機所需時間的分佈情況。

### `tuist_http_send_count` (計數器){#tuist_http_send_count-counter}

從連接池分配後已發送的請求數量。

### `tuist_http_send_duration_nanoseconds_sum` (sum){#tuist_http_send_duration_nanoseconds_sum-sum}

從連接池分配連接後，請求完成所需的時間。

### `tuist_http_send_duration_nanoseconds_bucket` (distribution){#tuist_http_send_duration_nanoseconds_bucket-distribution}

請求從連接池分配至連接後，完成所需時間的分佈情況。

### `tuist_http_receive_count` (計數器){#tuist_http_receive_count-counter}

已從發送請求中接收到的回應數量。

### `tuist_http_receive_duration_nanoseconds_sum` (sum){#tuist_http_receive_duration_nanoseconds_sum-sum}

接收回應所耗費的時間。

### `tuist_http_receive_duration_nanoseconds_bucket` (distribution){#tuist_http_receive_duration_nanoseconds_bucket-distribution}

接收回應所耗費時間的分佈情況。

### `tuist_http_queue_available_connections` (last_value){#tuist_http_queue_available_connections-last_value}

佇列中可用的連接數。

### `tuist_http_queue_in_use_connections` (last_value){#tuist_http_queue_in_use_connections-last_value}

正在使用的佇列連接數。
