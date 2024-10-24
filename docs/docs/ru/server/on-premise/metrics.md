---
title: Metrics
titleTemplate: :title | On-premise | Server | Tuist
description: Optimize your build times by caching compiled binaries and sharing them across different environments.
---

<h1 id="metrics">Metrics</h1>

You can ingest metrics gathered by the Tuist server using [Prometheus](https://prometheus.io/) and a visualization tool such as [Grafana](https://grafana.com/) to create a custom dashboard tailored to your needs. The Prometheus metrics are served via the `/metrics` endpoint on port 9091. The Prometheus' [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) should be set as less than 10_000 seconds (we recommend keeping the default of 15 seconds).

<h2 id="elixir-metrics">Elixir metrics</h2>

By default we include metrics of the Elixir runtime, [BEAM](https://en.wikipedia.org/wiki/BEAM_\\\(Erlang_virtual_machine\\\)), Elixir, and some of the libraries we use. The following are some of the metrics you can expect to see:

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

We recommend checking those pages to know which metrics are available and how to use them.

<h2 id="runs-metrics">Runs metrics</h2>

A set of metrics related to Tuist Runs.

<h3 id="tuist_runs_total-counter">`tuist_runs_total` (counter)</h3>

The total number of Tuist Runs.

<h4 id="tags">Tags</h4>

| Tag      | Description                                                                                 |
| -------- | ------------------------------------------------------------------------------------------- |
| `name`   | The name of the `tuist` command that was run, such as `build`, `test`, etc. |
| `is_ci`  | A boolean indicating if the executor was a CI or a developer's machine.     |
| `status` | `0` in case of `success`, `1` in case of `failure`.                         |

<h3 id="tuist_runs_duration_milliseconds-histogram">`tuist_runs_duration_milliseconds` (histogram)</h3>

The total duration of each tuist run in milliseconds.

<h4 id="tags">Tags</h4>

| Tag      | Description                                                                                 |
| -------- | ------------------------------------------------------------------------------------------- |
| `name`   | The name of the `tuist` command that was run, such as `build`, `test`, etc. |
| `is_ci`  | A boolean indicating if the executor was a CI or a developer's machine.     |
| `status` | `0` in case of `success`, `1` in case of `failure`.                         |

<h2 id="cache-metrics">Cache metrics</h2>

A set of metrics related to the Tuist Cache.

<h3 id="tuist_cache_events_total-counter">`tuist_cache_events_total` (counter)</h3>

The total number of Tuist Binary Cache events.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                            |
| ------------ | ---------------------------------------------------------------------- |
| `event_type` | Can be either of `local_hit`, `remote_hit`, or `miss`. |

---

<h2 id="storage-metrics">Storage metrics</h2>

A set of metrics related to the storage of artifacts in a remote storage (e.g. s3).

> [!TIP]
> These metrics are useful to understand the performance of the storage operations and to identify potential bottlenecks.

<h3 id="tuist_storage_get_object_size_size_bytes-histogram">`tuist_storage_get_object_size_size_bytes` (histogram)</h3>

The size (in bytes) of an object fetched from the remote storage.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

<h3 id="tuist_storage_get_object_size_duration_miliseconds-histogram">`tuist_storage_get_object_size_duration_miliseconds` (histogram)</h3>

The duration (in milliseconds) of fetching an object size from the remote storage.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

<h3 id="tuist_storage_get_object_size_count-counter">`tuist_storage_get_object_size_count` (counter)</h3>

The number of times an object size was fetched from the remote storage.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

<h3 id="tuist_storage_delete_all_objects_duration_milliseconds-histogram">`tuist_storage_delete_all_objects_duration_milliseconds` (histogram)</h3>

The duration (in milliseconds) of deleting all objects from the remote storage.

<h4 id="tags">Tags</h4>

| Tag            | Description                                                                      |
| -------------- | -------------------------------------------------------------------------------- |
| `project_slug` | The project slug of the project whose objects are being deleted. |

<h3 id="tuist_storage_delete_all_objects_count-counter">`tuist_storage_delete_all_objects_count` (counter)</h3>

The number of times all project objects were deleted from the remote storage.

<h4 id="tags">Tags</h4>

| Tag            | Description                                                                      |
| -------------- | -------------------------------------------------------------------------------- |
| `project_slug` | The project slug of the project whose objects are being deleted. |

<h3 id="tuist_storage_multipart_start_upload_duration_milliseconds-histogram">`tuist_storage_multipart_start_upload_duration_milliseconds` (histogram)</h3>

The duration (in milliseconds) of starting an upload to the remote storage.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

<h3 id="tuist_storage_multipart_start_upload_duration_count-counter">`tuist_storage_multipart_start_upload_duration_count` (counter)</h3>

The number of times an upload was started to the remote storage.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

<h3 id="tuist_storage_get_object_as_string_duration_milliseconds-histogram">`tuist_storage_get_object_as_string_duration_milliseconds` (histogram)</h3>

The duration (in milliseconds) of fetching an object as a string from the remote storage.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

<h3 id="tuist_storage_get_object_as_string_count-count">`tuist_storage_get_object_as_string_count` (count)</h3>

The number of times an object was fetched as a string from the remote storage.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

<h3 id="tuist_storage_check_object_existence_duration_milliseconds-histogram">`tuist_storage_check_object_existence_duration_milliseconds` (histogram)</h3>

The duration (in milliseconds) of checking the existence of an object in the remote storage.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

<h3 id="tuist_storage_check_object_existence_count-count">`tuist_storage_check_object_existence_count` (count)</h3>

The number of times the existence of an object was checked in the remote storage.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

<h3 id="tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram">`tuist_storage_generate_download_presigned_url_duration_milliseconds` (histogram)</h3>

The duration (in milliseconds) of generating a download presigned URL for an object in the remote storage.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

<h3 id="tuist_storage_generate_download_presigned_url_count-count">`tuist_storage_generate_download_presigned_url_count` (count)</h3>

The number of times a download presigned URL was generated for an object in the remote storage.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |

<h3 id="tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram">`tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histogram)</h3>

The duration (in milliseconds) of generating a part upload presigned URL for an object in the remote storage.

<h4 id="tags">Tags</h4>

| Tag           | Description                                                         |
| ------------- | ------------------------------------------------------------------- |
| `object_key`  | The lookup key of the object in the remote storage. |
| `part_number` | The part number of the object being uploaded.       |
| `upload_id`   | The upload ID of the multipart upload.              |

<h3 id="tuist_storage_multipart_generate_upload_part_presigned_url_count-count">`tuist_storage_multipart_generate_upload_part_presigned_url_count` (count)</h3>

The number of times a part upload presigned URL was generated for an object in the remote storage.

<h4 id="tags">Tags</h4>

| Tag           | Description                                                         |
| ------------- | ------------------------------------------------------------------- |
| `object_key`  | The lookup key of the object in the remote storage. |
| `part_number` | The part number of the object being uploaded.       |
| `upload_id`   | The upload ID of the multipart upload.              |

<h3 id="tuist_storage_multipart_complete_upload_duration_milliseconds-histogram">`tuist_storage_multipart_complete_upload_duration_milliseconds` (histogram)</h3>

The duration (in milliseconds) of completing an upload to the remote storage.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |
| `upload_id`  | The upload ID of the multipart upload.              |

<h3 id="tuist_storage_multipart_complete_upload_count-count">`tuist_storage_multipart_complete_upload_count` (count)</h3>

The total number of times an upload was completed to the remote storage.

<h4 id="tags">Tags</h4>

| Tag          | Description                                                         |
| ------------ | ------------------------------------------------------------------- |
| `object_key` | The lookup key of the object in the remote storage. |
| `upload_id`  | The upload ID of the multipart upload.              |
