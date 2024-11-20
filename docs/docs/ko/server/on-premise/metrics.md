---
title: Metrics
titleTemplate: :title | On-premise | Server | Tuist
description: 컴파일된 바이너리를 캐싱하고 다양한 환경 간에 공유하여 빌드 시간을 최적화하세요.
---

# 메트릭 {#metrics}

Tuist 서버에서 수집한 메트릭을 [Prometheus](https://prometheus.io/)를 통해 가져오고
[Grafana](https://grafana.com/)와 같은 시각화 도구를 활용하여 사용자 요구에 맞는 커스텀 대시보드를 생성할 수 있습니다. Prometheus 메트릭은 9091 port의 `/metrics` endpoint를 통해 제공됩니다. Prometheus의 [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)은 10,000초 미만으로 설정해야 합니다 (기본값인 15초로 유지할 것을 권장합니다).

## Elixir 메트릭 {#elixir-metrics}

기본적으로 Elixir 런타임, [BEAM](https://en.wikipedia.org/wiki/BEAM_\(Erlang_virtual_machine\)), Elixir, 그리고 사용하는 일부 라이브러리의 메트릭이 포함되어 있습니다. 다음은 확인할 수 있는 메트릭의 일부입니다:

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

We recommend checking those pages to know which metrics are available and how to use them.

## Runs 메트릭 {#runs-metrics}

Tuist run과 관련된 메트릭 모음입니다.

### `tuist_runs_total` (카운터) {#tuist_runs_total-counter}

Tuist Run의 총 실행 횟수.

#### Tags {#tuist-runs-total-tags}

| Tag      | Description                                                |
| -------- | ---------------------------------------------------------- |
| `name`   | `build`, `test` 등과 같이 실행된 `tuist` 명령어의 이름. |
| `is_ci`  | CI 또는 개발자의 머신에서 실행되었는 지를 나타내는 불리언 값.       |
| `status` | `성공` 시 `0`, `실패` 시 `1`                                     |

### `tuist_runs_duration_milliseconds` (히스토그램) {#tuist_runs_duration_milliseconds-histogram}

각 tuist run의 총 소요 시간(milliseconds).

#### Tags {#tuist-runs-duration-miliseconds-tags}

| Tag      | Description                                                |
| -------- | ---------------------------------------------------------- |
| `name`   | `build`, `test` 등과 같이 실행된 `tuist` 명령어의 이름. |
| `is_ci`  | CI 또는 개발자의 머신에서 실행되었는 지를 나타내는 불리언 값.       |
| `status` | `성공` 시 `0`, `실패` 시 `1`                                     |

## Cache 메트릭 {#cache-metrics}

Tuist Cache와 관련된 메트릭 모음입니다.

### `tuist_cache_events_total` (카운터) {#tuist_cache_events_total-counter}

Tuist Binary Cache 이벤트의 총 개수.

#### Tags {#tuist-cache-events-total-tags}

| Tag          | Description                            |
| ------------ | -------------------------------------- |
| `event_type` | `local_hit`, `remote_hit`, `miss` 중 하나 |

---

## Storage 메트릭 {#storage-metrics}

원격 스토리지(예: s3)에 아티팩트를 저장하는 것과 관련된 메트릭 모음.

> [!TIP]
> 이 메트릭은 스토리지의 작업 성능을 이해하고 잠재적인 병목 현상을 식별하는데 유용합니다.

### `tuist_storage_get_object_size_size_bytes` (히스토그램) {#tuist_storage_get_object_size_size_bytes-histogram}

The size (in bytes) of an object fetched from the remote storage.

#### Tags {#tuist-storage-get-object-size-size-bytes-tags}

| Tag          | Description                                                                      |
| ------------ | -------------------------------------------------------------------------------- |
| `object_key` | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |

### `tuist_storage_get_object_size_duration_miliseconds` (히스토그램) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

The duration (in milliseconds) of fetching an object size from the remote storage.

#### Tags {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Tag          | Description                                                                      |
| ------------ | -------------------------------------------------------------------------------- |
| `object_key` | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |

### `tuist_storage_get_object_size_count` (카운터) {#tuist_storage_get_object_size_count-counter}

원격 스토리지(remote storage)에서 객체(object) 크기를 가져온 횟수.

#### Tags {#tuist-storage-get-object-size-count-tags}

| Tag          | Description                                                                      |
| ------------ | -------------------------------------------------------------------------------- |
| `object_key` | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |

### `tuist_storage_delete_all_objects_duration_milliseconds` (히스토그램) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

The duration (in milliseconds) of deleting all objects from the remote storage.

#### Tags {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Tag            | Description                                                                      |
| -------------- | -------------------------------------------------------------------------------- |
| `project_slug` | The project slug of the project whose objects are being deleted. |

### `tuist_storage_delete_all_objects_count` (카운터) {#tuist_storage_delete_all_objects_count-counter}

The number of times all project objects were deleted from the remote storage.

#### Tags {#tuist-storage-delete-all-objects-count-tags}

| Tag            | Description                                                                      |
| -------------- | -------------------------------------------------------------------------------- |
| `project_slug` | The project slug of the project whose objects are being deleted. |

### `tuist_storage_multipart_start_upload_duration_milliseconds` (히스토그램) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

The duration (in milliseconds) of starting an upload to the remote storage.

#### Tags {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Tag          | Description                                                                      |
| ------------ | -------------------------------------------------------------------------------- |
| `object_key` | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |

### `tuist_storage_multipart_start_upload_duration_count` (카운터) {#tuist_storage_multipart_start_upload_duration_count-counter}

The number of times an upload was started to the remote storage.

#### Tags {#tuist-storage-multipart-start-upload-duration-count-tags}

| Tag          | Description                                                                      |
| ------------ | -------------------------------------------------------------------------------- |
| `object_key` | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |

### `tuist_storage_get_object_as_string_duration_milliseconds` (히스토그램) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

The duration (in milliseconds) of fetching an object as a string from the remote storage.

#### Tags {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Tag          | Description                                                                      |
| ------------ | -------------------------------------------------------------------------------- |
| `object_key` | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |

### `tuist_storage_get_object_as_string_count` (횟수) {#tuist_storage_get_object_as_string_count-count}

The number of times an object was fetched as a string from the remote storage.

#### Tags {#tuist-storage-get-object-as-string-count-tags}

| Tag          | Description                                                                      |
| ------------ | -------------------------------------------------------------------------------- |
| `object_key` | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |

### `tuist_storage_check_object_existence_duration_milliseconds` (히스토그램) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

The duration (in milliseconds) of checking the existence of an object in the remote storage.

#### Tags {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Tag          | Description                                                                      |
| ------------ | -------------------------------------------------------------------------------- |
| `object_key` | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |

### `tuist_storage_check_object_existence_count` (횟수) {#tuist_storage_check_object_existence_count-count}

The number of times the existence of an object was checked in the remote storage.

#### Tags {#tuist-storage-check-object-existence-count-tags}

| Tag          | Description                                                                      |
| ------------ | -------------------------------------------------------------------------------- |
| `object_key` | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (히스토그램) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

The duration (in milliseconds) of generating a download presigned URL for an object in the remote storage.

#### Tags {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Tag          | Description                                                                      |
| ------------ | -------------------------------------------------------------------------------- |
| `object_key` | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |

### `tuist_storage_generate_download_presigned_url_count` (횟수) {#tuist_storage_generate_download_presigned_url_count-count}

The number of times a download presigned URL was generated for an object in the remote storage.

#### Tags {#tuist-storage-generate-download-presigned-url-count-tags}

| Tag          | Description                                                                      |
| ------------ | -------------------------------------------------------------------------------- |
| `object_key` | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (히스토그램) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

The duration (in milliseconds) of generating a part upload presigned URL for an object in the remote storage.

#### Tags {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Tag           | Description                                                                      |
| ------------- | -------------------------------------------------------------------------------- |
| `object_key`  | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |
| `part_number` | 업로드 중인 객체(object)의 파트 번호                                      |
| `upload_id`   | multipart 업로드의 upload ID                                                         |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (횟수) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

The number of times a part upload presigned URL was generated for an object in the remote storage.

#### Tags {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Tag           | Description                                                                      |
| ------------- | -------------------------------------------------------------------------------- |
| `object_key`  | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |
| `part_number` | 업로드 중인 객체(object)의 파트 번호                                      |
| `upload_id`   | multipart 업로드의 upload ID                                                         |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (히스토그램) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

The duration (in milliseconds) of completing an upload to the remote storage.

#### Tags {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Tag          | Description                                                                      |
| ------------ | -------------------------------------------------------------------------------- |
| `object_key` | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |
| `upload_id`  | multipart 업로드의 upload ID                                                         |

### `tuist_storage_multipart_complete_upload_count` (횟수) {#tuist_storage_multipart_complete_upload_count-count}

원격 스토리지(remote storage)로 업로드가 완료된 총 횟수.

#### Tags {#tuist-storage-multipart-complete-upload-count-tags}

| Tag          | Description                                                                      |
| ------------ | -------------------------------------------------------------------------------- |
| `object_key` | 원격 스토리지(remote storage)에서 객체(object)의 조회 키 |
| `upload_id`  | multipart 업로드의 upload ID                                                         |
