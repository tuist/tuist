---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# 遙測{#telemetry}

您可以使用 [Prometheus](https://prometheus.io/) 和可視化工具（如
[Grafana](https://grafana.com/) ）攝取 Tuist 伺服器收集的度量指標，以建立符合您需求的自訂儀表板。Prometheus
metrics 透過`/metrics` 端點提供，連接埠為 9091。Prometheus 的
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
應設為小於 10_000 秒（我們建議保持預設為 15 秒）。

## Post Hog 分析{#posthog-analytics}

Tuist 整合了 [PostHog](https://posthog.com/) 用於用戶行為分析和事件追蹤。這可讓您瞭解使用者如何與 Tuist
伺服器互動、追蹤功能使用情況，並深入瞭解行銷網站、儀表板和 API 文件中的使用者行為。

### 組態{#posthog-configuration}

PostHog 整合是可選的，可透過設定適當的環境變數來啟用。設定完成後，Tuist 會自動追蹤使用者事件、頁面檢視和使用者旅程。

| 環境變數                    | 說明                   | 必須  | 預設  | 範例                                                |
| ----------------------- | -------------------- | --- | --- | ------------------------------------------------- |
| `tuist_posthog_api_key` | 您的 PostHog 專案 API 金鑰 | 沒有  |     | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `tuist_posthog_url`     | PostHog API 端點 URL   | 沒有  |     | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
只有同時設定`TUIST_POSTHOG_API_KEY` 和`TUIST_POSTHOG_URL`
時，才會啟用分析功能。如果缺少其中一個變數，就不會傳送分析事件。
<!-- -->
:::

### 特點{#posthog-features}

啟用 PostHog 時，Tuist 會自動追蹤：

- **使用者識別** ：使用者以其獨特的 ID 和電子郵件地址進行識別
- **使用者別名** ：使用者以帳號名稱別名，以便識別
- **群組分析** ：使用者依其所選的專案和組織分組，以進行區隔分析
- **頁面區段** ：事件包含超級屬性，指出是應用程式的哪個部分產生這些事件：
  - `行銷` - 來自行銷頁面和公開內容的活動
  - `儀表板` - 主應用程式儀表板和認證區域的事件
  - `api-docs` - 來自 API 文件頁面的事件
- **頁面檢視** ：使用 Phoenix LiveView 自動追蹤頁面導航
- **自訂事件** ：特定於應用程式的事件，用於功能使用和使用者互動

### 隱私權考量{#posthog-privacy}

- 對於已認證的使用者，PostHog 使用使用者的唯一 ID 作為獨特的識別碼，並包含他們的電子郵件地址
- 對於匿名使用者，PostHog 使用僅記憶體的持久性，以避免在本機儲存資料。
- 所有分析都尊重使用者隱私權，並遵循資料保護最佳實務
- PostHog的資料將依照PostHog的隱私權政策和您的設定來處理。

## Elixir 度量{#elixir-metrics}

預設情況下，我們會包含 Elixir runtime、BEAM、Elixir 和一些我們使用的函式庫的度量指標。以下是您可以預期看到的一些指標：

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

我們建議您查看這些頁面，以瞭解哪些指標可用以及如何使用。

## 運行指標{#runs-metrics}

一套與 Tuist Runs 相關的指標。

### `tuist_runs_total` (計數器){#tuist_runs_total-counter}

Tuist Runs 的總數。

#### 標籤{#tuist-runs-total-tags}

| 標籤      | 說明                                  |
| ------- | ----------------------------------- |
| `姓名`    | 執行`tuist` 指令的名稱，例如`build`,`test` 等。 |
| `is_ci` | 一個布林值，表示執行者是 CI 或開發人員的機器。           |
| `狀態`    | `0` 在`成功的情況下`,`1` 在`失敗的情況下` 。       |

### `tuist_runs_duration_milliseconds` (直方圖){#tuist_runs_duration_milliseconds-histogram}

每個 tuist 執行的總時間，以毫秒為單位。

#### 標籤{#tuist-runs-duration-miliseconds-tags}

| 標籤      | 說明                                  |
| ------- | ----------------------------------- |
| `姓名`    | 執行`tuist` 指令的名稱，例如`build`,`test` 等。 |
| `is_ci` | 一個布林值，表示執行者是 CI 或開發人員的機器。           |
| `狀態`    | `0` 在`成功的情況下`,`1` 在`失敗的情況下` 。       |

## 快取記憶體指標{#cache-metrics}

一套與 Tuist 快取相關的指標。

### `tuist_cache_events_total` (計數器){#tuist_cache_events_total-counter}

二進位快取記憶體事件的總數。

#### 標籤{#tuist-cache-events-total-tags}

| 標籤     | 說明                                         |
| ------ | ------------------------------------------ |
| `事件類型` | 可以是`local_hit`,`remote_hit`, 或`miss` 其中之一。 |

### `tuist_cache_uploads_total` (計數器){#tuist_cache_uploads_total-counter}

上傳至二進位快取記憶體的次數。

### `tuist_cache_uploaded_bytes` (sum){#tuist_cache_uploaded_bytes-sum}

上傳至二進位快取記憶體的位元組數量。

### `tuist_cache_downloads_total` (計數器){#tuist_cache_downloads_total-counter}

下載到二進位快取記憶體的次數。

### `tuist_cache_downloaded_bytes` (sum){#tuist_cache_downloaded_bytes-sum}

從二進位快取記憶體下載的位元組數量。

---

## 預覽指標{#previews-metrics}

一套與預覽功能相關的度量指標。

### `tuist_previews_uploads_total` (sum){#tuist_previews_uploads_total-counter}

上傳的預覽總數。

### `tuist_previews_downloads_total` (sum){#tuist_previews_downloads_total-counter}

下載的預覽總數。

---

## 儲存指標{#storage-metrics}

一套與遠端儲存（例如 s3）中工件儲存相關的指標。

::: tip
<!-- -->
這些指標有助於瞭解儲存作業的效能，並找出潛在的瓶頸。
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (histogram){#tuist_storage_get_object_size_size_bytes-histogram}

從遠端儲存取得物件的大小 (位元組)。

#### 標籤{#tuist-storage-get-object-size-size-bytes-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |


### `tuist_storage_get_object_size_duration_miliseconds` (histogram){#tuist_storage_get_object_size_duration_miliseconds-histogram}

從遠端儲存取得物件大小的持續時間（以毫秒為單位）。

#### 標籤{#tuist-storage-get-object-size-duration-miliseconds-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |


### `tuist_storage_get_object_size_count` (counter){#tuist_storage_get_object_size_count-counter}

從遠端儲存取得物件大小的次數。

#### 標籤{#tuist-storage-get-object-size-count-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |

### `tuist_storage_delete_all_objects_duration_milliseconds` (直方圖){#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

從遠端儲存中刪除所有物件的持續時間（以毫秒為單位）。

#### 標籤{#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| 標籤     | 說明             |
| ------ | -------------- |
| `專案標題` | 要刪除物件的專案的專案標號。 |


### `tuist_storage_delete_all_objects_count` (counter){#tuist_storage_delete_all_objects_count-counter}

所有專案物件從遠端儲存中刪除的次數。

#### 標籤{#tuist-storage-delete-all-objects-count-tags}

| 標籤     | 說明             |
| ------ | -------------- |
| `專案標題` | 要刪除物件的專案的專案標號。 |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (直方圖){#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

開始上傳至遠端儲存的持續時間（以毫秒為單位）。

#### 標籤{#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |

### `tuist_storage_multipart_start_upload_duration_count` (counter){#tuist_storage_multipart_start_upload_duration_count-counter}

開始上傳至遠端儲存的次數。

#### 標籤{#tuist-storage-multipart-start-upload-duration-count-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histogram){#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

從遠端存放區擷取物件為字串的持續時間（以毫秒為單位）。

#### 標籤{#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |

### `tuist_storage_get_object_as_string_count` (count){#tuist_storage_get_object_as_string_count-count}

以字串形式從遠端儲存取得物件的次數。

#### 標籤{#tuist-storage-get-object-as-string-count-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |


### `tuist_storage_check_object_existence_duration_milliseconds` (直方圖){#tuist_storage_check_object_existence_duration_milliseconds-histogram}

檢查遠端儲存中是否存在物件的持續時間（以毫秒為單位）。

#### 標籤{#tuist-storage-check-object-existence-duration-milliseconds-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |

### `tuist_storage_check_object_existence_count` (count){#tuist_storage_check_object_existence_count-count}

在遠端儲存中檢查物件存在的次數。

#### 標籤{#tuist-storage-check-object-existence-count-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (直方圖){#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

為遠端儲存中的物件產生下載預先指定 URL 的持續時間（以毫秒為單位）。

#### 標籤{#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |


### `tuist_storage_generate_download_presigned_url_count` (count){#tuist_storage_generate_download_presigned_url_count-count}

為遠端儲存中的物件產生下載預先指定 URL 的次數。

#### 標籤{#tuist-storage-generate-download-presigned-url-count-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (直方圖){#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

為遠端儲存中的物件產生部分上傳預先指定 URL 的持續時間（以毫秒為單位）。

#### 標籤{#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |
| `零件編號`       | 上傳物件的零件編號。    |
| `upload_id`  | 多部分上傳的上傳 ID。  |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count){#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

為遠端儲存中的物件產生部分上傳預先指定 URL 的次數。

#### 標籤{#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |
| `零件編號`       | 上傳物件的零件編號。    |
| `upload_id`  | 多部分上傳的上傳 ID。  |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (直方圖){#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

完成上傳至遠端儲存的持續時間（以毫秒為單位）。

#### 標籤{#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |
| `upload_id`  | 多部分上傳的上傳 ID。  |


### `tuist_storage_multipart_complete_upload_count` (count){#tuist_storage_multipart_complete_upload_count-count}

完成上傳至遠端儲存的總次數。

#### 標籤{#tuist-storage-multipart-complete-upload-count-tags}

| 標籤           | 說明            |
| ------------ | ------------- |
| `object_key` | 遠端儲存中物件的查詢金鑰。 |
| `upload_id`  | 多部分上傳的上傳 ID。  |

---

## 驗證指標{#authentication-metrics}

一套與認證相關的指標。

### `tuist_authentication_token_refresh_error_total` (計數器){#tuist_authentication_token_refresh_error_total-counter}

令牌刷新錯誤的總數。

#### 標籤{#tuist-authentication-token-refresh-error-total-tags}

| 標籤            | 說明                                                  |
| ------------- | --------------------------------------------------- |
| `cli_version` | 遇到錯誤的 Tuist CLI 版本。                                 |
| `理由`          | 令牌刷新錯誤的原因，例如`invalid_token_type` 或`invalid_token` 。 |

---

## 專案指標{#projects-metrics}

一套與專案相關的衡量標準。

### `tuist_projects_total` (last_value){#tuist_projects_total-last_value}

專案總數。

---

## 帳戶指標{#accounts-metrics}

一套與帳戶（使用者和組織）相關的度量指標。

### `tuist_accounts_organizations_total` (last_value){#tuist_accounts_organizations_total-last_value}

組織總數。

### `tuist_accounts_users_total` (last_value){#tuist_accounts_users_total-last_value}

使用者總數。


## 資料庫指標{#database-metrics}

一組與資料庫連線相關的指標。

### `tuist_repo_pool_checkout_queue_length` (last_value){#tuist_repo_pool_checkout_queue_length-last_value}

在佇列中等待指派給資料庫連線的資料庫查詢數目。

### `tuist_repo_pool_ready_conn_count` (last_value){#tuist_repo_pool_ready_conn_count-last_value}

準備指派給資料庫查詢的資料庫連線數目。


### `tuist_repo_pool_db_connection_connected` (counter){#tuist_repo_pool_db_connection_connected-counter}

已建立的資料庫連線數。

### `tuist_repo_pool_db_connection_disconnected` (counter){#tuist_repo_pool_db_connection_disconnected-counter}

已從資料庫斷線的連線數目。

## HTTP 量測{#http-metrics}

一套與 Tuist 透過 HTTP 與其他服務互動相關的指標。

### `tuist_http_request_count` (counter){#tuist_http_request_count-last_value}

傳出 HTTP 請求的數目。

### `tuist_http_request_duration_nanosecond_sum` (sum){#tuist_http_request_duration_nanosecond_sum-last_value}

傳出請求的持續時間總和（包括等待指派給連線的時間）。

### `tuist_http_request_duration_nanosecond_bucket` (distribution){#tuist_http_request_duration_nanosecond_bucket-distribution}
傳出請求的持續時間分佈 (包括等待指派給連線的時間)。

### `tuist_http_queue_count` (counter){#tuist_http_queue_count-counter}

已從資料池中擷取的請求數目。

### `tuist_http_queue_duration_nanoseconds_sum` (sum){#tuist_http_queue_duration_nanoseconds_sum-sum}

從連線池擷取連線所需的時間。

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum){#tuist_http_queue_idle_time_nanoseconds_sum-sum}

連線等待擷取的閒置時間。

### `tuist_http_queue_duration_nanoseconds_bucket` (distribution){#tuist_http_queue_duration_nanoseconds_bucket-distribution}

從連線池擷取連線所需的時間。

### `tuist_http_queue_idle_time_nanoseconds_bucket` (distribution){#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

連線等待擷取的閒置時間。

### `tuist_http_connection_count` (counter){#tuist_http_connection_count-counter}

已建立的連線數目。

### `tuist_http_connection_duration_nanoseconds_sum` (sum){#tuist_http_connection_duration_nanoseconds_sum-sum}

與主機建立連線所需的時間。

### `tuist_http_connection_duration_nanoseconds_bucket` (distribution){#tuist_http_connection_duration_nanoseconds_bucket-distribution}

針對主機建立連線所需時間的分佈。

### `tuist_http_send_count` (counter){#tuist_http_send_count-counter}

分配給池中連線後，已傳送的要求數目。

### `tuist_http_send_duration_nanoseconds_sum` (sum){#tuist_http_send_duration_nanoseconds_sum-sum}

將要求指派給池中的連線後，要求完成所需的時間。

### `tuist_http_send_duration_nanoseconds_bucket` (distribution){#tuist_http_send_duration_nanoseconds_bucket-distribution}

將請求指派給池中的連線後，其完成所需時間的分佈。

### `tuist_http_receive_count` (counter){#tuist_http_receive_count-counter}

從已傳送的要求中收到的回應數目。

### `tuist_http_receive_duration_nanoseconds_sum` (sum){#tuist_http_receive_duration_nanoseconds_sum-sum}

接收回覆的時間。

### `tuist_http_receive_duration_nanoseconds_bucket` (distribution){#tuist_http_receive_duration_nanoseconds_bucket-distribution}

接收回覆的時間分佈。

### `tuist_http_queue_available_connections` (last_value){#tuist_http_queue_available_connections-last_value}

佇列中可用的連線數。

### `tuist_http_queue_in_use_connections` (last_value){#tuist_http_queue_in_use_connections-last_value}

使用中的佇列連線數。
