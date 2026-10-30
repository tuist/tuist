---
{
  "title": "遥测",
  "titleTemplate": ":title | 自托管 | Server | 指南 | Tuist",
  "description": "通过 Prometheus 指标、OpenTelemetry 追踪和日志转发监控你的 Tuist 服务器。"
}
---
# 遥测 {#telemetry}

Tuist 提供三种互补的可观测性信号：**指标**（Prometheus）、**追踪**（OpenTelemetry）和 **日志**（兼容 Loki）。这三者均为可选，可以独立启用。

## 分布式追踪（OpenTelemetry）{#opentelemetry}

Tuist 支持使用 [OpenTelemetry](https://opentelemetry.io/) 进行分布式追踪。启用后，服务器会为 HTTP 请求（Phoenix 和 Bandit）、数据库查询（Ecto）、出站 HTTP 调用（Finch）以及 Broadway 消息处理发出追踪数据。这些追踪数据可帮助你了解请求延迟、识别慢查询，并跨服务跟踪请求。

### 配置 {#opentelemetry-configuration}

设置以下环境变量以启用追踪导出：

| 环境变量 | 描述 | 必填 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry Collector 的 gRPC 端点（例如 Grafana Alloy、Jaeger 或任何兼容 OTLP 的收集器） | 否 | | `http://localhost:4317` |

未设置此变量时，追踪功能处于禁用状态，不会增加任何开销。

### 已插桩的库 {#opentelemetry-instrumented-libraries}

启用追踪后，以下库会自动进行插桩：

- **Bandit** -- HTTP 服务器连接跨度
- **Phoenix** -- 请求生命周期跨度（控制器操作、LiveView）
- **Ecto** -- 带有查询元数据的数据库查询跨度
- **Finch** -- 出站 HTTP 客户端请求跨度
- **Broadway** -- 消息处理管道跨度

### 使用 Grafana Alloy 的示例设置 {#opentelemetry-alloy-example}

如果你使用 [Grafana Alloy](https://grafana.com/docs/alloy/latest/) 作为收集器，请将其配置为接收 OTLP 追踪数据并将其转发到你的追踪后端（例如 Grafana Cloud Tempo）：

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

然后设置 `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` 指向 Alloy 实例，例如 `http://alloy:4317`。

## 日志转发（Loki）{#log-forwarding}

Tuist 可以将应用日志转发到兼容 [Loki](https://grafana.com/oss/loki/) 的端点。这使你可以将日志与指标和追踪集中在一起，形成完整的可观测性视图。日志通过 Loki HTTP 推送 API（`/loki/api/v1/push`）推送，并包含 `app`、`env` 和 `level` 标签。

### 配置 {#log-forwarding-configuration}

| 环境变量 | 描述 | 必填 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_LOKI_URL` | 兼容 Loki 的推送 API 端点的基础 URL | 否 | | `http://localhost:3100` |

未设置此变量时，日志转发功能处于禁用状态。

### 使用 Grafana Alloy 的示例设置 {#log-forwarding-alloy-example}

Grafana Alloy 可以使用其 [`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/) 组件充当本地日志中继：

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

然后设置 `TUIST_LOKI_URL=http://alloy:3100`。

如果 Loki 实例暴露了推送 API，你也可以将 `TUIST_LOKI_URL` 直接指向该实例。

## Prometheus 指标 {#prometheus-metrics}

你可以使用 [Prometheus](https://prometheus.io/) 和诸如 [Grafana](https://grafana.com/) 的可视化工具来摄取 Tuist 服务器收集的指标，从而创建符合你需求的自定义仪表板。Prometheus 指标通过端口 9091 上的 `/metrics` 端点提供。Prometheus 的 [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) 应设置为小于 10_000 秒（我们建议设置为 30 秒，以在可观测性与指标摄取成本之间取得平衡）。

## 真实用户监控 {#real-user-monitoring}

Tuist 可以使用捆绑在所提供的 JavaScript 中的 [Grafana Faro](https://grafana.com/oss/faro/) Web SDK，报告来自营销网站、文档和仪表板的浏览器性能。它会捕获核心网页指标（包括最大内容绘制）、未捕获的错误和页面浏览量，并将这些数据发布到你运行的 [Faro 接收器](https://grafana.com/docs/alloy/latest/reference/components/faro/faro.receiver/)——例如 Grafana Alloy 中的 `faro.receiver` 组件，该组件会将数据转发到 Loki 和 Tempo。

### 配置 {#real-user-monitoring-configuration}

| 环境变量 | 描述 | 必填 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_FARO_COLLECTOR_URL` | 浏览器发布 Faro 负载的 URL | 否 | | `/-/faro` |

> [!NOTE]
> 仅当设置 `TUIST_FARO_COLLECTOR_URL` 时，真实用户监控才会启用。如果没有它，不会收集任何浏览器遥测数据，也不会加载任何第三方脚本。

使用同源路径（如 `/-/faro`）可以避免跨域请求，并保持浏览器的内容安全策略不变。通过你的入口网关将其指向你的 Faro 接收器。

### 收集的内容 {#real-user-monitoring-collected}

- **Web Vitals**：LCP、CLS、INP、FCP 和 TTFB，由浏览器自动捕获
- **页面浏览量**：在加载和 Phoenix LiveView 导航时记录
- **视图**：每个负载都携带生成它的部分——`marketing`、`docs`、`dashboard` 或 `api-docs`
- **错误**：未捕获的异常和未处理的 Promise 拒绝

### 隐私考量 {#real-user-monitoring-privacy}

- 不附加用户身份：负载中不包含用户 ID、电子邮件或账户信息
- 会话不会在访问之间持久化，因此不会向浏览器存储写入任何内容
- 控制台捕获处于关闭状态，因此应用日志输出绝不会从浏览器发送

## Elixir 指标 {#elixir-metrics}

默认情况下，我们包含 Elixir 运行时、BEAM、Elixir 以及我们使用的一些库的指标。以下是你可以看到的一些指标：

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

我们建议查看这些页面，了解有哪些可用指标以及如何使用它们。

## 运行指标 {#runs-metrics}

一组与 Tuist Runs 相关的指标。

### `tuist_runs_total`（计数器）{#tuist_runs_total-counter}

Tuist Runs 的总数。

#### 标签 {#tuist-runs-total-tags}

| 标签 | 描述 |
|--- | ---- |
| `name` | 运行的 `tuist` 命令的名称，例如 `build`、`test` 等。 |
| `is_ci` | 一个布尔值，指示执行者是 CI 还是开发人员的机器。 |
| `status` | `success` 成功时 `0`，`failure` 失败时 `1`。 |

### `tuist_runs_duration_milliseconds`（直方图）{#tuist_runs_duration_milliseconds-histogram}

每次 tuist 运行的总持续时间（以毫秒为单位）。

#### 标签 {#tuist-runs-duration-miliseconds-tags}

| 标签 | 描述 |
|--- | ---- |
| `name` | 运行的 `tuist` 命令的名称，例如 `build`、`test` 等。 |
| `is_ci` | 一个布尔值，指示执行者是 CI 还是开发人员的机器。 |
| `status` | `success` 成功时 `0`，`failure` 失败时 `1`。 |

## 缓存指标 {#cache-metrics}

一组与 Tuist Cache 相关的指标。

### `tuist_cache_events_total`（计数器）{#tuist_cache_events_total-counter}

二进制缓存事件的总数。

#### 标签 {#tuist-cache-events-total-tags}

| 标签 | 描述 |
|--- | ---- |
| `event_type` | 可以是 `local_hit`、`remote_hit` 或 `miss`。 |

### `tuist_cache_uploads_total`（计数器）{#tuist_cache_uploads_total-counter}

上传到二进制缓存的次数。

### `tuist_cache_uploaded_bytes`（总和）{#tuist_cache_uploaded_bytes-sum}

上传到二进制缓存的字节数。

### `tuist_cache_downloads_total`（计数器）{#tuist_cache_downloads_total-counter}

从二进制缓存下载的次数。

### `tuist_cache_downloaded_bytes`（总和）{#tuist_cache_downloaded_bytes-sum}

从二进制缓存下载的字节数。

---

## 预览指标 {#previews-metrics}

一组与预览功能相关的指标。

### `tuist_previews_uploads_total`（总和）{#tuist_previews_uploads_total-counter}

上传的预览总数。

### `tuist_previews_downloads_total`（总和）{#tuist_previews_downloads_total-counter}

下载的预览总数。

---

## 存储指标 {#storage-metrics}

一组与远程存储（例如 S3）中工件存储相关的指标。

> [!TIP]
> 这些指标有助于了解存储操作的性能并识别潜在瓶颈。


### `tuist_storage_get_object_size_size_bytes`（直方图）{#tuist_storage_get_object_size_size_bytes-histogram}

从远程存储获取的对象大小（以字节为单位）。

#### 标签 {#tuist-storage-get-object-size-size-bytes-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |


### `tuist_storage_get_object_size_duration_miliseconds`（直方图）{#tuist_storage_get_object_size_duration_miliseconds-histogram}

从远程存储获取对象大小的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-get-object-size-duration-miliseconds-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |


### `tuist_storage_get_object_size_count`（计数器）{#tuist_storage_get_object_size_count-counter}

从远程存储获取对象大小的次数。

#### 标签 {#tuist-storage-get-object-size-count-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |

### `tuist_storage_delete_all_objects_duration_milliseconds`（直方图）{#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

从远程存储删除所有对象的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| 标签 | 描述 |
|--- | ---- |
| `project_slug` | 其对象正在被删除的项目的项目 slug。 |


### `tuist_storage_delete_all_objects_count`（计数器）{#tuist_storage_delete_all_objects_count-counter}

从远程存储删除所有项目对象的次数。

#### 标签 {#tuist-storage-delete-all-objects-count-tags}

| 标签 | 描述 |
|--- | ---- |
| `project_slug` | 其对象正在被删除的项目的项目 slug。 |


### `tuist_storage_multipart_start_upload_duration_milliseconds`（直方图）{#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

开始上传到远程存储的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |

### `tuist_storage_multipart_start_upload_duration_count`（计数器）{#tuist_storage_multipart_start_upload_duration_count-counter}

开始上传到远程存储的次数。

#### 标签 {#tuist-storage-multipart-start-upload-duration-count-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |


### `tuist_storage_get_object_as_string_duration_milliseconds`（直方图）{#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

从远程存储以字符串形式获取对象的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |

### `tuist_storage_get_object_as_string_count`（计数）{#tuist_storage_get_object_as_string_count-count}

从远程存储以字符串形式获取对象的次数。

#### 标签 {#tuist-storage-get-object-as-string-count-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |


### `tuist_storage_check_object_existence_duration_milliseconds`（直方图）{#tuist_storage_check_object_existence_duration_milliseconds-histogram}

检查远程存储中对象存在性的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |

### `tuist_storage_check_object_existence_count`（计数）{#tuist_storage_check_object_existence_count-count}

检查远程存储中对象存在性的次数。

#### 标签 {#tuist-storage-check-object-existence-count-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds`（直方图）{#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

为远程存储中的对象生成下载预签名 URL 的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |


### `tuist_storage_generate_download_presigned_url_count`（计数）{#tuist_storage_generate_download_presigned_url_count-count}

为远程存储中的对象生成下载预签名 URL 的次数。

#### 标签 {#tuist-storage-generate-download-presigned-url-count-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds`（直方图）{#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

为远程存储中的对象生成分段上传预签名 URL 的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |
| `part_number` | 正在上传的对象的分段编号。 |
| `upload_id` | 分段上传的上传 ID。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count`（计数）{#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

为远程存储中的对象生成分段上传预签名 URL 的次数。

#### 标签 {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |
| `part_number` | 正在上传的对象的分段编号。 |
| `upload_id` | 分段上传的上传 ID。 |

### `tuist_storage_multipart_complete_upload_duration_milliseconds`（直方图）{#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

完成上传到远程存储的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |
| `upload_id` | 分段上传的上传 ID。 |


### `tuist_storage_multipart_complete_upload_count`（计数）{#tuist_storage_multipart_complete_upload_count-count}

完成上传到远程存储的总次数。

#### 标签 {#tuist-storage-multipart-complete-upload-count-tags}

| 标签 | 描述 |
|--- | ---- |
| `object_key` | 对象在远程存储中的查找键。 |
| `upload_id` | 分段上传的上传 ID。 |

---

## 身份验证指标 {#authentication-metrics}

一组与身份验证相关的指标。

### `tuist_authentication_token_refresh_error_total`（计数器）{#tuist_authentication_token_refresh_error_total-counter}

令牌刷新错误的总数。

#### 标签 {#tuist-authentication-token-refresh-error-total-tags}

| 标签 | 描述 |
|--- | ---- |
| `cli_version` | 遇到错误的 Tuist CLI 版本。 |
| `reason` | 令牌刷新错误的原因，例如 `invalid_token_type` 或 `invalid_token`。 |

---

## 项目指标 {#projects-metrics}

一组与项目相关的指标。

### `tuist_projects_total`（最新值）{#tuist_projects_total-last_value}

项目总数。

---

## 账户指标 {#accounts-metrics}

一组与账户（用户和组织）相关的指标。

### `tuist_accounts_organizations_total`（最新值）{#tuist_accounts_organizations_total-last_value}

组织总数。

### `tuist_accounts_users_total`（最新值）{#tuist_accounts_users_total-last_value}

用户总数。


## 数据库指标 {#database-metrics}

一组与数据库连接相关的指标。

仓库池指标在内部每 100 毫秒采样一次，然后通过 `/metrics` 暴露给 Prometheus。下面的 `last_value` 指标显示抓取时的最新池状态。后文的压力指标是从这些 100 毫秒样本中得出的总和，这使得即使在下次抓取之前已恢复的短暂饱和窗口也更容易被发现。

### `tuist_repo_pool_checkout_queue_length`（最新值）{#tuist_repo_pool_checkout_queue_length-last_value}

排队等待分配数据库连接的数据库查询数量。

#### 标签 {#tuist_repo_pool_checkout_queue_length-tags}

| 标签 | 描述 |
|--- | ---- |
| `repo` | 发出该指标的仓库，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底层数据库类型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_ready_conn_count`（最新值）{#tuist_repo_pool_ready_conn_count-last_value}

准备分配给数据库查询的数据库连接数量。

#### 标签 {#tuist_repo_pool_ready_conn_count-tags}

| 标签 | 描述 |
|--- | ---- |
| `repo` | 发出该指标的仓库，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底层数据库类型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_size`（最新值）{#tuist_repo_pool_size-last_value}

池中配置的连接数。

#### 标签 {#tuist_repo_pool_size-tags}

| 标签 | 描述 |
|--- | ---- |
| `repo` | 发出该指标的仓库，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底层数据库类型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_total_samples_sum`（总和）{#tuist_repo_pool_checkout_queue_total_samples_sum-sum}

执行的仓库池轮询总次数（每次轮询增加 1）。在计算忙碌率或饥饿率百分比时将其用作分母：`rate(busy_samples) / rate(total_samples)` 或 `rate(starved_samples) / rate(total_samples)`。

#### 标签 {#tuist_repo_pool_checkout_queue_total_samples_sum-tags}

| 标签 | 描述 |
|--- | ---- |
| `repo` | 发出该指标的仓库，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底层数据库类型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_observed_sum`（总和）{#tuist_repo_pool_checkout_queue_observed_sum-sum}

在仓库池轮询中观察到的排队检出请求的总和。这对于检测可能仅在最新队列长度样本中不可见的短暂池争用突发非常有用。

#### 标签 {#tuist_repo_pool_checkout_queue_observed_sum-tags}

| 标签 | 描述 |
|--- | ---- |
| `repo` | 发出该指标的仓库，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底层数据库类型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_busy_samples_sum`（总和）{#tuist_repo_pool_checkout_queue_busy_samples_sum-sum}

至少有一个数据库检出请求在队列中等待的仓库池轮询次数。

#### 标签 {#tuist_repo_pool_checkout_queue_busy_samples_total-tags}

| 标签 | 描述 |
|--- | ---- |
| `repo` | 发出该指标的仓库，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底层数据库类型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_checkout_queue_starved_samples_sum`（总和）{#tuist_repo_pool_checkout_queue_starved_samples_sum-sum}

检出请求排队且没有可用就绪连接的仓库池轮询次数。此处持续增加通常意味着池已饱和。

#### 标签 {#tuist_repo_pool_checkout_queue_starved_samples_total-tags}

| 标签 | 描述 |
|--- | ---- |
| `repo` | 发出该指标的仓库，例如 `postgres`、`clickhouse_read` 或 `clickhouse_write`。 |
| `database` | 底层数据库类型，例如 `postgres` 或 `clickhouse`。 |

### `tuist_repo_pool_db_connection_connected`（计数器）{#tuist_repo_pool_db_connection_connected-counter}

已建立到数据库的连接数。

### `tuist_repo_pool_db_connection_disconnected`（计数器）{#tuist_repo_pool_db_connection_disconnected-counter}

已从数据库断开的连接数。

#### 标签 {#tuist_repo_pool_db_connection_connected_and_disconnected-tags}

| 标签 | 描述 |
|--- | ---- |
| `tag` | 标识发出仓库的 DBConnection 监听器标签。 |

## HTTP 指标 {#http-metrics}

一组与 Tuist 通过 HTTP 与其他服务交互相关的指标。

### `tuist_http_request_count`（计数器）{#tuist_http_request_count-last_value}

发出的 HTTP 请求数量。

### `tuist_http_request_duration_nanosecond_sum`（总和）{#tuist_http_request_duration_nanosecond_sum-last_value}

发出请求的持续时间总和（包括等待分配连接的时间）。

### `tuist_http_request_duration_nanosecond_bucket`（分布）{#tuist_http_request_duration_nanosecond_bucket-distribution}
发出请求的持续时间分布（包括等待分配连接的时间）。

### `tuist_http_queue_count`（计数器）{#tuist_http_queue_count-counter}

从池中检索的请求数量。

### `tuist_http_queue_duration_nanoseconds_sum`（总和）{#tuist_http_queue_duration_nanoseconds_sum-sum}

从池中检索连接所需的时间。

### `tuist_http_queue_idle_time_nanoseconds_sum`（总和）{#tuist_http_queue_idle_time_nanoseconds_sum-sum}

连接空闲等待被检索的时间。

### `tuist_http_queue_duration_nanoseconds_bucket`（分布）{#tuist_http_queue_duration_nanoseconds_bucket-distribution}

从池中检索连接所需的时间。

### `tuist_http_queue_idle_time_nanoseconds_bucket`（分布）{#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

连接空闲等待被检索的时间。

### `tuist_http_connection_count`（计数器）{#tuist_http_connection_count-counter}

已建立的连接数。

### `tuist_http_connection_duration_nanoseconds_sum`（总和）{#tuist_http_connection_duration_nanoseconds_sum-sum}

与主机建立连接所需的时间。

### `tuist_http_connection_duration_nanoseconds_bucket`（分布）{#tuist_http_connection_duration_nanoseconds_bucket-distribution}

与主机建立连接所需时间的分布。

### `tuist_http_send_count`（计数器）{#tuist_http_send_count-counter}

分配到池中的连接后已发送的请求数量。

### `tuist_http_send_duration_nanoseconds_sum`（总和）{#tuist_http_send_duration_nanoseconds_sum-sum}

分配到池中的连接后请求完成所需的时间。

### `tuist_http_send_duration_nanoseconds_bucket`（分布）{#tuist_http_send_duration_nanoseconds_bucket-distribution}

分配到池中的连接后请求完成所需时间的分布。

### `tuist_http_receive_count`（计数器）{#tuist_http_receive_count-counter}

从已发送请求中收到的响应数量。

### `tuist_http_receive_duration_nanoseconds_sum`（总和）{#tuist_http_receive_duration_nanoseconds_sum-sum}

接收响应所花费的时间。

### `tuist_http_receive_duration_nanoseconds_bucket`（分布）{#tuist_http_receive_duration_nanoseconds_bucket-distribution}

接收响应所花费时间的分布。

### `tuist_http_queue_available_connections`（最新值）{#tuist_http_queue_available_connections-last_value}

队列中可用的连接数。

### `tuist_http_queue_in_use_connections`（最新值）{#tuist_http_queue_in_use_connections-last_value}

正在使用的队列连接数。
