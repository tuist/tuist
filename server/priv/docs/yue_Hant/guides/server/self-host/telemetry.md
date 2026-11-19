---
{
  "title": "遙測",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "透過 Prometheus 指標、OpenTelemetry 追蹤記錄同日誌轉發，監察你嘅 Tuist 伺服器。"
}
---
# 遙測 {#telemetry}

Tuist 提供三個互補的可觀測性信號：**指標**（Prometheus）、**追蹤**（OpenTelemetry）和 **日誌**（Loki 相容）。三者皆為可選，且可獨立啟用。

## 分散式追蹤（OpenTelemetry）{#opentelemetry}

Tuist 支援 [OpenTelemetry](https://opentelemetry.io/) 進行分散式追蹤。啟用後，伺服器會為 HTTP 請求（Phoenix 和 Bandit）、資料庫查詢（Ecto）、傳出 HTTP 呼叫（Finch）以及 Broadway 訊息處理發出追蹤記錄。這些追蹤記錄讓你了解請求延遲、識別慢查詢，並跨服務追蹤請求。

### 設定 {#opentelemetry-configuration}

設定以下環境變數以啟用追蹤匯出：

| 環境變數 | 說明 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry Collector 的 gRPC 端點（例如 Grafana Alloy、Jaeger 或任何 OTLP 相容的收集器） | 否 | | `http://localhost:4317` |

若未設定此變數，追蹤功能將停用且不會產生額外開銷。

### 已插樁的函式庫 {#opentelemetry-instrumented-libraries}

啟用追蹤時，以下函式庫會自動進行插樁：

- **Bandit** – HTTP 伺服器連線跨度
- **Phoenix** – 請求生命週期跨度（控制器動作、LiveView）
- **Ecto** – 帶有查詢中繼資料的資料庫查詢跨度
- **Finch** – 傳出 HTTP 用戶端請求跨度
- **Broadway** – 訊息處理管線跨度

### 使用 Grafana Alloy 的範例設定 {#opentelemetry-alloy-example}

如果你使用 [Grafana Alloy](https://grafana.com/docs/alloy/latest/) 作為收集器，請將其設定為接收 OTLP 追蹤記錄，並轉發至你的追蹤後端（例如 Grafana Cloud Tempo）：

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

然後設定 `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` 指向 Alloy 執行個體，例如 `http://alloy:4317`。

## 日誌轉送（Loki）{#log-forwarding}

Tuist 可以將應用程式日誌轉送至 [Loki](https://grafana.com/oss/loki/) 相容的端點。這讓你可以將日誌與指標和追蹤記錄集中管理，獲得完整的可觀測性視圖。日誌透過 Loki HTTP push API（`/loki/api/v1/push`）推送，並包含 `app`、`env` 和 `level` 的標籤。

### 設定 {#log-forwarding-configuration}

| 環境變數 | 說明 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_LOKI_URL` | Loki 相容 push API 端點的基礎 URL | 否 | | `http://localhost:3100` |

若未設定此變數，日誌轉送功能將停用。

### 使用 Grafana Alloy 的範例設定 {#log-forwarding-alloy-example}

Grafana Alloy 可以使用其 [`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/) 元件作為本機日誌中繼：

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

然後設定 `TUIST_LOKI_URL=http://alloy:3100`。

如果 Loki 執行個體公開了 push API，你也可以直接將 `TUIST_LOKI_URL` 指向該執行個體。

## Prometheus 指標 {#prometheus-metrics}

你可以使用 [Prometheus](https://prometheus.io/) 和像 [Grafana](https://grafana.com/) 這樣的視覺化工具，匯入 Tuist 伺服器收集的指標，以建立符合你需求的自訂儀表板。Prometheus 指標透過連接埠 9091 上的 `/metrics` 端點提供。Prometheus 的 [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) 應設定為少於 10_000 秒（我們建議設為 30 秒，以在可觀測性與指標匯入成本之間取得平衡）。

## 真實用戶監控 {#real-user-monitoring}

Tuist 可以使用捆綁在所提供 JavaScript 中的 [Grafana Faro](https://grafana.com/oss/faro/) Web SDK，從行銷網站、文件和控制面板報告瀏覽器效能。它會捕捉核心網頁指標（包括最大內容繪製）、未捕獲的錯誤和頁面瀏覽量，並將它們發布到你運行的 [Faro 接收器](https://grafana.com/docs/alloy/latest/reference/components/faro/faro.receiver/) — 例如 Grafana Alloy 中的 `faro.receiver` 元件，它會將數據轉發至 Loki 和 Tempo。

### 設定 {#real-user-monitoring-configuration}

| 環境變數 | 說明 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_FARO_COLLECTOR_URL` | 瀏覽器發布 Faro 負載的 URL | 否 | | `/-/faro` |

> [!NOTE]
> 僅在設定 `TUIST_FARO_COLLECTOR_URL` 時才會啟用真實用戶監控。若未設定，則不會收集任何瀏覽器遙測數據，也不會載入任何第三方腳本。

同源路徑（例如 `/-/faro`）可避免跨源請求，並保持瀏覽器的內容安全政策不變。請透過你的入口將其指向你的 Faro 接收器。

### 收集的內容 {#real-user-monitoring-collected}

- **網頁指標**：LCP、CLS、INP、FCP 和 TTFB，由瀏覽器自動捕捉
- **頁面瀏覽**：在載入和 Phoenix LiveView 導航時記錄
- **視圖**：每個負載都帶有產生它的區段 — `marketing`、`docs`、`dashboard` 或 `api-docs`
- **錯誤**：未捕獲的異常和未處理的 Promise 拒絕

### 隱私考量 {#real-user-monitoring-privacy}

- 不附加用戶身份：負載不包含用戶 ID、電子郵件或帳戶
- 工作階段不會在訪問之間持久化，因此不會將任何內容寫入瀏覽器儲存空間
- 控制台捕捉已關閉，因此應用程式日誌輸出絕不會從瀏覽器發送

## Elixir 指標 {#elixir-metrics}

預設情況下，我們包含 Elixir 運行時、BEAM、Elixir 以及我們使用的部分函式庫的指標。以下是你可以看到的一些指標：

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

我們建議查看這些頁面，以了解有哪些可用指標以及如何使用它們。

## Runs 指標 {#runs-metrics}

一組與 Tuist Runs 相關的指標。

### `tuist_runs_total`（計數器）{#tuist_runs_total-counter}

Tuist Runs 的總數。

#### 標籤 {#tuist-runs-total-tags}

| 標籤 | 說明 |
|--- | ---- |
| `name` | 運行的 `tuist` 命令名稱，例如 `build`、`test` 等。 |
| `is_ci` | 一個布林值，指示執行者是 CI 還是開發人員的機器。 |
| `status` | `success` 時為 `0`，`failure` 時為 `1`。 |

### `tuist_runs_duration_milliseconds`（直方圖）{#tuist_runs_duration_milliseconds-histogram}

每次 tuist 運行的總持續時間（以毫秒為單位）。

#### 標籤 {#tuist-runs-duration-miliseconds-tags}

| 標籤 | 說明 |
|--- | ---- |
| `name` | 運行的 `tuist` 命令名稱，例如 `build`、`test` 等。 |
| `is_ci` | 一個布林值，指示執行者是 CI 還是開發人員的機器。 |
| `status` | `0` 表示 `success`，`1` 表示 `failure`。 |

## 快取指標 {#cache-metrics}

一組與 Tuist Cache 相關的指標。

### `tuist_cache_events_total`（計數器）{#tuist_cache_events_total-counter}

二進位快取事件的總數。

#### 標籤 {#tuist-cache-events-total-tags}

| 標籤 | 說明 |
|--- | ---- |
| `event_type` | 可以是 `local_hit`、`remote_hit` 或 `miss`。 |

### `tuist_cache_uploads_total`（計數器）{#tuist_cache_uploads_total-counter}

上傳至二進位快取的次數。

### `tuist_cache_uploaded_bytes`（總和）{#tuist_cache_uploaded_bytes-sum}

上傳至二進位快取的位元組數。

### `tuist_cache_downloads_total`（計數器）{#tuist_cache_downloads_total-counter}

從二進位快取下載的次數。

### `tuist_cache_downloaded_bytes`（總和）{#tuist_cache_downloaded_bytes-sum}

從二進位快取下載的位元組數。

---

## Previews 指標 {#previews-metrics}

一組與 previews 功能相關的指標。

### `tuist_previews_uploads_total`（總和）{#tuist_previews_uploads_total-counter}

上傳的 previews 總數。

### `tuist_previews_downloads_total`（總和）{#tuist_previews_downloads_total-counter}

下載的 previews 總數。

---

## 儲存指標 {#storage-metrics}

一組與遠端儲存（例如 s3）中構件儲存相關的指標。

> [!TIP]
> 這些指標有助於了解儲存操作的效能並識別潛在瓶頸。


### `tuist_storage_get_object_size_size_bytes`（直方圖）{#tuist_storage_get_object_size_size_bytes-histogram}

從遠端儲存獲取的物件大小（以位元組為單位）。

#### 標籤 {#tuist-storage-get-object-size-size-bytes-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |


### `tuist_storage_get_object_size_duration_miliseconds`（直方圖）{#tuist_storage_get_object_size_duration_miliseconds-histogram}

從遠端儲存獲取物件大小的持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-get-object-size-duration-miliseconds-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |


### `tuist_storage_get_object_size_count`（計數器）{#tuist_storage_get_object_size_count-counter}

從遠端儲存獲取物件大小的次數。

#### 標籤 {#tuist-storage-get-object-size-count-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |

### `tuist_storage_delete_all_objects_duration_milliseconds`（直方圖）{#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

從遠端儲存刪除所有物件的持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| 標籤 | 說明 |
|--- | ---- |
| `project_slug` | 其物件正被刪除之專案的專案 slug。 |


### `tuist_storage_delete_all_objects_count`（計數器）{#tuist_storage_delete_all_objects_count-counter}

從遠端儲存刪除所有專案物件的次數。

#### 標籤 {#tuist-storage-delete-all-objects-count-tags}

| 標籤 | 說明 |
|--- | ---- |
| `project_slug` | 其物件正被刪除之專案的專案 slug。 |


### `tuist_storage_multipart_start_upload_duration_milliseconds`（直方圖）{#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

開始上傳至遠端儲存的持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |

### `tuist_storage_multipart_start_upload_duration_count`（計數器）{#tuist_storage_multipart_start_upload_duration_count-counter}

開始上傳至遠端儲存的次數。

#### 標籤 {#tuist-storage-multipart-start-upload-duration-count-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |


### `tuist_storage_get_object_as_string_duration_milliseconds`（直方圖）{#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

從遠端儲存以字串形式獲取物件的持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |

### `tuist_storage_get_object_as_string_count`（計數）{#tuist_storage_get_object_as_string_count-count}

從遠端儲存以字串形式獲取物件的次數。

#### 標籤 {#tuist-storage-get-object-as-string-count-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |


### `tuist_storage_check_object_existence_duration_milliseconds`（直方圖）{#tuist_storage_check_object_existence_duration_milliseconds-histogram}

檢查遠端儲存中物件是否存在的持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |

### `tuist_storage_check_object_existence_count`（計數）{#tuist_storage_check_object_existence_count-count}

檢查遠端儲存中物件是否存在的次數。

#### 標籤 {#tuist-storage-check-object-existence-count-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds`（直方圖）{#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

為遠端儲存中的物件產生下載預簽名 URL 的持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |


### `tuist_storage_generate_download_presigned_url_count`（計數）{#tuist_storage_generate_download_presigned_url_count-count}

為遠端儲存中的物件產生下載預簽名 URL 的次數。

#### 標籤 {#tuist-storage-generate-download-presigned-url-count-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds`（直方圖）{#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

為遠端儲存中的物件產成分區上傳預簽名 URL 的持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |
| `part_number` | 正在上傳之物件的分區編號。 |
| `upload_id` | 多部分上傳的上傳 ID。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count`（計數）{#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

為遠端儲存中的物件產成分區上傳預簽名 URL 的次數。

#### 標籤 {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |
| `part_number` | 正在上傳之物件的分區編號。 |
| `upload_id` | 多部分上傳的上傳 ID。 |

### `tuist_storage_multipart_complete_upload_duration_milliseconds`（直方圖）{#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

完成上傳至遠端儲存的持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |
| `upload_id` | 多部分上傳的上傳 ID。 |


### `tuist_storage_multipart_complete_upload_count`（計數器）{#tuist_storage_multipart_complete_upload_count-count}

完成上傳至遠端儲存的總次數。

#### 標籤 {#tuist-storage-multipart-complete-upload-count-tags}

| 標籤 | 說明 |
|--- | ---- |
| `object_key` | 遠端儲存中物件的查找鍵。 |
| `upload_id` | 多部分上傳的上傳 ID。 |

---

## 驗證指標 {#authentication-metrics}

一組與驗證相關的指標。

### `tuist_authentication_token_refresh_error_total`（計數器）{#tuist_authentication_token_refresh_error_total-counter}

令牌刷新錯誤的總數。

#### 標籤 {#tuist-authentication-token-refresh-error-total-tags}

| 標籤 | 說明 |
|--- | ---- |
| `cli_version` | 遇到錯誤的 Tuist CLI 版本。 |
| `reason` | 令牌刷新錯誤的原因，例如 `invalid_token_type` 或 `invalid_token`。 |

---

## 專案指標 {#projects-metrics}

一組與專案相關的指標。

### `tuist_projects_total`（最新值）{#tuist_projects_total-last_value}

專案總數。

---

## 帳戶指標 {#accounts-metrics}

一組與帳戶（用戶和組織）相關的指標。

### `tuist_accounts_organizations_total`（最新值）{#tuist_accounts_organizations_total-last_value}

組織總數。

### `tuist_accounts_users_total`（最新值）{#tuist_accounts_users_total-last_value}

用戶總數。


## 資料庫指標 {#database-metrics}

一組與資料庫連線相關的指標。

儲存庫集區指標每 100 毫秒在內部採樣一次，然後透過 `/metrics` 公開給 Prometheus。下方的 `last_value` 指標顯示抓取時的最新集區狀態。後方的壓力指標是從這些 100 毫秒樣本得出的總和，即使飽和情況在下一次抓取前已恢復，亦能更容易察覺短暫的飽和窗口。

### `tuist_repo_pool_checkout_queue_length`（最新值）{#tuist_repo_pool_checkout_queue_length-last_value}

正在佇列中等待分配至資料庫連線的資料庫查詢數量。

#### 標籤 {#tuist_repo_pool_checkout_queue_length-tags}

| 標籤 | 說明 |
|--- | ---- |
| `repo` | 發出該指標的儲存庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層資料庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_ready_conn_count`（最新值）{#tuist_repo_pool_ready_conn_count-last_value}

準備好分配給資料庫查詢的資料庫連線數量。

#### 標籤 {#tuist_repo_pool_ready_conn_count-tags}

| 標籤 | 說明 |
|--- | ---- |
| `repo` | 發出該指標的儲存庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層資料庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_size`（最新值）{#tuist_repo_pool_size-last_value}

集區中設定的連線數量。

#### 標籤 {#tuist_repo_pool_size-tags}

| 標籤 | 說明 |
|--- | ---- |
| `repo` | 發出該指標的儲存庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層資料庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_total_samples_sum`（總和）{#tuist_repo_pool_checkout_queue_total_samples_sum-sum}

執行的儲存庫集區輪詢總次數（每次輪詢增加 1）。計算忙碌或飢餓百分比時，請將此作為分母：`rate(busy_samples) / rate(total_samples)` 或 `rate(starved_samples) / rate(total_samples)`。

#### 標籤 {#tuist_repo_pool_checkout_queue_total_samples_sum-tags}

| 標籤 | 說明 |
|--- | ---- |
| `repo` | 發出該指標的儲存庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層資料庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_observed_sum`（總和）{#tuist_repo_pool_checkout_queue_observed_sum-sum}

在儲存庫集區輪詢中觀察到的排隊檢出請求總和。這有助於偵測短暫的集區爭用爆發，這些情況可能無法僅從最新的佇列長度樣本中看出。

#### 標籤 {#tuist_repo_pool_checkout_queue_observed_sum-tags}

| 標籤 | 說明 |
|--- | ---- |
| `repo` | 發出該指標的儲存庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層資料庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_busy_samples_sum`（總和）{#tuist_repo_pool_checkout_queue_busy_samples_sum-sum}

儲存庫集區輪詢中，至少有一個資料庫檢出請求在佇列中等待的次數。

#### 標籤 {#tuist_repo_pool_checkout_queue_busy_samples_total-tags}

| 標籤 | 說明 |
|--- | ---- |
| `repo` | 發出該指標的儲存庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層資料庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_starved_samples_sum`（總和）{#tuist_repo_pool_checkout_queue_starved_samples_sum-sum}

儲存庫集區輪詢中，檢出請求已排隊且沒有可用連線的次數。此處持續增加通常表示集區已飽和。

#### 標籤 {#tuist_repo_pool_checkout_queue_starved_samples_total-tags}

| 標籤 | 說明 |
|--- | ---- |
| `repo` | 發出該指標的儲存庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層資料庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_db_connection_connected`（計數器）{#tuist_repo_pool_db_connection_connected-counter}

已建立至資料庫的連線數量。

### `tuist_repo_pool_db_connection_disconnected`（計數器）{#tuist_repo_pool_db_connection_disconnected-counter}

已從資料庫斷開的連線數量。

#### 標籤 {#tuist_repo_pool_db_connection_connected_and_disconnected-tags}

| 標籤 | 說明 |
|--- | ---- |
| `tag` | 識別發出儲存庫的 DBConnection 監聽器標籤。 |

## HTTP 指標 {#http-metrics}

一組與 Tuist 透過 HTTP 與其他服務互動相關的指標。

### `tuist_http_request_count`（計數器）{#tuist_http_request_count-last_value}

傳出 HTTP 請求的數量。

### `tuist_http_request_duration_nanoseconds_sum`（總和）{#tuist_http_request_duration_nanoseconds_sum-last_value}

傳出請求持續時間的總和（包括等待分配至連線的時間）。

### `tuist_http_request_duration_nanoseconds_bucket`（分佈）{#tuist_http_request_duration_nanoseconds_bucket-distribution}
傳出請求持續時間的分佈（包括等待分配至連線的時間）。

### `tuist_http_queue_count`（計數器）{#tuist_http_queue_count-counter}

已從集區檢取的請求數量。

### `tuist_http_queue_duration_nanoseconds_sum`（總和）{#tuist_http_queue_duration_nanoseconds_sum-sum}

從集區檢取連線所需的時間。

### `tuist_http_queue_idle_time_nanoseconds_sum`（總和）{#tuist_http_queue_idle_time_nanoseconds_sum-sum}

連線閒置等待被檢取的時間。

### `tuist_http_queue_duration_nanoseconds_bucket`（分佈）{#tuist_http_queue_duration_nanoseconds_bucket-distribution}

從集區檢取連線所需的時間。

### `tuist_http_queue_idle_time_nanoseconds_bucket`（分佈）{#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

連線閒置等待被檢取的時間。

### `tuist_http_connection_count`（計數器）{#tuist_http_connection_count-counter}

已建立的連線數量。

### `tuist_http_connection_duration_nanoseconds_sum`（總和）{#tuist_http_connection_duration_nanoseconds_sum-sum}

與主機建立連線所需的時間。

### `tuist_http_connection_duration_nanoseconds_bucket`（分佈）{#tuist_http_connection_duration_nanoseconds_bucket-distribution}

與主機建立連線所需時間的分佈。

### `tuist_http_send_count`（計數器）{#tuist_http_send_count-counter}

已分配至集區連線並發出的請求數量。

### `tuist_http_send_duration_nanoseconds_sum`（總和）{#tuist_http_send_duration_nanoseconds_sum-sum}

分配至集區連線後，請求完成所需的時間。

### `tuist_http_send_duration_nanoseconds_bucket`（分佈）{#tuist_http_send_duration_nanoseconds_bucket-distribution}

分配至集區連線後，請求完成所需時間的分佈。

### `tuist_http_receive_count`（計數器）{#tuist_http_receive_count-counter}

已收到來自已發出請求的回應數量。

### `tuist_http_receive_duration_nanoseconds_sum`（總和）{#tuist_http_receive_duration_nanoseconds_sum-sum}

接收回應所花的時間。

### `tuist_http_receive_duration_nanoseconds_bucket`（分佈）{#tuist_http_receive_duration_nanoseconds_bucket-distribution}

接收回應所花時間的分佈。

### `tuist_http_queue_available_connections`（最新值）{#tuist_http_queue_available_connections-last_value}

佇列中可用的連線數量。

### `tuist_http_queue_in_use_connections`（最新值）{#tuist_http_queue_in_use_connections-last_value}

使用中佇列連線的數量。
