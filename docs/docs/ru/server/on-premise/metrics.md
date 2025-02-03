---
title: Metrics
titleTemplate: :title | On-premise | Server | Tuist
description: Optimize your build times by caching compiled binaries and sharing them across different environments.
---

# Metrics {#metrics}

You can ingest metrics gathered by the Tuist server using [Prometheus](https://prometheus.io/) and a visualization tool such as [Grafana](https://grafana.com/) to create a custom dashboard tailored to your needs. The Prometheus metrics are served via the `/metrics` endpoint on port 9091. The Prometheus' [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) should be set as less than 10_000 seconds (we recommend keeping the default of 15 seconds).

## Elixir metrics {#elixir-metrics}

By default we include metrics of the Elixir runtime, [BEAM](https://en.wikipedia.org/wiki/BEAM_\\\\\\\\\\\\\\\\\\\\\\\(Erlang_virtual_machine\\\\\\\\\\\\\\\\\\\\\\\)), Elixir, and some of the libraries we use. The following are some of the metrics you can expect to see:

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

| Tag      | Description                                                                                 |
| -------- | ------------------------------------------------------------------------------------------- |
| `name`   | The name of the `tuist` command that was run, such as `build`, `test`, etc. |
| `is_ci`  | A boolean indicating if the executor was a CI or a developer's machine.     |
| `status` | `0` in case of `success`, `1` in case of `failure`.                         |

### `tuist_runs_duration_milliseconds` (histogram) {#tuist_runs_duration_milliseconds-histogram}

The total duration of each tuist run in milliseconds.

#### Tags {#tuist-runs-duration-miliseconds-tags}

| Tag      | Description                                                                                 |
| -------- | ------------------------------------------------------------------------------------------- |
| `name`   | The name of the `tuist` command that was run, such as `build`, `test`, etc. |
| `is_ci`  | A boolean indicating if the executor was a CI or a developer's machine.     |
| `status` | `0` in case of `success`, `1` in case of `failure`.                         |

## Cache metrics {#cache-metrics}

A set of metrics related to the Tuist Cache.

### `tuist_cache_events_total` (counter) {#tuist_cache_events_total-counter}

The total number of binary cache events.

#### Tags {#tuist-cache-events-total-tags}

| Tag          | Description                                                            |
| ------------ | ---------------------------------------------------------------------- |
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

> [!TIP]
> These metrics are useful to understand the performance of the storage operations and to identify potential bottlenecks.

### `tuist_storage_get_object_size_size_bytes` (histogram) {#tuist_storage_get_object_size_size_bytes-histogram}

The size (in bytes) of an object fetched from the remote storage.

#### Tags {#tuist-storage-get-object-size-size-bytes-tags}

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_get_object_size_duration_miliseconds` (histogram) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

The duration (in milliseconds) of fetching an object size from the remote storage.

#### Tags {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_get_object_size_count` (counter) {#tuist_storage_get_object_size_count-counter}

The number of times an object size was fetched from the remote storage.

#### Tags {#tuist-storage-get-object-size-count-tags}

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (histogram) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

The duration (in milliseconds) of deleting all objects from the remote storage.

#### Tags {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Tag            | Description                                                                      |
| -------------- | -------------------------------------------------------------------------------- |
| `project_slug` | The project slug of the project whose objects are being deleted. |

### `tuist_storage_delete_all_objects_count` (counter) {#tuist_storage_delete_all_objects_count-counter}

The number of times all project objects were deleted from the remote storage.

#### Tags {#tuist-storage-delete-all-objects-count-tags}

| Tag            | Description                                                                      |
| -------------- | -------------------------------------------------------------------------------- |
| `project_slug` | The project slug of the project whose objects are being deleted. |

### `tuist_storage_multipart_start_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

The duration (in milliseconds) of starting an upload to the remote storage.

#### Tags {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_multipart_start_upload_duration_count` (counter) {#tuist_storage_multipart_start_upload_duration_count-counter}

The number of times an upload was started to the remote storage.

#### Tags {#tuist-storage-multipart-start-upload-duration-count-tags}

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_get_object_as_string_duration_milliseconds` (histogram) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

The duration (in milliseconds) of fetching an object as a string from the remote storage.

#### Tags {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_get_object_as_string_count` (count) {#tuist_storage_get_object_as_string_count-count}

The number of times an object was fetched as a string from the remote storage.

#### Tags {#tuist-storage-get-object-as-string-count-tags}

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_check_object_existence_duration_milliseconds` (histogram) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

The duration (in milliseconds) of checking the existence of an object in the remote storage.

#### Tags {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_check_object_existence_count` (count) {#tuist_storage_check_object_existence_count-count}

The number of times the existence of an object was checked in the remote storage.

#### Tags {#tuist-storage-check-object-existence-count-tags}

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

The duration (in milliseconds) of generating a download presigned URL for an object in the remote storage.

#### Tags {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_generate_download_presigned_url_count` (count) {#tuist_storage_generate_download_presigned_url_count-count}

The number of times a download presigned URL was generated for an object in the remote storage.

#### Tags {#tuist-storage-generate-download-presigned-url-count-tags}

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

The duration (in milliseconds) of generating a part upload presigned URL for an object in the remote storage.

#### Tags {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Tag           | Description                                                         |
| ------------- | ------------------------------------------------------------------- |
| `object_key`  | The lookup key of the object in the remote storage. |
| `part_number` | The part number of the object being uploaded.       |
| `upload_id`   | The upload ID of the multipart upload.              |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

The number of times a part upload presigned URL was generated for an object in the remote storage.

#### Tags {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Tag           | Description                                                         |
| ------------- | ------------------------------------------------------------------- |
| `object_key`  | The lookup key of the object in the remote storage. |
| `part_number` | The part number of the object being uploaded.       |
| `upload_id`   | The upload ID of the multipart upload.              |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

The duration (in milliseconds) of completing an upload to the remote storage.

#### Tags {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |
| `upload_id`  | The upload ID of the multipart upload.              |

### `tuist_storage_multipart_complete_upload_count` (count) {#tuist_storage_multipart_complete_upload_count-count}

The total number of times an upload was completed to the remote storage.

#### Tags {#tuist-storage-multipart-complete-upload-count-tags}

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |
| `upload_id`  | The upload ID of the multipart upload.              |

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
