---
{
  "title": "遙測",
  "titleTemplate": ":title | 自行託管 | 伺服器 | 指南 | Tuist",
  "description": "透過 Prometheus 指標、OpenTelemetry 追蹤記錄同日誌轉發，監察你嘅 Tuist 伺服器。"
}
---
# 遙測 {#telemetry}

Tuist 提供三種互補的可觀察性信號：**指標**（Prometheus）、**追蹤**（OpenTelemetry）和 **日誌**（兼容 Loki）。這三者均為可選，並可獨立啟用。

## 分散式追蹤（OpenTelemetry）{#opentelemetry}

Tuist 支援使用 [OpenTelemetry](https://opentelemetry.io/) 進行分散式追蹤。啟用後，伺服器會為 HTTP 請求（Phoenix 和 Bandit）、資料庫查詢（Ecto）、外發 HTTP 呼叫（Finch）以及 Broadway 訊息處理發出追蹤記錄。這些追蹤記錄讓你能了解請求延遲、識別慢查詢，並跨服務追蹤請求。

### 設定 {#opentelemetry-configuration}

設定以下環境變數以啟用追蹤匯出：

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry Collector 的 gRPC 端點（例如 Grafana Alloy、Jaeger 或任何兼容 OTLP 的收集器） | 否 | | `http://localhost:4317` |

若未設定此變數，則不會啟用追蹤，亦不會增加額外負荷。

### 已插樁的函式庫 {#opentelemetry-instrumented-libraries}

啟用追蹤時，以下函式庫會自動被插樁：

- **Bandit** — HTTP 伺服器連線跨度
- **Phoenix** — 請求生命週期跨度（控制器動作、LiveView）
- **Ecto** — 帶有查詢元數據的資料庫查詢跨度
- **Finch** — 外發 HTTP 用戶端請求跨度
- **Broadway** — 訊息處理管線跨度

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

然後將 `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` 設定為指向 Alloy 實例，例如 `http://alloy:4317`。

## 日誌轉發（Loki）{#log-forwarding}

Tuist 可以將應用程式日誌轉發至兼容 [Loki](https://grafana.com/oss/loki/) 的端點。這讓你能够將日誌與指標和追蹤記錄集中管理，形成完整的可觀察性視圖。日誌透過 Loki HTTP push API（`/loki/api/v1/push`）推送，並包含 `app`、`env` 和 `level` 的標籤。

### 設定 {#log-forwarding-configuration}

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_LOKI_URL` | 兼容 Loki 的 push API 端點的基本 URL | 否 | | `http://localhost:3100` |

若未設定此變數，則不會啟用日誌轉發。

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

如果 Loki 實例公開了 push API，你也可以將 `TUIST_LOKI_URL` 直接指向該實例。

## Prometheus 指標 {#prometheus-metrics}

你可以使用 [Prometheus](https://prometheus.io/) 和像 [Grafana](https://grafana.com/) 這樣的視覺化工具，匯入 Tuist 伺服器收集的指標，以建立符合你需求的自訂儀表板。Prometheus 指標透過連接埠 9091 上的 `/metrics` 端點提供。Prometheus 的 [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) 應設定為少於 10_000 秒（我們建議設為 30 秒，以平衡可觀察性與指標匯入成本）。

## 真實用戶監控 {#real-user-monitoring}

Tuist 可以使用捆綁在所提供的 JavaScript 中的 [Grafana Faro](https://grafana.com/oss/faro/) Web SDK，從營銷網站、文檔和儀表板報告瀏覽器性能。它會捕獲核心網頁指標（包括最大內容繪製 LCP）、未捕獲的錯誤和頁面瀏覽量，並將它們發佈到你運行的 [Faro 接收器](https://grafana.com/docs/alloy/latest/reference/components/faro/faro.receiver/) — 例如 Grafana Alloy 中的 `faro.receiver` 元件，該元件會將數據轉發到 Loki 和 Tempo。

### 設定 {#real-user-monitoring-configuration}

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_FARO_COLLECTOR_URL` | 瀏覽器張貼 Faro 負載的 URL | 否 | | `/-/faro` |

> [!NOTE]
> 只有在設定 `TUIST_FARO_COLLECTOR_URL` 時才會啟用真實用戶監控。若未設定，則不會收集任何瀏覽器遙測數據，也不會加載任何第三方腳本。

使用同源路徑（例如 `/-/faro`）可以避免跨源請求，並保持瀏覽器的內容安全策略不變。請通過你的入口將其指向你的 Faro 接收器。

### 收集的內容 {#real-user-monitoring-collected}

- **網頁指標**：LCP、CLS、INP、FCP 和 TTFB，由瀏覽器自動捕獲
- **頁面瀏覽**：在加載和 Phoenix LiveView 導航時記錄
- **視圖**：每個負載都帶有產生它的部分 — `marketing`、`docs`、`dashboard` 或 `api-docs`
- **錯誤**：未捕獲的異常和未處理的 Promise 拒絕

### 隱私考量 {#real-user-monitoring-privacy}

- 不附加用戶身份：負載中不包含用戶 ID、電子郵件或帳戶信息
- 會話不會在訪問之間持久化，因此不會向瀏覽器存儲寫入任何內容
- 控制台捕獲已關閉，因此應用程序日誌輸出絕不會從瀏覽器發送

## Elixir 指標 {#elixir-metrics}

默認情況下，我們包含 Elixir 運行時、BEAM、Elixir 以及我們使用的一些函式庫的指標。以下是一些你可以看到的指標：

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

我們建議查看這些頁面以了解有哪些可用指標以及如何使用它們。

## Runs 指標 {#runs-metrics}

一組與 Tuist Runs 相關的指標。

### `tuist_runs_total`（計數器）{#tuist_runs_total-counter}

Tuist Runs 的總數。

#### 標籤 {#tuist-runs-total-tags}

| 標籤 | 描述 |
|--- | ---- |
| `name` | 運行的 `tuist` 命令的名稱，例如 `build`、`test` 等。 |
| `is_ci` | 一個布爾值，指示執行者是 CI 還是開發人員的機器。 |
| `status` | `success` 時為 `0`，`failure` 時為 `1`。 |

### `tuist_runs_duration_milliseconds`（直方圖）{#tuist_runs_duration_milliseconds-histogram}

每次 tuist 運行的總持續時間（毫秒）。

#### 標籤 {#tuist-runs-duration-miliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `name` | 運行的 `tuist` 命令的名稱，例如 `build`、`test` 等。 |
| `is_ci` | 一個布爾值，指示執行者是 CI 還是開發人員的機器。 |
| `status` | `0` 表示 `success`，`1` 表示 `failure`。 |

## 快取指標 {#cache-metrics}

一組與 Tuist 快取相關的指標。

### `tuist_cache_events_total`（計數器）{#tuist_cache_events_total-counter}

二進制快取事件的總數。

#### 標籤 {#tuist-cache-events-total-tags}

| 標籤 | 描述 |
|--- | ---- |
| `event_type` | 可以是 `local_hit`、`remote_hit` 或 `miss`。 |

### `tuist_cache_uploads_total`（計數器）{#tuist_cache_uploads_total-counter}

上傳至二進制快取的次數。

### `tuist_cache_uploaded_bytes`（總和）{#tuist_cache_uploaded_bytes-sum}

上傳至二進制快取的字節數。

### `tuist_cache_downloads_total`（計數器）{#tuist_cache_downloads_total-counter}

從二進制快取下載的次數。

### `tuist_cache_downloaded_bytes`（總和）{#tuist_cache_downloaded_bytes-sum}

從二進制快取下載的字節數。

---

## 預覽指標 {#previews-metrics}

一組與預覽功能相關的指標。

### `tuist_previews_uploads_total`（總和）{#tuist_previews_uploads_total-counter}

上傳的預覽總數。

### `tuist_previews_downloads_total`（總和）{#tuist_previews_downloads_total-counter}

下載的預覽總數。

---

## 存儲指標 {#storage-metrics}

一組與遠程存儲（例如 S3）中構件存儲相關的指標。

> [!TIP]
> 這些指標有助於了解存儲操作的性能並識別潛在瓶頸。


### `tuist_storage_get_object_size_size_bytes`（直方圖）{#tuist_storage_get_object_size_size_bytes-histogram}

從遠程存儲獲取的對象大小（字節）。

#### 標籤 {#tuist-storage-get-object-size-size-bytes-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |


### `tuist_storage_get_object_size_duration_miliseconds`（直方圖）{#tuist_storage_get_object_size_duration_miliseconds-histogram}

從遠程存儲獲取對象大小的持續時間（毫秒）。

#### 標籤 {#tuist-storage-get-object-size-duration-miliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |


### `tuist_storage_get_object_size_count`（計數器）{#tuist_storage_get_object_size_count-counter}

從遠程存儲獲取對象大小的次數。

#### 標籤 {#tuist-storage-get-object-size-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |

### `tuist_storage_delete_all_objects_duration_milliseconds`（直方圖）{#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

從遠程存儲刪除所有對象的持續時間（毫秒）。

#### 標籤 {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `project_slug` | 其對象正被刪除的項目的項目 slug。 |


### `tuist_storage_delete_all_objects_count`（計數器）{#tuist_storage_delete_all_objects_count-counter}

從遠程存儲刪除所有項目對象的次數。

#### 標籤 {#tuist-storage-delete-all-objects-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `project_slug` | 其對象正被刪除的項目的項目 slug。 |


### `tuist_storage_multipart_start_upload_duration_milliseconds`（直方圖）{#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

開始上傳至遠程存儲的持續時間（毫秒）。

#### 標籤 {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |

### `tuist_storage_multipart_start_upload_duration_count`（計數器）{#tuist_storage_multipart_start_upload_duration_count-counter}

開始上傳至遠程存儲的次數。

#### 標籤 {#tuist-storage-multipart-start-upload-duration-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |


### `tuist_storage_get_object_as_string_duration_milliseconds`（直方圖）{#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

從遠程存儲以字符串形式獲取對象的持續時間（毫秒）。

#### 標籤 {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |

### `tuist_storage_get_object_as_string_count`（計數）{#tuist_storage_get_object_as_string_count-count}

從遠程存儲以字符串形式獲取對象的次數。

#### 標籤 {#tuist-storage-get-object-as-string-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |


### `tuist_storage_check_object_existence_duration_milliseconds`（直方圖）{#tuist_storage_check_object_existence_duration_milliseconds-histogram}

檢查遠程存儲中對象存在性的持續時間（毫秒）。

#### 標籤 {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |

### `tuist_storage_check_object_existence_count`（計數）{#tuist_storage_check_object_existence_count-count}

檢查遠程存儲中對象存在性的次數。

#### 標籤 {#tuist-storage-check-object-existence-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds`（直方圖）{#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

為遠程存儲中的對象生成下載預簽名 URL 的持續時間（毫秒）。

#### 標籤 {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |


### `tuist_storage_generate_download_presigned_url_count`（計數）{#tuist_storage_generate_download_presigned_url_count-count}

為遠程存儲中的對象生成下載預簽名 URL 的次數。

#### 標籤 {#tuist-storage-generate-download-presigned-url-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds`（直方圖）{#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

為遠程存儲中的對象生成分部分上傳預簽名 URL 的持續時間（毫秒）。

#### 標籤 {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |
| `part_number` | 正在上傳的對象的部分編號。 |
| `upload_id` | 多部分上傳的上傳 ID。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count`（計數）{#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

為遠程存儲中的對象生成分部分上傳預簽名 URL 的次數。

#### 標籤 {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |
| `part_number` | 正在上傳的對象的部分編號。 |
| `upload_id` | 多部分上傳的上傳 ID。 |

### `tuist_storage_multipart_complete_upload_duration_milliseconds`（直方圖）{#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

完成上傳至遠程存儲的持續時間（毫秒）。

#### 標籤 {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |
| `upload_id` | 多部分上傳的上傳 ID。 |


### `tuist_storage_multipart_complete_upload_count`（計數）{#tuist_storage_multipart_complete_upload_count-count}

完成上傳至遠程存儲的總次數。

#### 標籤 {#tuist-storage-multipart-complete-upload-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象的查找鍵。 |
| `upload_id` | 多部分上傳的上傳 ID。 |

---

## 身份驗證指標 {#authentication-metrics}

一組與身份驗證相關的指標。

### `tuist_authentication_token_refresh_error_total`（計數器）{#tuist_authentication_token_refresh_error_total-counter}

令牌刷新錯誤的總數。

#### 標籤 {#tuist-authentication-token-refresh-error-total-tags}

| 標籤 | 描述 |
|--- | ---- |
| `cli_version` | 遇到錯誤的 Tuist CLI 版本。 |
| `reason` | 令牌刷新錯誤的原因，例如 `invalid_token_type` 或 `invalid_token`。 |

---

## 項目指標 {#projects-metrics}

一組與項目相關的指標。

### `tuist_projects_total`（最後值）{#tuist_projects_total-last_value}

項目總數。

---

## 帳戶指標 {#accounts-metrics}

一組與帳戶（用戶和組織）相關的指標。

### `tuist_accounts_organizations_total`（最後值）{#tuist_accounts_organizations_total-last_value}

組織總數。

### `tuist_accounts_users_total`（最後值）{#tuist_accounts_users_total-last_value}

用戶總數。


## 數據庫指標 {#database-metrics}

一組與數據庫連接相關的指標。

Repo 池指標每 100 毫秒在內部採樣一次，然後通過 `/metrics` 暴露給 Prometheus。下方的 `last_value` 指標顯示抓取時最新的池狀態。更下方的壓力指標是從這些 100 毫秒樣本得出的總和，這使得即使在下次抓取之前恢復，也更容易發現短暫的飽和窗口。

### `tuist_repo_pool_checkout_queue_length`（最後值）{#tuist_repo_pool_checkout_queue_length-last_value}

排隊等待分配給數據庫連接的數據庫查詢數量。

#### 標籤 {#tuist_repo_pool_checkout_queue_length-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出該指標的存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 後端數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_ready_conn_count`（最後值）{#tuist_repo_pool_ready_conn_count-last_value}

準備好分配給數據庫查詢的數據庫連接數量。

#### 標籤 {#tuist_repo_pool_ready_conn_count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出該指標的存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 後端數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_size`（最後值）{#tuist_repo_pool_size-last_value}

池中配置的連接數量。

#### 標籤 {#tuist_repo_pool_size-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出該指標的存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 後端數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_total_samples_sum`（總和）{#tuist_repo_pool_checkout_queue_total_samples_sum-sum}

執行的 repo 池輪詢總次數（每次輪詢增加 1）。在計算繁忙或飢餓百分比時，將此用作分母：`rate(busy_samples) / rate(total_samples)` 或 `rate(starved_samples) / rate(total_samples)`。

#### 標籤 {#tuist_repo_pool_checkout_queue_total_samples_sum-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出該指標的存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 後端數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_observed_sum`（總和）{#tuist_repo_pool_checkout_queue_observed_sum-sum}

在 repo 池輪詢中觀察到的排隊檢出請求總和。這對於檢測可能在最新隊列長度樣本中不可見的短暫池爭用爆發很有用。

#### 標籤 {#tuist_repo_pool_checkout_queue_observed_sum-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出該指標的存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 後端數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_busy_samples_sum`（總和）{#tuist_repo_pool_checkout_queue_busy_samples_sum-sum}

至少有一個數據庫檢出請求在隊列中等待的 repo 池輪詢次數。

#### 標籤 {#tuist_repo_pool_checkout_queue_busy_samples_total-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出該指標的存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 後端數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_starved_samples_sum`（總和）{#tuist_repo_pool_checkout_queue_starved_samples_sum-sum}

檢出請求排隊且沒有可用就緒連接的 repo 池輪詢次數。此處持續增加通常意味著池已飽和。

#### 標籤 {#tuist_repo_pool_checkout_queue_starved_samples_total-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出該指標的存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 後端數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_db_connection_connected`（計數器）{#tuist_repo_pool_db_connection_connected-counter}

已建立到數據庫的連接數量。

### `tuist_repo_pool_db_connection_disconnected`（計數器）{#tuist_repo_pool_db_connection_disconnected-counter}

已從數據庫斷開的連接數量。

#### 標籤 {#tuist_repo_pool_db_connection_connected_and_disconnected-tags}

| 標籤 | 描述 |
|--- | ---- |
| `tag` | 標識發出存儲庫的 DBConnection 偵聽器標籤。 |

## HTTP 指標 {#http-metrics}

一組與 Tuist 通過 HTTP 與其他服務交互相關的指標。

### `tuist_http_request_count`（計數器）{#tuist_http_request_count-last_value}

傳出 HTTP 請求的數量。

### `tuist_http_request_duration_nanosecond_sum`（總和）{#tuist_http_request_duration_nanosecond_sum-last_value}

傳出請求持續時間的總和（包括等待分配給連接的時間）。

### `tuist_http_request_duration_nanosecond_bucket`（分佈）{#tuist_http_request_duration_nanosecond_bucket-distribution}
傳出請求持續時間的分佈（包括等待分配給連接的時間）。

### `tuist_http_queue_count`（計數器）{#tuist_http_queue_count-counter}

已從池中檢索的請求數量。

### `tuist_http_queue_duration_nanoseconds_sum`（總和）{#tuist_http_queue_duration_nanoseconds_sum-sum}

從池中檢索連接所需的時間。

### `tuist_http_queue_idle_time_nanoseconds_sum`（總和）{#tuist_http_queue_idle_time_nanoseconds_sum-sum}

連接空閒等待被檢索的時間。

### `tuist_http_queue_duration_nanoseconds_bucket`（分佈）{#tuist_http_queue_duration_nanoseconds_bucket-distribution}

從池中檢索連接所需的時間。

### `tuist_http_queue_idle_time_nanoseconds_bucket`（分佈）{#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

連接空閒等待被檢索的時間。

### `tuist_http_connection_count`（計數器）{#tuist_http_connection_count-counter}

已建立的連接數量。

### `tuist_http_connection_duration_nanoseconds_sum`（總和）{#tuist_http_connection_duration_nanoseconds_sum-sum}

與主機建立連接所需的時間。

### `tuist_http_connection_duration_nanoseconds_bucket`（分佈）{#tuist_http_connection_duration_nanoseconds_bucket-distribution}

與主機建立連接所需時間的分佈。

### `tuist_http_send_count`（計數器）{#tuist_http_send_count-counter}

從池中分配連接後已發送的請求數量。

### `tuist_http_send_duration_nanoseconds_sum`（總和）{#tuist_http_send_duration_nanoseconds_sum-sum}

從池中分配連接後請求完成所需的時間。

### `tuist_http_send_duration_nanoseconds_bucket`（分佈）{#tuist_http_send_duration_nanoseconds_bucket-distribution}

從池中分配連接後請求完成所需時間的分佈。

### `tuist_http_receive_count`（計數器）{#tuist_http_receive_count-counter}

已收到發送請求的回應數量。

### `tuist_http_receive_duration_nanoseconds_sum`（總和）{#tuist_http_receive_duration_nanoseconds_sum-sum}

接收回應所花的時間。

### `tuist_http_receive_duration_nanoseconds_bucket`（分佈）{#tuist_http_receive_duration_nanoseconds_bucket-distribution}

接收回應所花時間的分佈。

### `tuist_http_queue_available_connections`（最後值）{#tuist_http_queue_available_connections-last_value}

隊列中可用的連接數量。

### `tuist_http_queue_in_use_connections`（最後值）{#tuist_http_queue_in_use_connections-last_value}

正在使用的隊列連接數量。
