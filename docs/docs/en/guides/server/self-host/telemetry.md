---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# Telemetry {#telemetry}

You can ingest metrics gathered by the Tuist server using [Prometheus](https://prometheus.io/) and a visualization tool such as [Grafana](https://grafana.com/) to create a custom dashboard tailored to your needs. The Prometheus metrics are served via the `/metrics` endpoint on port 9091. The Prometheus' [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) should be set as less than 10_000 seconds (we recommend keeping the default of 15 seconds).

## PostHog analytics {#posthog-analytics}

Tuist integrates with [PostHog](https://posthog.com/) for user behavior analytics and event tracking. This allows you to understand how users interact with your Tuist server, track feature usage, and gain insights into user behavior across the marketing site, dashboard, and API documentation.

### Configuration {#posthog-configuration}

PostHog integration is optional and can be enabled by setting the appropriate environment variables. When configured, Tuist will automatically track user events, page views, and user journeys.

| Environment variable | Description | Required | Default | Example |
| --- | --- | --- | --- | --- |
| `TUIST_POSTHOG_API_KEY` | Your PostHog project API key | No | | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL` | The PostHog API endpoint URL | No | | `https://eu.i.posthog.com` |

::: info ANALYTICS ENABLEMENT
<!-- -->
Analytics are only enabled when both `TUIST_POSTHOG_API_KEY` and `TUIST_POSTHOG_URL` are configured. If either variable is missing, no analytics events will be sent.
<!-- -->
:::

### Features {#posthog-features}

When PostHog is enabled, Tuist automatically tracks:

- **User identification**: Users are identified by their unique ID and email address
- **User aliasing**: Users are aliased by their account name for easier identification
- **Group analytics**: Users are grouped by their selected project and organization for segmented analytics
- **Page sections**: Events include super properties indicating which section of the application generated them:
  - `marketing` - Events from marketing pages and public content
  - `dashboard` - Events from the main application dashboard and authenticated areas  
  - `api-docs` - Events from API documentation pages
- **Page views**: Automatic tracking of page navigation using Phoenix LiveView
- **Custom events**: Application-specific events for feature usage and user interactions

### Privacy considerations {#posthog-privacy}

- For authenticated users, PostHog uses the user's unique ID as the distinct identifier and includes their email address
- For anonymous users, PostHog uses memory-only persistence to avoid storing data locally
- All analytics respect user privacy and follow data protection best practices
- PostHog data is processed according to PostHog's privacy policy and your configuration

## Elixir metrics {#elixir-metrics}

By default we include metrics of the Elixir runtime, BEAM, Elixir, and some of the libraries we use. The following are some of the metrics you can expect to see:

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

We recommend checking those pages to know which metrics are available and how to use them.

## Runs metrics {#runs-metrics}

A set of metrics related to Tuist Runs.

### `tuist_runs_total` (counter) {#tuist_runs_total-counter}

The total number of Tuist Runs.

#### Tags {#tuist-runs-total-tags}

| Tag | Description |
|--- | ---- |
| `name` | The name of the `tuist` command that was run, such as `build`, `test`, etc. |
| `is_ci` | A boolean indicating if the executor was a CI or a developer's machine. |
| `status` | `0` in case of `success`, `1` in case of `failure`. |

### `tuist_runs_duration_milliseconds` (histogram) {#tuist_runs_duration_milliseconds-histogram}

The total duration of each tuist run in milliseconds.

#### Tags {#tuist-runs-duration-miliseconds-tags}

| Tag | Description |
|--- | ---- |
| `name` | The name of the `tuist` command that was run, such as `build`, `test`, etc. |
| `is_ci` | A boolean indicating if the executor was a CI or a developer's machine. |
| `status` | `0` in case of `success`, `1` in case of `failure`. |

## Cache metrics {#cache-metrics}

A set of metrics related to the Tuist Cache.

### `tuist_cache_events_total` (counter) {#tuist_cache_events_total-counter}

The total number of binary cache events.

#### Tags {#tuist-cache-events-total-tags}

| Tag | Description |
|--- | ---- |
| `event_type` | Can be either of `local_hit`, `remote_hit`, or `miss`. |

### `tuist_cache_uploads_total` (counter) {#tuist_cache_uploads_total-counter}

The number of uploads to the binary cache.

### `tuist_cache_uploaded_bytes` (sum) {#tuist_cache_uploaded_bytes-sum}

The number of bytes uploaded to the binary cache.

### `tuist_cache_downloads_total` (counter) {#tuist_cache_downloads_total-counter}

The number of downloads to the binary cache.

### `tuist_cache_downloaded_bytes` (sum) {#tuist_cache_downloaded_bytes-sum}

The number of bytes downloaded from the binary cache.

---

## Previews metrics {#previews-metrics}

A set of metrics related to the previews feature.

### `tuist_previews_uploads_total` (sum) {#tuist_previews_uploads_total-counter}

The total number of previews uploaded.

### `tuist_previews_downloads_total` (sum) {#tuist_previews_downloads_total-counter}

The total number of previews downloaded.

---

## Storage metrics {#storage-metrics}

A set of metrics related to the storage of artifacts in a remote storage (e.g. s3).

::: tip
<!-- -->
These metrics are useful to understand the performance of the storage operations and to identify potential bottlenecks.
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (histogram) {#tuist_storage_get_object_size_size_bytes-histogram}

The size (in bytes) of an object fetched from the remote storage.

#### Tags {#tuist-storage-get-object-size-size-bytes-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |


### `tuist_storage_get_object_size_duration_miliseconds` (histogram) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

The duration (in milliseconds) of fetching an object size from the remote storage.

#### Tags {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |


### `tuist_storage_get_object_size_count` (counter) {#tuist_storage_get_object_size_count-counter}

The number of times an object size was fetched from the remote storage.

#### Tags {#tuist-storage-get-object-size-count-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (histogram) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

The duration (in milliseconds) of deleting all objects from the remote storage.

#### Tags {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Tag | Description |
|--- | ---- |
| `project_slug` | The project slug of the project whose objects are being deleted. |


### `tuist_storage_delete_all_objects_count` (counter) {#tuist_storage_delete_all_objects_count-counter}

The number of times all project objects were deleted from the remote storage.

#### Tags {#tuist-storage-delete-all-objects-count-tags}

| Tag | Description |
|--- | ---- |
| `project_slug` | The project slug of the project whose objects are being deleted. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

The duration (in milliseconds) of starting an upload to the remote storage.

#### Tags {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_multipart_start_upload_duration_count` (counter) {#tuist_storage_multipart_start_upload_duration_count-counter}

The number of times an upload was started to the remote storage.

#### Tags {#tuist-storage-multipart-start-upload-duration-count-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histogram) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

The duration (in milliseconds) of fetching an object as a string from the remote storage.

#### Tags {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_get_object_as_string_count` (count) {#tuist_storage_get_object_as_string_count-count}

The number of times an object was fetched as a string from the remote storage.

#### Tags {#tuist-storage-get-object-as-string-count-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |


### `tuist_storage_check_object_existence_duration_milliseconds` (histogram) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

The duration (in milliseconds) of checking the existence of an object in the remote storage.

#### Tags {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_check_object_existence_count` (count) {#tuist_storage_check_object_existence_count-count}

The number of times the existence of an object was checked in the remote storage.

#### Tags {#tuist-storage-check-object-existence-count-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

The duration (in milliseconds) of generating a download presigned URL for an object in the remote storage.

#### Tags {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |


### `tuist_storage_generate_download_presigned_url_count` (count) {#tuist_storage_generate_download_presigned_url_count-count}

The number of times a download presigned URL was generated for an object in the remote storage.

#### Tags {#tuist-storage-generate-download-presigned-url-count-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

The duration (in milliseconds) of generating a part upload presigned URL for an object in the remote storage.

#### Tags {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |
| `part_number` | The part number of the object being uploaded. |
| `upload_id` | The upload ID of the multipart upload. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

The number of times a part upload presigned URL was generated for an object in the remote storage.

#### Tags {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |
| `part_number` | The part number of the object being uploaded. |
| `upload_id` | The upload ID of the multipart upload. |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

The duration (in milliseconds) of completing an upload to the remote storage.

#### Tags {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |
| `upload_id` | The upload ID of the multipart upload. |


### `tuist_storage_multipart_complete_upload_count` (count) {#tuist_storage_multipart_complete_upload_count-count}

The total number of times an upload was completed to the remote storage.

#### Tags {#tuist-storage-multipart-complete-upload-count-tags}

| Tag | Description |
|--- | ---- |
| `object_key` | The lookup key of the object in the remote storage. |
| `upload_id` | The upload ID of the multipart upload. |

---

## Authentication metrics {#authentication-metrics}

A set of metrics related to authentication.

### `tuist_authentication_token_refresh_error_total` (counter) {#tuist_authentication_token_refresh_error_total-counter}

The total number of token refresh errors.

#### Tags {#tuist-authentication-token-refresh-error-total-tags}

| Tag | Description |
|--- | ---- |
| `cli_version` | The version of the Tuist CLI that encountered the error. |
| `reason` | The reason for the token refresh error, such as `invalid_token_type` or `invalid_token`. |

---

## Projects metrics {#projects-metrics}

A set of metrics related to the projects.

### `tuist_projects_total` (last_value) {#tuist_projects_total-last_value}

The total number of projects.

---

## Accounts metrics {#accounts-metrics}

A set of metrics related to accounts (users and organizations).

### `tuist_accounts_organizations_total` (last_value) {#tuist_accounts_organizations_total-last_value}

The total number of organizations.

### `tuist_accounts_users_total` (last_value) {#tuist_accounts_users_total-last_value}

The total number of users.


## Database metrics {#database-metrics}

A set of metrics related to the database connection.

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

The number of database queries that are sitting in a queue waiting to be assigned to a database connection.

### `tuist_repo_pool_ready_conn_count` (last_value) {#tuist_repo_pool_ready_conn_count-last_value}

The number of database connections that are ready to be assigned to a database query.


### `tuist_repo_pool_db_connection_connected` (counter) {#tuist_repo_pool_db_connection_connected-counter}

The number of connections that have been established to the database.

### `tuist_repo_pool_db_connection_disconnected` (counter) {#tuist_repo_pool_db_connection_disconnected-counter}

The number of connections that have been disconnected from the database.

## HTTP metrics {#http-metrics}

A set of metrics related to Tuist's interactions with other services via HTTP.

### `tuist_http_request_count` (counter) {#tuist_http_request_count-last_value}

The number of outgoing HTTP requests.

### `tuist_http_request_duration_nanosecond_sum` (sum) {#tuist_http_request_duration_nanosecond_sum-last_value}

The sum of the duration of the outgoing requests (including the time that they spent waiting to be assigned to a connection).

### `tuist_http_request_duration_nanosecond_bucket` (distribution) {#tuist_http_request_duration_nanosecond_bucket-distribution}
The distribution of the duration of outgoing requests (including the time that they spent waiting to be assigned to a connection).

### `tuist_http_queue_count` (counter) {#tuist_http_queue_count-counter}

The number of requests that have been retrieved from the pool.

### `tuist_http_queue_duration_nanoseconds_sum` (sum) {#tuist_http_queue_duration_nanoseconds_sum-sum}

The time it takes to retrieve a connection from the pool.

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

The time a connection has been idle waiting to be retrieved.

### `tuist_http_queue_duration_nanoseconds_bucket` (distribution) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

The time it takes to retrieve a connection from the pool.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (distribution) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

The time a connection has been idle waiting to be retrieved.

### `tuist_http_connection_count` (counter) {#tuist_http_connection_count-counter}

The number of connections that have been established.

### `tuist_http_connection_duration_nanoseconds_sum` (sum) {#tuist_http_connection_duration_nanoseconds_sum-sum}

The time it takes to establish a connection against a host.

### `tuist_http_connection_duration_nanoseconds_bucket` (distribution) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

The distribution of the time it takes to establish a connection against a host.

### `tuist_http_send_count` (counter) {#tuist_http_send_count-counter}

The number of requests that have been sent once assigned to a connection from the pool.

### `tuist_http_send_duration_nanoseconds_sum` (sum) {#tuist_http_send_duration_nanoseconds_sum-sum}

The time that it takes for requests to complete once assigned to a connection from the pool.

### `tuist_http_send_duration_nanoseconds_bucket` (distribution) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

The distribution of the time that it takes for requests to complete once assigned to a connection from the pool.

### `tuist_http_receive_count` (counter) {#tuist_http_receive_count-counter}

The number of responses that have been received from sent requests.

### `tuist_http_receive_duration_nanoseconds_sum` (sum) {#tuist_http_receive_duration_nanoseconds_sum-sum}

The time spent receiving responses.

### `tuist_http_receive_duration_nanoseconds_bucket` (distribution) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

The distribution of the time spent receiving responses.

### `tuist_http_queue_available_connections` (last_value) {#tuist_http_queue_available_connections-last_value}

The number of connections available in the queue.

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

The number of queue connections that are in use.
