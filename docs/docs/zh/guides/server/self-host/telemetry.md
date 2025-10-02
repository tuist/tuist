---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# 遥测 {#telemetry}

您可以使用[Prometheus](https://prometheus.io/)和[Grafana](https://grafana.com/)等可视化工具摄取
Tuist 服务器收集的指标，创建符合您需求的自定义仪表盘。Prometheus 指标通过`/metrics` 端点提供，端口为 9091。Prometheus
的
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
应设置为小于 10_000 秒（建议保持默认值 15 秒）。

## 邮猪分析 {#posthog-analytics}

Tuist 与 [PostHog](https://posthog.com/) 集成，用于用户行为分析和事件跟踪。这样，您就可以了解用户如何与 Tuist
服务器交互、跟踪功能使用情况，并深入了解营销网站、仪表板和 API 文档中的用户行为。

### 配置 {#posthog-configuration}

PostHog 集成是可选的，可通过设置相应的环境变量启用。配置完成后，Tuist 将自动跟踪用户事件、页面浏览和用户旅程。

| 环境变量                    | 说明                   | 需要  | 默认值 | 示例                                                |
| ----------------------- | -------------------- | --- | --- | ------------------------------------------------- |
| `tuist_posthog_api_key` | 您的 PostHog 项目 API 密钥 | 没有  |     | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `tuist_posthog_url`     | PostHog API 端点 URL   | 没有  |     | `https://eu.i.posthog.com`                        |

> [只有同时配置`TUIST_POSTHOG_API_KEY` 和`TUIST_POSTHOG_URL`
> 时，才能启用分析功能。如果缺少其中一个变量，将不会发送分析事件。

### 特点 {#posthog-features}

启用 PostHog 后，Tuist 会自动跟踪：

- **用户识别** ：用户通过其独特的 ID 和电子邮件地址进行识别
- **用户别名** ：用户以账户名别名，以便于识别
- **分组分析** ：按选定的项目和组织对用户进行分组，以便进行细分分析
- **页面部分** ：事件包括超级属性，表明是应用程序的哪个部分生成的：
  - `营销` - 来自营销页面和公共内容的活动
  - `仪表板` - 来自主应用程序仪表板和认证区域的事件
  - `api-docs` - 来自 API 文档页面的事件
- **页面浏览** ：使用 Phoenix LiveView 自动跟踪页面导航
- **自定义事件** ：特定于应用程序的事件，用于功能使用和用户交互

### 隐私注意事项 {#posthog-privacy}

- 对于通过身份验证的用户，PostHog 使用用户的唯一 ID 作为不同的标识符，并包括其电子邮件地址
- 对于匿名用户，PostHog 使用纯内存持久性，以避免在本地存储数据
- 所有分析都尊重用户隐私，并遵循数据保护的最佳做法
- PostHog的数据将根据PostHog的隐私政策和您的配置进行处理。

## Elixir 指标 {#elixir-metrics}

默认情况下，我们包括 Elixir 运行时、BEAM、Elixir 和我们使用的一些库的指标。以下是你可以看到的一些指标：

- [应用](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)。
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [凤凰](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [凤凰 LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [欧班](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

我们建议查看这些页面，了解哪些指标可用以及如何使用。

## 运行指标 {#runs-metrics}

一套与 Tuist Runs 相关的指标。

### `tuist_runs_total` （计数器） {#tuist_runs_total-counter}

图易斯特运行总数。

#### 标签 {#tuist-runs-total-tags}

| 标签      | 说明                                  |
| ------- | ----------------------------------- |
| `名字`    | 运行的`tuist` 命令的名称，如`build`,`test` 等。 |
| `is_ci` | 布尔值，表示执行器是 CI 机器还是开发者机器。            |
| `地位`    | `0` （如果`成功）`,`1` （如果`失败）` 。         |

### `tuist_runs_duration_milliseconds` （直方图） {#tuist_runs_duration_milliseconds-histogram}

每个 tuist 运行的总持续时间（毫秒）。

#### 标签 {#tuist-runs-duration-miliseconds-tags}

| 标签      | 说明                                  |
| ------- | ----------------------------------- |
| `名字`    | 运行的`tuist` 命令的名称，如`build`,`test` 等。 |
| `is_ci` | 布尔值，表示执行器是 CI 机器还是开发者机器。            |
| `地位`    | `0` （如果`成功）`,`1` （如果`失败）` 。         |

## 缓存指标 {#cache-metrics}

一组与 Tuist 缓存相关的指标。

### `tuist_cache_events_total` (counter) {#tuist_cache_events_total-counter}

二进制高速缓存事件总数。

#### 标签 {#tuist-cache-events-total-tags}

| 标签     | 说明                                          |
| ------ | ------------------------------------------- |
| `事件类型` | 可以是`local_hit`,`remote_hit`, 或`miss` 中的任一个。 |

### `tuist_cache_uploads_total` (counter) {#tuist_cache_uploads_total-counter}

上传到二进制缓存的次数。

### `tuist_cache_uploaded_bytes` (sum) {#tuist_cache_uploaded_bytes-sum}

上传到二进制缓存的字节数。

### `tuist_cache_downloads_total` (counter) {#tuist_cache_downloads_total-counter}

下载到二进制缓存的次数。

### `tuist_cache_downloaded_bytes` (sum) {#tuist_cache_downloaded_bytes-sum}

从二进制缓存下载的字节数。

---

## 预览指标 {#previews-metrics}

一组与预览功能相关的指标。

### `tuist_previews_uploads_total` (sum) {#tuist_previews_uploads_total-counter}

上传的预览总数。

### `tuist_previews_downloads_total` (sum) {#tuist_previews_downloads_total-counter}

下载的预览总数。

---

## 存储指标 {#storage-metrics}

一组与在远程存储（如 s3）中存储人工制品相关的指标。

> [！提示] 这些指标有助于了解存储操作的性能，并找出潜在的瓶颈。

### `tuist_storage_get_object_size_size_bytes` (histogram) {#tuist_storage_get_object_size_size_bytes-histogram}

从远程存储器获取的对象的大小（以字节为单位）。

#### 标签 {#tuist-storage-get-object-size-size-bytes-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |


### `tuist_storage_get_object_size_duration_miliseconds` (histogram) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

从远程存储器获取对象大小的持续时间（毫秒）。

#### 标签 {#tuist-storage-get-object-size-duration-miliseconds-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |


### `tuist_storage_get_object_size_count` (counter) {#tuist_storage_get_object_size_count-counter}

从远程存储器获取对象大小的次数。

#### 标签 {#tuist-storage-get-object-size-count-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |

### `tuist_storage_delete_all_objects_duration_milliseconds` (histogram) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

从远程存储中删除所有对象的持续时间（毫秒）。

#### 标签 {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| 标签     | 说明            |
| ------ | ------------- |
| `项目标题` | 删除对象的项目的项目标号。 |


### `tuist_storage_delete_all_objects_count` (counter) {#tuist_storage_delete_all_objects_count-counter}

从远程存储中删除所有项目对象的次数。

#### 标签 {#tuist-storage-delete-all-objects-count-tags}

| 标签     | 说明            |
| ------ | ------------- |
| `项目标题` | 删除对象的项目的项目标号。 |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

开始向远程存储上传的持续时间（毫秒）。

#### 标签 {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |

### `tuist_storage_multipart_start_upload_duration_count` (counter) {#tuist_storage_multipart_start_upload_duration_count-counter}

开始向远程存储上传的次数。

#### 标签 {#tuist-storage-multipart-start-upload-duration-count-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histogram) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

从远程存储器获取字符串对象的持续时间（毫秒）。

#### 标签 {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |

### `tuist_storage_get_object_as_string_count` (count) {#tuist_storage_get_object_as_string_count-count}

从远程存储器以字符串形式获取对象的次数。

#### 标签 {#tuist-storage-get-object-as-string-count-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |


### `tuist_storage_check_object_existence_duration_milliseconds` （直方图） {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

检查远程存储中是否存在对象的持续时间（毫秒）。

#### 标签 {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |

### `tuist_storage_check_object_existence_count` (count) {#tuist_storage_check_object_existence_count-count}

在远程存储器中检查对象是否存在的次数。

#### 标签 {#tuist-storage-check-object-existence-count-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

为远程存储中的对象生成下载预指定 URL 的持续时间（毫秒）。

#### 标签 {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |


### `tuist_storage_generate_download_presigned_url_count` (count) {#tuist_storage_generate_download_presigned_url_count-count}

为远程存储中的对象生成下载预指定 URL 的次数。

#### 标签 {#tuist-storage-generate-download-presigned-url-count-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

为远程存储中的对象生成部分上传预指定 URL 的持续时间（毫秒）。

#### 标签 {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |
| `零件编号`       | 上传对象的部件编号。   |
| `上传`         | 多部分上传的上传 ID。 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

为远程存储中的对象生成部件上传预指定 URL 的次数。

#### 标签 {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |
| `零件编号`       | 上传对象的部件编号。   |
| `上传`         | 多部分上传的上传 ID。 |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

完成向远程存储上传的持续时间（毫秒）。

#### 标签 {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |
| `上传`         | 多部分上传的上传 ID。 |


### `tuist_storage_multipart_complete_upload_count` (count) {#tuist_storage_multipart_complete_upload_count-count}

向远程存储器上传的总次数。

#### 标签 {#tuist-storage-multipart-complete-upload-count-tags}

| 标签           | 说明           |
| ------------ | ------------ |
| `object_key` | 远程存储中对象的查找键。 |
| `上传`         | 多部分上传的上传 ID。 |

---

## 身份验证指标 {#authentication-metrics}

一组与身份验证相关的指标。

### `tuist_authentication_token_refresh_error_total` (counter) {#tuist_authentication_token_refresh_error_total-counter}

令牌刷新错误总数。

#### 标签 {#tuist-authentication-token-refresh-error-total-tags}

| 标签            | 说明                                                 |
| ------------- | -------------------------------------------------- |
| `cli_version` | 出现错误的 Tuist CLI 版本。                                |
| `理由`          | 令牌刷新错误的原因，如`invalid_token_type` 或`invalid_token` 。 |

---

## 项目指标 {#projects-metrics}

一组与项目相关的指标。

### `tuist_projects_total` (last_value) {#tuist_projects_total-last_value}

项目总数。

---

## 账户度量 {#accounts-metrics}

一组与账户（用户和组织）相关的指标。

### `tuist_accounts_organizations_total` (last_value) {#tuist_accounts_organizations_total-last_value}

组织总数。

### `tuist_accounts_users_total` (last_value) {#tuist_accounts_users_total-last_value}

用户总数。


## 数据库度量 {#database-metrics}

一组与数据库连接相关的指标。

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

在队列中等待分配给数据库连接的数据库查询次数。

### `tuist_repo_pool_ready_conn_count` (last_value) {#tuist_repo_pool_ready_conn_count-last_value}

准备分配给数据库查询的数据库连接数。


### `tuist_repo_pool_db_connection_connected` (counter) {#tuist_repo_pool_db_connection_connected-counter}

已建立的数据库连接数。

### `tuist_repo_pool_db_connection_disconnected` (counter) {#tuist_repo_pool_db_connection_disconnected-counter}

从数据库断开的连接数。

## HTTP 指标 {#http-metrics}

一组与 Tuist 通过 HTTP 与其他服务交互相关的指标。

### `tuist_http_request_count` (counter) {#tuist_http_request_count-last_value}

外发 HTTP 请求的数量。

### `tuist_http_request_duration_nanosecond_sum` (sum) {#tuist_http_request_duration_nanosecond_sum-last_value}

发出请求的持续时间总和（包括等待分配给连接的时间）。

### `tuist_http_request_duration_nanosecond_bucket` （分布） {#tuist_http_request_duration_nanosecond_bucket-distribution}
发出请求的持续时间分布（包括等待分配到连接的时间）。

### `tuist_http_queue_count` (counter) {#tuist_http_queue_count-counter}

从池中获取的请求数。

### `tuist_http_queue_duration_nanoseconds_sum` (sum) {#tuist_http_queue_duration_nanoseconds_sum-sum}

从连接池检索连接所需的时间。

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

连接空闲等待检索的时间。

### `tuist_http_queue_duration_nanoseconds_bucket` （分布） {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

从连接池检索连接所需的时间。

### `tuist_http_queue_idle_time_nanoseconds_bucket` (distribution) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

连接空闲等待检索的时间。

### `tuist_http_connection_count` (counter) {#tuist_http_connection_count-counter}

已建立的连接数。

### `tuist_http_connection_duration_nanoseconds_sum` (sum) {#tuist_http_connection_duration_nanoseconds_sum-sum}

与主机建立连接所需的时间。

### `tuist_http_connection_duration_nanoseconds_bucket` (distribution) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

与主机建立连接所需的时间分布。

### `tuist_http_send_count` (counter) {#tuist_http_send_count-counter}

分配给连接池中的连接后已发送的请求数。

### `tuist_http_send_duration_nanoseconds_sum` (sum) {#tuist_http_send_duration_nanoseconds_sum-sum}

请求分配给连接池中的连接后，请求完成所需的时间。

### `tuist_http_send_duration_nanoseconds_bucket` (distribution) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

将请求分配给池中的连接后，请求完成所需的时间分布。

### `tuist_http_receive_count` (counter) {#tuist_http_receive_count-counter}

从发送的请求中收到的回复数量。

### `tuist_http_receive_duration_nanoseconds_sum` (sum) {#tuist_http_receive_duration_nanoseconds_sum-sum}

接收回复的时间。

### `tuist_http_receive_duration_nanoseconds_bucket` (distribution) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

接收回复的时间分布。

### `tuist_http_queue_available_connections` (last_value) {#tuist_http_queue_available_connections-last_value}

队列中可用的连接数。

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

正在使用的队列连接数。
