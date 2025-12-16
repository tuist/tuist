---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# 监控 {#telemetry}

您可以使用 [Prometheus](https://prometheus.io/) 和可视化工具（如
[Grafana](https://grafana.com/)）来收集 Tuist 服务器的指标数据，并创建满足您需求的定制化仪表板。Prometheus
指标通过 9091 端口的`/metrics` 端点提供服务。Prometheus 的
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
应设置为小于 10_000 秒（我们建议保持默认的 15 秒）。

## PostHog 分析 {#posthog-analytics}

Tuist 与 [PostHog](https://posthog.com/) 集成，提供用户行为分析和事件跟踪功能。这使您能够了解用户如何与您的 Tuist
服务器交互，跟踪功能使用情况，并深入了解用户在营销网站、仪表板和 API 文档中的行为模式。

### 配置 {#posthog-configuration}

PostHog 集成是可选的，可以通过设置相应的环境变量来启用。配置后，Tuist 将自动跟踪用户事件、页面浏览和用户行为路径。

| 环境变量                    | 描述                   | 必需  | 默认值 | 示例                                                |
| ----------------------- | -------------------- | --- | --- | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | 您的 PostHog 项目 API 密钥 | 没有  |     | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | PostHog API 端点 URL   | 没有  |     | `https://eu.i.posthog.com`                        |

::: info 分析功能启用
<!-- -->
只有同时配置了 `TUIST_POSTHOG_API_KEY` 和 `TUIST_POSTHOG_URL`
时，分析功能才会启用。如果缺少任一变量，将不会发送任何分析事件。
<!-- -->
:::

### 功能特性 {#posthog-features}

启用 PostHog 后，Tuist 会自动跟踪：

- **用户身份识别**：通过用户的唯一 ID 和邮箱地址来识别用户
- **用户别名**：通过账户名称为用户设置别名，便于识别
- **分组分析**：根据用户选择的项目和组织进行分组，实现细分分析
- **页面区域**：事件包含超级属性，指示生成事件的应用程序区域：
  - `marketing` - 来自营销页面和公共内容的事件
  - `dashboard` - 来自主应用仪表板和认证区域的事件
  - `api-docs` - 来自 API 文档页面的事件
- **页面浏览**：使用 Phoenix LiveView 自动跟踪页面导航
- **自定义事件**：用于功能使用和用户交互的应用程序特定事件

### 隐私注意事项 {#posthog-privacy}

- 对于已认证用户，PostHog 使用用户的唯一 ID 作为明确标识符，并包含其邮箱地址
- 对于匿名用户，PostHog 使用仅内存持久化来避免在本地存储数据
- 所有分析功能都尊重用户隐私，并遵循数据保护最佳实践
- PostHog 数据根据 PostHog 的隐私政策和您的配置进行处理

## Elixir 指标 {#elixir-metrics}

默认情况下，我们包含 Elixir 运行时、BEAM、Elixir 以及我们使用的一些库的指标。以下是您可以期望看到的一些指标：

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

我们建议查看这些页面，以了解有哪些可用的指标以及如何使用它们。

## 运行指标 {#runs-metrics}

与 Tuist 运行相关的一组指标。

### `tuist_runs_total` (计数器) {#tuist_runs_total-counter}

Tuist 运行的总次数。

#### 标签 {#tuist-runs-total-tags}

| 标签      | 描述                                  |
| ------- | ----------------------------------- |
| `名字`    | 运行的`tuist` 命令的名称，如`build`,`test` 等。 |
| `is_ci` | 布尔值，表示执行器是 CI 机器还是开发者机器。            |
| `地位`    | `0` （如果`成功）`,`1` （如果`失败）` 。         |

### `tuist_runs_duration_milliseconds` (直方图) {#tuist_runs_duration_milliseconds-histogram}

每次 tuist 运行的总持续时间（以毫秒为单位）。

#### 标签 {#tuist-runs-duration-miliseconds-tags}

| 标签      | 描述                                  |
| ------- | ----------------------------------- |
| `名字`    | 运行的`tuist` 命令的名称，如`build`,`test` 等。 |
| `is_ci` | 布尔值，表示执行器是 CI 机器还是开发者机器。            |
| `地位`    | `0` （如果`成功）`,`1` （如果`失败）` 。         |

## 缓存指标 {#cache-metrics}

与 Tuist 缓存相关的一组指标。

### `tuist_cache_events_total` (计数器) {#tuist_cache_events_total-counter}

二进制缓存事件的总数。

#### 标签 {#tuist-cache-events-total-tags}

| 标签           | 描述                                        |
| ------------ | ----------------------------------------- |
| `event_type` | 可以是 `local_hit`、`remote_hit` 或 `miss` 之一。 |

### `tuist_cache_uploads_total` (计数器) {#tuist_cache_uploads_total-counter}

上传到二进制缓存的次数。

### `tuist_cache_uploaded_bytes` (求和) {#tuist_cache_uploaded_bytes-sum}

上传到二进制缓存的总字节数。

### `tuist_cache_downloads_total` (计数器) {#tuist_cache_downloads_total-counter}

从二进制缓存下载的次数。

### `tuist_cache_downloaded_bytes` (求和) {#tuist_cache_downloaded_bytes-sum}

从二进制缓存下载的总字节数。

---

## 预览指标 {#previews-metrics}

与预览功能相关的一组指标。

### `tuist_previews_uploads_total` (求和) {#tuist_previews_uploads_total-counter}

上传的预览总数。

### `tuist_previews_downloads_total` (求和) {#tuist_previews_downloads_total-counter}

下载的预览总数。

---

## 存储指标 {#storage-metrics}

与在远程存储（如 S3）中存储构建产物相关的一组指标。

::: tip
<!-- -->
这些指标有助于了解存储操作的性能并识别潜在的瓶颈。
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (直方图) {#tuist_storage_get_object_size_size_bytes-histogram}

从远程存储获取的对象的大小（以字节为单位）。

#### 标签 {#tuist-storage-get-object-size-size-bytes-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |


### `tuist_storage_get_object_size_duration_miliseconds` (直方图) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

从远程存储获取对象大小的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-get-object-size-duration-miliseconds-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |


### `tuist_storage_get_object_size_count` (计数器) {#tuist_storage_get_object_size_count-counter}

从远程存储获取对象大小的次数。

#### 标签 {#tuist-storage-get-object-size-count-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |

### `tuist_storage_delete_all_objects_duration_milliseconds` (直方图) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

从远程存储删除所有对象的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| 标签     | 描述            |
| ------ | ------------- |
| `项目标题` | 删除对象的项目的项目标号。 |


### `tuist_storage_delete_all_objects_count` (计数器) {#tuist_storage_delete_all_objects_count-counter}

从远程存储删除所有项目对象的次数。

#### 标签 {#tuist-storage-delete-all-objects-count-tags}

| 标签     | 描述            |
| ------ | ------------- |
| `项目标题` | 删除对象的项目的项目标号。 |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (直方图) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

开始向远程存储上传的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |

### `tuist_storage_multipart_start_upload_duration_count` (计数器) {#tuist_storage_multipart_start_upload_duration_count-counter}

向远程存储开始上传的次数。

#### 标签 {#tuist-storage-multipart-start-upload-duration-count-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |


### `tuist_storage_get_object_as_string_duration_milliseconds` (直方图) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

从远程存储获取对象字符串的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |

### `tuist_storage_get_object_as_string_count` (计数) {#tuist_storage_get_object_as_string_count-count}

从远程存储获取对象字符串的次数。

#### 标签 {#tuist-storage-get-object-as-string-count-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |


### `tuist_storage_check_object_existence_duration_milliseconds` (直方图) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

检查远程存储中对象存在的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |

### `tuist_storage_check_object_existence_count` (计数) {#tuist_storage_check_object_existence_count-count}

检查远程存储中对象存在的次数。

#### 标签 {#tuist-storage-check-object-existence-count-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (直方图) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

为远程存储中的对象生成下载预签名 URL 的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |


### `tuist_storage_generate_download_presigned_url_count` (计数) {#tuist_storage_generate_download_presigned_url_count-count}

为远程存储中的对象生成下载预签名 URL 的次数。

#### 标签 {#tuist-storage-generate-download-presigned-url-count-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (直方图) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

为远程存储中的对象生成部分上传预签名 URL 的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |
| `零件编号`       | 上传对象的部件编号。    |
| `upload_id`  | 多部分上传的上传 ID。  |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (计数) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

为远程存储中的对象生成部分上传预签名 URL 的次数。

#### 标签 {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |
| `零件编号`       | 上传对象的部件编号。    |
| `upload_id`  | 多部分上传的上传 ID。  |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (直方图) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

完成向远程存储上传的持续时间（以毫秒为单位）。

#### 标签 {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |
| `upload_id`  | 多部分上传的上传 ID。  |


### `tuist_storage_multipart_complete_upload_count` (计数) {#tuist_storage_multipart_complete_upload_count-count}

完成向远程存储上传的总次数。

#### 标签 {#tuist-storage-multipart-complete-upload-count-tags}

| 标签           | 描述            |
| ------------ | ------------- |
| `object_key` | 对象在远程存储中的查找键。 |
| `upload_id`  | 多部分上传的上传 ID。  |

---

## 身份验证指标 {#authentication-metrics}

与身份验证相关的一组指标。

### `tuist_authentication_token_refresh_error_total` (计数器) {#tuist_authentication_token_refresh_error_total-counter}

令牌刷新错误的总数。

#### 标签 {#tuist-authentication-token-refresh-error-total-tags}

| 标签            | 描述                                                   |
| ------------- | ---------------------------------------------------- |
| `cli_version` | 遇到错误的 Tuist CLI 版本。                                  |
| `reason`      | 令牌刷新错误的原因，例如 `invalid_token_type` 或 `invalid_token`。 |

---

## 项目指标 {#projects-metrics}

与项目相关的一组指标。

### `tuist_projects_total` (最新值) {#tuist_projects_total-last_value}

项目的总数。

---

## 账户指标 {#accounts-metrics}

与账户（用户和组织）相关的一组指标。

### `tuist_accounts_organizations_total` (最新值) {#tuist_accounts_organizations_total-last_value}

组织的总数。

### `tuist_accounts_users_total` (最新值) {#tuist_accounts_users_total-last_value}

用户的总数。


## 数据库指标 {#database-metrics}

与数据库连接相关的一组指标。

### `tuist_repo_pool_checkout_queue_length` (最新值) {#tuist_repo_pool_checkout_queue_length-last_value}

在队列中等待分配数据库连接的数据库查询数量。

### `tuist_repo_pool_ready_conn_count` (最新值) {#tuist_repo_pool_ready_conn_count-last_value}

准备好分配给数据库查询的数据库连接数量。


### `tuist_repo_pool_db_connection_connected` (计数器) {#tuist_repo_pool_db_connection_connected-counter}

已建立到数据库的连接数量。

### `tuist_repo_pool_db_connection_disconnected` (计数器) {#tuist_repo_pool_db_connection_disconnected-counter}

已从数据库断开的连接数量。

## HTTP 指标 {#http-metrics}

与 Tuist 通过 HTTP 与其他服务交互相关的一组指标。

### `tuist_http_request_count` (计数器) {#tuist_http_request_count-last_value}

发出的 HTTP 请求的数量。

### `tuist_http_request_duration_nanosecond_sum` (求和) {#tuist_http_request_duration_nanosecond_sum-last_value}

发出请求的持续时间总和（包括等待分配到连接所花费的时间）。

### `tuist_http_request_duration_nanosecond_bucket` (分布) {#tuist_http_request_duration_nanosecond_bucket-distribution}
发出请求持续时间的分布（包括等待分配到连接所花费的时间）。

### `tuist_http_queue_count` (计数器) {#tuist_http_queue_count-counter}

从连接池中检索到的请求数量。

### `tuist_http_queue_duration_nanoseconds_sum` (求和) {#tuist_http_queue_duration_nanoseconds_sum-sum}

从连接池检索连接所需的时间。

### `tuist_http_queue_idle_time_nanoseconds_sum` (求和) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

连接空闲等待检索的时间。

### `tuist_http_queue_duration_nanoseconds_bucket` (分布) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

从连接池检索连接所需的时间。

### `tuist_http_queue_idle_time_nanoseconds_bucket` (分布) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

连接空闲等待检索的时间。

### `tuist_http_connection_count` (计数器) {#tuist_http_connection_count-counter}

已建立的连接数量。

### `tuist_http_connection_duration_nanoseconds_sum` (求和) {#tuist_http_connection_duration_nanoseconds_sum-sum}

与主机建立连接所需的时间。

### `tuist_http_connection_duration_nanoseconds_bucket` (分布) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

与主机建立连接所需时间的分布。

### `tuist_http_send_count` (计数器) {#tuist_http_send_count-counter}

一旦分配了来自连接池的连接后已发送的请求数量。

### `tuist_http_send_duration_nanoseconds_sum` (求和) {#tuist_http_send_duration_nanoseconds_sum-sum}

一旦分配了来自连接池的连接后请求完成所需的时间。

### `tuist_http_send_duration_nanoseconds_bucket` (分布) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

一旦分配了来自连接池的连接后请求完成所需时间的分布。

### `tuist_http_receive_count` (计数器) {#tuist_http_receive_count-counter}

从已发送请求收到的响应数量。

### `tuist_http_receive_duration_nanoseconds_sum` (求和) {#tuist_http_receive_duration_nanoseconds_sum-sum}

接收响应所花费的时间。

### `tuist_http_receive_duration_nanoseconds_bucket` (分布) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

接收响应所花费时间的分布。

### `tuist_http_queue_available_connections` (最新值) {#tuist_http_queue_available_connections-last_value}

队列中可用的连接数量。

### `tuist_http_queue_in_use_connections` (最新值) {#tuist_http_queue_in_use_connections-last_value}

正在使用的队列连接数量。
