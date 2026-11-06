---
{
  "title": "遙測",
  "titleTemplate": ":title | 自行託管 | 伺服器 | 指南 | Tuist",
  "description": "透過 Prometheus 指標、OpenTelemetry 追蹤記錄同日誌轉發，監察你嘅 Tuist 伺服器。"
}
---
# 遙測 {#telemetry}

Tuist 提供三個互補的可觀測性信號：**指標**（Prometheus）、**追蹤**（OpenTelemetry）同**日誌**（兼容 Loki）。三者皆為可選，可以獨立啟用。

## 分散式追蹤（OpenTelemetry） {#opentelemetry}

Tuist 支援使用 [OpenTelemetry](https://opentelemetry.io/) 進行分散式追蹤。啟用後，伺服器會為 HTTP 請求（Phoenix 同 Bandit）、數據庫查詢（Ecto）、傳出 HTTP 呼叫（Finch）以及 Broadway 訊息處理發出追蹤數據。呢啲追蹤數據令你了解請求延遲、識別慢查詢，並跨服務追蹤請求。

### 設定 {#opentelemetry-configuration}

設定以下環境變數以啟用追蹤匯出：

| 環境變數 | 描述 | 必需 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry Collector 嘅 gRPC 端點（例如 Grafana Alloy、Jaeger 或任何兼容 OTLP 嘅收集器） | 否 | | `http://localhost:4317` |

如果未設定此變數，追蹤功能將被禁用且不會增加額外開銷。

### 已插樁嘅函式庫 {#opentelemetry-instrumented-libraries}

啟用追蹤時，以下函式庫會自動被插樁：

- **Bandit** -- HTTP 伺服器連線跨度
- **Phoenix** -- 請求生命週期跨度（控制器動作、LiveView）
- **Ecto** -- 帶查詢元數據嘅數據庫查詢跨度
- **Finch** -- 傳出 HTTP 客戶端請求跨度
- **Broadway** -- 訊息處理管道跨度

### 使用 Grafana Alloy 嘅設定範例 {#opentelemetry-alloy-example}

如果你使用 [Grafana Alloy](https://grafana.com/docs/alloy/latest/) 作為收集器，請將其設定為接收 OTLP 追蹤數據並轉發到你嘅追蹤後端（例如 Grafana Cloud Tempo）：

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

然後設定 `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` 指向 Alloy 實例，例如 `http://alloy:4317`。

## 日誌轉發（Loki） {#log-forwarding}

Tuist 可以將應用程式日誌轉發到兼容 [Loki](https://grafana.com/oss/loki/) 嘅端點。這允許你將日誌與指標和追蹤集中在一起，形成完整嘅可觀測性視圖。日誌通過 Loki HTTP push API（`/loki/api/v1/push`）推送，並包含 `app`、`env` 同 `level` 嘅標籤。

### 設定 {#log-forwarding-configuration}

| 環境變數 | 描述 | 必需 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_LOKI_URL` | 兼容 Loki 嘅 push API 端點嘅基礎 URL | 否 | | `http://localhost:3100` |

如果未設定此變數，日誌轉發功能將被禁用。

### 使用 Grafana Alloy 嘅設定範例 {#log-forwarding-alloy-example}

Grafana Alloy 可以使用其 [`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/) 組件作為本地日誌中繼：

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

如果 Loki 實例暴露咗 push API，你也可以直接將 `TUIST_LOKI_URL` 指向該 Loki 實例。

## Prometheus 指標 {#prometheus-metrics}

你可以使用 [Prometheus](https://prometheus.io/) 同 [Grafana](https://grafana.com/) 等可視化工具，匯入 Tuist 伺服器收集嘅指標，從而創建符合你需求嘅自訂儀表板。Prometheus 指標通過端口 9091 上嘅 `/metrics` 端點提供。Prometheus 嘅 [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) 應設定為少於 10_000 秒（我哋建議設定為 30 秒，以平衡可觀測性同指標匯入成本）。

## 真實用戶監控 {#real-user-monitoring}

Tuist 可以使用捆綁喺所提供 JavaScript 中嘅 [Grafana Faro](https://grafana.com/oss/faro/) Web SDK，報告營銷網站、文檔同儀表板嘅瀏覽器性能。它會捕捉核心網頁指標（包括 Largest Contentful Paint）、未捕獲嘅錯誤同頁面瀏覽量，並將它們發佈到你運行嘅 [Faro 接收器](https://grafana.com/docs/alloy/latest/reference/components/faro/faro.receiver/) — 例如 Grafana Alloy 中嘅 `faro.receiver` 組件，該組件會將數據轉發到 Loki 同 Tempo。

### 設定 {#real-user-monitoring-configuration}

| 環境變數 | 描述 | 必需 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_FARO_COLLECTOR_URL` | 瀏覽器張貼 Faro 負載到嘅 URL | 否 | | `/-/faro` |

> [!NOTE]
> 只有當設定咗 `TUIST_FARO_COLLECTOR_URL` 時，真實用戶監控才會啟用。如果冇設定，就不會收集任何瀏覽器遙測數據，也不會加載任何第三方腳本。

像 `/-/faro` 這樣嘅同源路徑可以避免跨域請求，並保持瀏覽器嘅內容安全策略不變。通過你嘅入口將其指向你嘅 Faro 接收器。

### 收集咗乜嘢 {#real-user-monitoring-collected}

- **網頁指標**：LCP、CLS、INP、FCP 同 TTFB，由瀏覽器自動捕捉
- **頁面瀏覽**：在加載同 Phoenix LiveView 導航時記錄
- **視圖**：每個負載都帶有產生它嘅部分 — `marketing`、`docs`、`dashboard` 或 `api-docs`
- **錯誤**：未捕獲嘅異常同未處理嘅 Promise 拒絕

### 隱私考慮 {#real-user-monitoring-privacy}

- 不附帶用戶身份：負載中不包含用戶 ID、電子郵件或賬戶信息
- 會話不會在訪問之間持久化，因此不會將任何內容寫入瀏覽器存儲
- 控制台捕捉已關閉，因此應用程式日誌輸出永遠不會從瀏覽器發送出去

## Elixir 指標 {#elixir-metrics}

默認情況下，我哋包含 Elixir 運行時、BEAM、Elixir 同我哋使用嘅一些函式庫嘅指標。以下係你可以預期看到嘅一些指標：

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

我哋建議查看這些頁面，以了解有哪些可用指標以及如何使用它們。

## Runs 指標 {#runs-metrics}

一組與 Tuist Runs 相關嘅指標。

### `tuist_runs_total`（計數器） {#tuist_runs_total-counter}

Tuist Runs 嘅總數。

#### 標籤 {#tuist-runs-total-tags}

| 標籤 | 描述 |
|--- | ---- |
| `name` | 運行嘅 `tuist` 命令嘅名稱，例如 `build`、`test` 等。 |
| `is_ci` | 一個布爾值，指示執行者係 CI 還係開發人員嘅機器。 |
| `status` | `success` 時為 `0`，`failure` 時為 `1`。 |

### `tuist_runs_duration_milliseconds`（直方圖）{#tuist_runs_duration_milliseconds-histogram}

每次 tuist 運行嘅總持續時間（以毫秒為單位）。

#### 標籤 {#tuist-runs-duration-miliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `name` | 運行嘅 `tuist` 命令嘅名稱，例如 `build`、`test` 等。 |
| `is_ci` | 一個布爾值，指示執行者係 CI 還係開發人員嘅機器。 |
| `status` | `success` 時為 `0`，`failure` 時為 `1`。 |

## 快取指標 {#cache-metrics}

一組與 Tuist Cache 相關嘅指標。

### `tuist_cache_events_total`（計數器）{#tuist_cache_events_total-counter}

二進制快取事件嘅總數。

#### 標籤 {#tuist-cache-events-total-tags}

| 標籤 | 描述 |
|--- | ---- |
| `event_type` | 可以係 `local_hit`、`remote_hit` 或 `miss` 中嘅任何一個。 |

### `tuist_cache_uploads_total`（計數器）{#tuist_cache_uploads_total-counter}

上傳到二進制快取嘅次數。

### `tuist_cache_uploaded_bytes`（總和）{#tuist_cache_uploaded_bytes-sum}

上傳到二進制快取嘅字節數。

### `tuist_cache_downloads_total`（計數器）{#tuist_cache_downloads_total-counter}

從二進制快取下載嘅次數。

### `tuist_cache_downloaded_bytes`（總和）{#tuist_cache_downloaded_bytes-sum}

從二進制快取下載嘅字節數。

---

## Previews 指標 {#previews-metrics}

一組與 previews 功能相關嘅指標。

### `tuist_previews_uploads_total`（總和）{#tuist_previews_uploads_total-counter}

上傳嘅 previews 總數。

### `tuist_previews_downloads_total`（總和）{#tuist_previews_downloads_total-counter}

下載嘅 previews 總數。

---

## 存儲指標 {#storage-metrics}

一組與遠程存儲（例如 s3）中工件存儲相關嘅指標。

> [!TIP]
> 這些指標有助於了解存儲操作嘅性能並識別潛在瓶頸。


### `tuist_storage_get_object_size_size_bytes`（直方圖）{#tuist_storage_get_object_size_size_bytes-histogram}

從遠程存儲獲取嘅對象大小（以字節為單位）。

#### 標籤 {#tuist-storage-get-object-size-size-bytes-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |


### `tuist_storage_get_object_size_duration_miliseconds`（直方圖）{#tuist_storage_get_object_size_duration_miliseconds-histogram}

從遠程存儲獲取對象大小嘅持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-get-object-size-duration-miliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |


### `tuist_storage_get_object_size_count`（計數器）{#tuist_storage_get_object_size_count-counter}

從遠程存儲獲取對象大小嘅次數。

#### 標籤 {#tuist-storage-get-object-size-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |

### `tuist_storage_delete_all_objects_duration_milliseconds`（直方圖）{#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

從遠程存儲刪除所有對象嘅持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `project_slug` | 正在刪除其對象嘅項目嘅項目 slug。 |


### `tuist_storage_delete_all_objects_count`（計數器）{#tuist_storage_delete_all_objects_count-counter}

從遠程存儲刪除所有項目對象嘅次數。

#### 標籤 {#tuist-storage-delete-all-objects-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `project_slug` | 正在刪除其對象嘅項目嘅項目 slug。 |


### `tuist_storage_multipart_start_upload_duration_milliseconds`（直方圖）{#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

開始上傳到遠程存儲嘅持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |

### `tuist_storage_multipart_start_upload_duration_count`（計數器）{#tuist_storage_multipart_start_upload_duration_count-counter}

開始上傳到遠程存儲嘅次數。

#### 標籤 {#tuist-storage-multipart-start-upload-duration-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |


### `tuist_storage_get_object_as_string_duration_milliseconds`（直方圖）{#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

從遠程存儲以字符串形式獲取對象嘅持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |

### `tuist_storage_get_object_as_string_count`（計數）{#tuist_storage_get_object_as_string_count-count}

從遠程存儲以字符串形式獲取對象嘅次數。

#### 標籤 {#tuist-storage-get-object-as-string-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |


### `tuist_storage_check_object_existence_duration_milliseconds`（直方圖）{#tuist_storage_check_object_existence_duration_milliseconds-histogram}

檢查遠程存儲中對象是否存在嘅持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |

### `tuist_storage_check_object_existence_count`（計數）{#tuist_storage_check_object_existence_count-count}

檢查遠程存儲中對象是否存在嘅次數。

#### 標籤 {#tuist-storage-check-object-existence-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds`（直方圖）{#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

為遠程存儲中嘅對象生成下載預簽名 URL 嘅持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |


### `tuist_storage_generate_download_presigned_url_count`（計數）{#tuist_storage_generate_download_presigned_url_count-count}

為遠程存儲中嘅對象生成下載預簽名 URL 嘅次數。

#### 標籤 {#tuist-storage-generate-download-presigned-url-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds`（直方圖）{#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

為遠程存儲中嘅對象生成分部分上傳預簽名 URL 嘅持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |
| `part_number` | 正在上傳對象嘅部分編號。 |
| `upload_id` | 多部分上傳嘅上傳 ID。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count`（計數）{#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

為遠程存儲中嘅對象生成分部分上傳預簽名 URL 嘅次數。

#### 標籤 {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |
| `part_number` | 正在上傳對象嘅部分編號。 |
| `upload_id` | 多部分上傳嘅上傳 ID。 |

### `tuist_storage_multipart_complete_upload_duration_milliseconds`（直方圖）{#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

完成上傳到遠程存儲嘅持續時間（以毫秒為單位）。

#### 標籤 {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |
| `upload_id` | 多部分上傳嘅上傳 ID。 |


### `tuist_storage_multipart_complete_upload_count`（計數器）{#tuist_storage_multipart_complete_upload_count-count}

完成上傳到遠程存儲嘅總次數。

#### 標籤 {#tuist-storage-multipart-complete-upload-count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `object_key` | 遠程存儲中對象嘅查找鍵。 |
| `upload_id` | 多部分上傳嘅上傳 ID。 |

---

## 認證指標 {#authentication-metrics}

一組與認證相關嘅指標。

### `tuist_authentication_token_refresh_error_total`（計數器）{#tuist_authentication_token_refresh_error_total-counter}

令牌刷新錯誤嘅總數。

#### 標籤 {#tuist-authentication-token-refresh-error-total-tags}

| 標籤 | 描述 |
|--- | ---- |
| `cli_version` | 遇到錯誤嘅 Tuist CLI 版本。 |
| `reason` | 令牌刷新錯誤嘅原因，例如 `invalid_token_type` 或 `invalid_token`。 |

---

## 項目指標 {#projects-metrics}

一組與項目相關嘅指標。

### `tuist_projects_total`（最後值）{#tuist_projects_total-last_value}

項目總數。

---

## 帳戶指標 {#accounts-metrics}

一組與帳戶（用戶和組織）相關嘅指標。

### `tuist_accounts_organizations_total`（最後值）{#tuist_accounts_organizations_total-last_value}

組織總數。

### `tuist_accounts_users_total`（最後值）{#tuist_accounts_users_total-last_value}

用戶總數。


## 數據庫指標 {#database-metrics}

一組與數據庫連接相關嘅指標。

Repo 池指標每 100 毫秒內部採樣一次，然後通過 `/metrics` 暴露給 Prometheus。下面嘅 `last_value` 指標顯示抓取時最新嘅池狀態。後面嘅壓力指標係從嗰啲 100 毫秒樣本得出嘅總和，即使飽和窗口喺下次抓取之前已經恢復，亦都更容易發現短時間嘅飽和情況。

### `tuist_repo_pool_checkout_queue_length`（最後值）{#tuist_repo_pool_checkout_queue_length-last_value}

排隊等待分配數據庫連接嘅數據庫查詢數量。

#### 標籤 {#tuist_repo_pool_checkout_queue_length-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出指標嘅存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_ready_conn_count`（最後值）{#tuist_repo_pool_ready_conn_count-last_value}

準備好分配給數據庫查詢嘅數據庫連接數量。

#### 標籤 {#tuist_repo_pool_ready_conn_count-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出指標嘅存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_size`（最後值）{#tuist_repo_pool_size-last_value}

池中配置嘅連接數量。

#### 標籤 {#tuist_repo_pool_size-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出指標嘅存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_total_samples_sum`（總和）{#tuist_repo_pool_checkout_queue_total_samples_sum-sum}

執行嘅 repo 池輪詢總數（每次輪詢增加 1）。計算繁忙或飢餓百分比時使用此值作為分母：`rate(busy_samples) / rate(total_samples)` 或 `rate(starved_samples) / rate(total_samples)`。

#### 標籤 {#tuist_repo_pool_checkout_queue_total_samples_sum-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出指標嘅存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_observed_sum`（總和）{#tuist_repo_pool_checkout_queue_observed_sum-sum}

跨 repo 池輪詢觀察到嘅排隊檢出請求總和。這有助於檢測可能無法僅從最新隊列長度樣本中看到嘅短暫池競爭爆發。

#### 標籤 {#tuist_repo_pool_checkout_queue_observed_sum-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出指標嘅存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_busy_samples_sum`（總和）{#tuist_repo_pool_checkout_queue_busy_samples_sum-sum}

至少有一個數據庫檢出請求喺隊列中等待嘅 repo 池輪詢次數。

#### 標籤 {#tuist_repo_pool_checkout_queue_busy_samples_total-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出指標嘅存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_starved_samples_sum`（總和）{#tuist_repo_pool_checkout_queue_starved_samples_sum-sum}

檢出請求排隊且無可用就緒連接嘅 repo 池輪詢次數。此處持續增加通常表示池已飽和。

#### 標籤 {#tuist_repo_pool_checkout_queue_starved_samples_total-tags}

| 標籤 | 描述 |
|--- | ---- |
| `repo` | 發出指標嘅存儲庫，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底層數據庫類型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_db_connection_connected`（計數器）{#tuist_repo_pool_db_connection_connected-counter}

已建立到數據庫嘅連接數量。

### `tuist_repo_pool_db_connection_disconnected`（計數器）{#tuist_repo_pool_db_connection_disconnected-counter}

已從數據庫斷開嘅連接數量。

#### 標籤 {#tuist_repo_pool_db_connection_connected_and_disconnected-tags}

| 標籤 | 描述 |
|--- | ---- |
| `tag` | 標識發出存儲庫嘅 DBConnection 偵聽器標籤。 |

## HTTP 指標 {#http-metrics}

一組與 Tuist 通過 HTTP 同其他服務交互相關嘅指標。

### `tuist_http_request_count`（計數器）{#tuist_http_request_count-last_value}

傳出 HTTP 請求嘅數量。

### `tuist_http_request_duration_nanosecond_sum`（總和）{#tuist_http_request_duration_nanosecond_sum-last_value}

傳出請求持續時間嘅總和（包括等待分配連接嘅時間）。

### `tuist_http_request_duration_nanosecond_bucket`（分佈）{#tuist_http_request_duration_nanosecond_bucket-distribution}
傳出請求持續時間嘅分佈（包括等待分配連接嘅時間）。

### `tuist_http_queue_count`（計數器）{#tuist_http_queue_count-counter}

從池中檢索到嘅請求數量。

### `tuist_http_queue_duration_nanoseconds_sum`（總和）{#tuist_http_queue_duration_nanoseconds_sum-sum}

從池中檢索連接所需嘅時間。

### `tuist_http_queue_idle_time_nanoseconds_sum`（總和）{#tuist_http_queue_idle_time_nanoseconds_sum-sum}

連接空閒等待被檢索嘅時間。

### `tuist_http_queue_duration_nanoseconds_bucket`（分佈）{#tuist_http_queue_duration_nanoseconds_bucket-distribution}

從池中檢索連接所需嘅時間。

### `tuist_http_queue_idle_time_nanoseconds_bucket`（分佈）{#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

連接空閒等待被檢索嘅時間。

### `tuist_http_connection_count`（計數器）{#tuist_http_connection_count-counter}

已建立嘅連接數量。

### `tuist_http_connection_duration_nanoseconds_sum`（總和）{#tuist_http_connection_duration_nanoseconds_sum-sum}

同主機建立連接所需嘅時間。

### `tuist_http_connection_duration_nanoseconds_bucket`（分佈）{#tuist_http_connection_duration_nanoseconds_bucket-distribution}

同主機建立連接所需時間嘅分佈。

### `tuist_http_send_count`（計數器）{#tuist_http_send_count-counter}

分配到池中連接後已發送嘅請求數量。

### `tuist_http_send_duration_nanoseconds_sum`（總和）{#tuist_http_send_duration_nanoseconds_sum-sum}

分配到池中連接後請求完成所需嘅時間。

### `tuist_http_send_duration_nanoseconds_bucket`（分佈）{#tuist_http_send_duration_nanoseconds_bucket-distribution}

分配到池中連接後請求完成所需時間嘅分佈。

### `tuist_http_receive_count`（計數器）{#tuist_http_receive_count-counter}

從已發送請求中收到嘅響應數量。

### `tuist_http_receive_duration_nanoseconds_sum`（總和）{#tuist_http_receive_duration_nanoseconds_sum-sum}

接收響應所花嘅時間。

### `tuist_http_receive_duration_nanoseconds_bucket`（分佈）{#tuist_http_receive_duration_nanoseconds_bucket-distribution}

接收響應所花時間嘅分佈。

### `tuist_http_queue_available_connections`（最新值）{#tuist_http_queue_available_connections-last_value}

隊列中可用嘅連接數量。

### `tuist_http_queue_in_use_connections`（最新值）{#tuist_http_queue_in_use_connections-last_value}

使用中嘅隊列連接數量。
