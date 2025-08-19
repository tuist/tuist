---
{
  "title": "Metrics",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "컴파일된 바이너리를 캐싱하고 다양한 환경 간에 공유하여 빌드 시간을 최적화하세요."
}
---
# 메트릭 {#metrics}

Tuist 서버에서 수집한 메트릭을 [Prometheus](https://prometheus.io/)를 통해 가져오고
[Grafana](https://grafana.com/)와 같은 시각화 도구를 활용하여 사용자 요구에 맞는 커스텀 대시보드를 생성할 수 있습니다. Prometheus 메트릭은 9091 port의 `/metrics` endpoint를 통해 제공됩니다. Prometheus의 [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)은 10,000초 미만으로 설정해야 합니다 (기본 값인 15 초로 유지할 것을 권장합니다).

## Elixir 메트릭 {#elixir-metrics}

기본적으로 Elixir 런타임, BEAM, Elixir, 그리고 사용하는 일부 라이브러리의 메트릭이 포함되어 있습니다. 다음은 확인할 수 있는 메트릭의 일부입니다:

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

바이너리 캐시 이벤트의 총 개수.

#### Tags {#tuist-cache-events-total-tags}

| Tag          | Description                            |
| ------------ | -------------------------------------- |
| `event_type` | `local_hit`, `remote_hit`, `miss` 중 하나 |

### `tuist_cache_uploads_total` (카운터) {#tuist_cache_uploads_total-counter}

바이너리 캐시 업로드 개수.

### `tuist_cache_uploaded_bytes` (합) {#tuist_cache_uploaded_bytes-sum}

바이너리 캐시에 업로드된 바이트 수.

### `tuist_cache_downloads_total` (카운터) {#tuist_cache_downloads_total-counter}

바이너리 캐시에 다운로드 수.

### `tuist_cache_downloaded_bytes` (합) {#tuist_cache_downloaded_bytes-sum}

바이너리 캐시로 부터 다운로드된 바이트 수.

---

## Preview 메트릭 {#previews-metrics}

프리뷰 기능과 관련된 메트릭 모음입니다.

### `tuist_previews_uploads_total` (합) {#tuist_previews_uploads_total-counter}

업로드된 프리뷰의 수.

### `tuist_previews_downloads_total` (합) {#tuist_previews_downloads_total-counter}

다운로드된 프리뷰의 수.

---

## Storage 메트릭 {#storage-metrics}

remote storage(예: s3)에 아티팩트를 저장하는 것과 관련된 메트릭 모음.

> [!TIP]
> 이 메트릭은 storage의 작업 성능을 이해하고 잠재적인 병목 현상을 식별하는데 유용합니다.

### `tuist_storage_get_object_size_size_bytes` (히스토그램) {#tuist_storage_get_object_size_size_bytes-histogram}

remote storage에서 가져온 object의 크기(byte)

#### Tags {#tuist-storage-get-object-size-size-bytes-tags}

| Tag          | Description                   |
| ------------ | ----------------------------- |
| `object_key` | remote storage에서 object의 조회 키 |

### `tuist_storage_get_object_size_duration_miliseconds` (히스토그램) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

remote storage에서 object의 크기를 가져오는 데 소요된 시간(milliseconds)

#### Tags {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Tag          | Description                   |
| ------------ | ----------------------------- |
| `object_key` | remote storage에서 object의 조회 키 |

### `tuist_storage_get_object_size_count` (카운터) {#tuist_storage_get_object_size_count-counter}

remote storage에서 object 크기를 가져온 횟수.

#### Tags {#tuist-storage-get-object-size-count-tags}

| Tag          | Description                   |
| ------------ | ----------------------------- |
| `object_key` | remote storage에서 object의 조회 키 |

### `tuist_storage_delete_all_objects_duration_milliseconds` (히스토그램) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

remote storage에서 모든 object를 삭제하는 데 소요된 시간(milliseconds)

#### Tags {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Tag            | Description                                          |
| -------------- | ---------------------------------------------------- |
| `project_slug` | object가 삭제되는 프로젝트의 프로젝트 슬러그(slug) |

### `tuist_storage_delete_all_objects_count` (카운터) {#tuist_storage_delete_all_objects_count-counter}

remote storage에서 프로젝트의 모든 object가 삭제된 횟수

#### Tags {#tuist-storage-delete-all-objects-count-tags}

| Tag            | Description                                          |
| -------------- | ---------------------------------------------------- |
| `project_slug` | object가 삭제되는 프로젝트의 프로젝트 슬러그(slug) |

### `tuist_storage_multipart_start_upload_duration_milliseconds` (히스토그램) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

remote storage로 업로드를 시작하는 데 소요된 시간(milliseconds)

#### Tags {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Tag          | Description                   |
| ------------ | ----------------------------- |
| `object_key` | remote storage에서 object의 조회 키 |

### `tuist_storage_multipart_start_upload_duration_count` (카운터) {#tuist_storage_multipart_start_upload_duration_count-counter}

remote storage로 업로드가 시작된 횟수

#### Tags {#tuist-storage-multipart-start-upload-duration-count-tags}

| Tag          | Description                   |
| ------------ | ----------------------------- |
| `object_key` | remote storage에서 object의 조회 키 |

### `tuist_storage_get_object_as_string_duration_milliseconds` (히스토그램) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

remote storage에서 object를 문자열로 가져오는 데 소요된 시간(milliseconds)

#### Tags {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Tag          | Description                   |
| ------------ | ----------------------------- |
| `object_key` | remote storage에서 object의 조회 키 |

### `tuist_storage_get_object_as_string_count` (횟수) {#tuist_storage_get_object_as_string_count-count}

remote storage에서 객체를 문자열로 가져온 횟수

#### Tags {#tuist-storage-get-object-as-string-count-tags}

| Tag          | Description                   |
| ------------ | ----------------------------- |
| `object_key` | remote storage에서 object의 조회 키 |

### `tuist_storage_check_object_existence_duration_milliseconds` (히스토그램) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

remote storage에서 object의 존재 여부를 확인하는 데 소요된 시간(milliseconds)

#### Tags {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Tag          | Description                   |
| ------------ | ----------------------------- |
| `object_key` | remote storage에서 object의 조회 키 |

### `tuist_storage_check_object_existence_count` (횟수) {#tuist_storage_check_object_existence_count-count}

remote storage에서 object의 존재 여부를 확인한 횟수

#### Tags {#tuist-storage-check-object-existence-count-tags}

| Tag          | Description                   |
| ------------ | ----------------------------- |
| `object_key` | remote storage에서 object의 조회 키 |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (히스토그램) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

remote storage에서 object의 download presigned URL을 생성하는 데 소요된 시간(milliseconds)

#### Tags {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Tag          | Description                   |
| ------------ | ----------------------------- |
| `object_key` | remote storage에서 object의 조회 키 |

### `tuist_storage_generate_download_presigned_url_count` (횟수) {#tuist_storage_generate_download_presigned_url_count-count}

remote storage에서 object의 download presigned URL이 생성된 횟수

#### Tags {#tuist-storage-generate-download-presigned-url-count-tags}

| Tag          | Description                   |
| ------------ | ----------------------------- |
| `object_key` | remote storage에서 object의 조회 키 |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (히스토그램) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

remote storage에서 object의 part upload presigned URL을 생성하는 데 소요된 시간(milliseconds)

#### Tags {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Tag           | Description                   |
| ------------- | ----------------------------- |
| `object_key`  | remote storage에서 object의 조회 키 |
| `part_number` | 업로드 중인 object의 part number    |
| `upload_id`   | multipart upload의 upload ID  |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (횟수) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

remote storage에서 object의 part upload presigned URL이 생성된 횟수

#### Tags {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Tag           | Description                   |
| ------------- | ----------------------------- |
| `object_key`  | remote storage에서 object의 조회 키 |
| `part_number` | 업로드 중인 object의 part number    |
| `upload_id`   | multipart upload의 upload ID  |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (히스토그램) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

remote storage로 업로드를 완료하는 데 소요된 시간(milliseconds)

#### Tags {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Tag          | Description                   |
| ------------ | ----------------------------- |
| `object_key` | remote storage에서 object의 조회 키 |
| `upload_id`  | multipart upload의 upload ID  |

### `tuist_storage_multipart_complete_upload_count` (횟수) {#tuist_storage_multipart_complete_upload_count-count}

remote storage로 업로드가 완료된 총 횟수.

#### Tags {#tuist-storage-multipart-complete-upload-count-tags}

| Tag          | Description                   |
| ------------ | ----------------------------- |
| `object_key` | remote storage에서 object의 조회 키 |
| `upload_id`  | multipart upload의 upload ID  |

---

## 프로젝트 메트릭 {#projects-metrics}

프로젝트와 관련된 메트릭 모음입니다.

### `tuist_projects_total` (last_value) {#tuist_projects_total-last_value}

프로젝트의 수.

---

## 계정 메트릭 {#accounts-metrics}

계정 (사용자와 조직) 과 관련된 메트릭 모음입니다.

### `tuist_accounts_organizations_total` (last_value) {#tuist_accounts_organizations_total-last_value}

조직의 총 수.

### `tuist_accounts_users_total` (last_value) {#tuist_accounts_users_total-last_value}

사용자의 총 수.

## 데이터베이스 메트릭 {#database-metrics}

데이터베이스 연결과 관련된 메트릭입니다.

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

데이터베이스 연결에 할당되기를 기다리며 큐에 대기 중인 데이터베이스 쿼리 수입니다.

### `tuist_repo_pool_ready_conn_count` (last_value) {#tuist_repo_pool_ready_conn_count-last_value}

데이터베이스 쿼리에 할당될 준비가 된 데이터베이스 연결 수입니다.

### `tuist_repo_pool_db_connection_connected` (counter) {#tuist_repo_pool_db_connection_connected-counter}

데이터베이스에 설정된 연결 수입니다.

### `tuist_repo_pool_db_connection_disconnected` (counter) {#tuist_repo_pool_db_connection_disconnected-counter}

데이터베이스에서 해제된 연결 수입니다.

## HTTP 메트릭 {#http-metrics}

Tuist가 다른 서비스와 HTTP를 통해 상호작용할 때 관련된 메트릭의 집합

### `tuist_http_request_count` (counter) {#tuist_http_request_count-last_value}

HTTP 요청 수

### `tuist_http_request_duration_nanosecond_sum` (sum) {#tuist_http_request_duration_nanosecond_sum-last_value}

요청에 대한 전체 시간 합계(연결에 할당되기까지 대기한 시간 포함)

### `tuist_http_request_duration_nanosecond_bucket` (distribution) {#tuist_http_request_duration_nanosecond_bucket-distribution}

요청에 대한 지속 시간 분포(연결에 할당되기까지 대기한 시간 포함)

### `tuist_http_queue_count` (counter) {#tuist_http_queue_count-counter}

풀에서 가져온 요청 수

### `tuist_http_queue_duration_nanoseconds_sum` (sum) {#tuist_http_queue_duration_nanoseconds_sum-sum}

풀에서 연결을 가져오는데 걸리는 시간

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

풀에서 연결을 가져올 때 유휴 상태로 있던 시간

### `tuist_http_queue_duration_nanoseconds_bucket` (distribution) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

풀에서 연결을 가져오는데 걸리는 시간

### `tuist_http_queue_idle_time_nanoseconds_bucket` (distribution) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

풀에서 연결을 가져올 때 유휴 상태로 있던 시간

### `tuist_http_connection_count` (counter) {#tuist_http_connection_count-counter}

설정된 연결 수

### `tuist_http_connection_duration_nanoseconds_sum` (sum) {#tuist_http_connection_duration_nanoseconds_sum-sum}

호스트와의 연결을 설정하는데 걸리는 시간

### `tuist_http_connection_duration_nanoseconds_bucket` (distribution) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

호스트와의 연결을 설정하는데 걸리는 시간 분포

### `tuist_http_send_count` (counter) {#tuist_http_send_count-counter}

풀에서 연결이 할당된 후에 전송된 요청 수

### `tuist_http_send_duration_nanoseconds_sum` (sum) {#tuist_http_send_duration_nanoseconds_sum-sum}

풀에서 연결이 할당된 후에 요청이 완료되기까지의 시간

### `tuist_http_send_duration_nanoseconds_bucket` (distribution) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

풀에서 연결이 할당된 후에 요청이 완료되기까지의 시간 분포

### `tuist_http_receive_count` (counter) {#tuist_http_receive_count-counter}

전송된 요청으로부터 수신된 응답 수

### `tuist_http_receive_duration_nanoseconds_sum` (sum) {#tuist_http_receive_duration_nanoseconds_sum-sum}

응답을 수신하는데 걸리는 시간

### `tuist_http_receive_duration_nanoseconds_bucket` (distribution) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

응답을 수신하는데 걸리는 시간 분포

### `tuist_http_queue_available_connections` (last_value) {#tuist_http_queue_available_connections-last_value}

큐에서 사용 가능한 연결 수

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

큐에서 사용 중인 연결 수
