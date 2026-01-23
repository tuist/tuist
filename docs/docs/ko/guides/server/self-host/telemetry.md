---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# Telemetry {#telemetry}

Tuist 서버에서 수집한 메트릭은 [Prometheus](https://prometheus.io/)과
[Grafana](https://grafana.com/)와 같은 시각화 도구를 사용하여 필요에 맞게 커스텀 대시보드를 생성할 수 있습니다.
Prometheus 메트릭은 포트 9091의 `/metrics` 엔드포인트를 통해 제공됩니다. Prometheus의
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)은
10_000초 미만으로 설정해야 합니다(기본값인 15초 유지 권장).

## PostHog 분석 {#posthog-analytics}

Tuist는 사용자 행동 분석 및 이벤트 추적을 위해 [PostHog](https://posthog.com/)과 연동됩니다. 이를 통해 마케팅
사이트, 대시보드, API 문서 전반에서 사용자가 Tuist 서버와 어떻게 상호작용하는지 파악하고, 기능 사용 현황을 추적하며, 사용자 행동에
대한 통찰력을 얻을 수 있습니다.

### 구성 {#posthog-configuration}

PostHog 통합은 선택 사항이며, 적절한 환경 변수를 설정하여 활성화할 수 있습니다. 구성 시 Tuist는 사용자 이벤트, 페이지 뷰 및
사용자 여정을 자동으로 추적합니다.

| 환경 변수                   | 설명                     | 필수  | 기본 값 | 예                                                 |
| ----------------------- | ---------------------- | --- | ---- | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | 귀하의 PostHog 프로젝트 API 키 | 아니요 |      | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | PostHog API 엔드포인트 URL  | 아니요 |      | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
`TUIST_POSTHOG_API_KEY` 및 `TUIST_POSTHOG_URL` 두 변수가 모두 설정된 경우에만 애널리틱스가 활성화됩니다. 두
변수 중 하나라도 누락되면 애널리틱스 이벤트가 전송되지 않습니다.
<!-- -->
:::

### 기능 {#posthog-features}

PostHog가 활성화되면 Tuist는 자동으로 다음을 추적합니다:

- **사용자 식별**: 사용자는 고유 ID와 이메일 주소로 식별됩니다.
- **사용자 별칭**: 사용자는 계정명으로 별칭 처리되어 식별이 용이합니다
- **그룹 분석**: 사용자를 선택한 프로젝트 및 조직별로 그룹화하여 세분화된 분석을 제공합니다.
- **페이지 섹션**: 이벤트에는 애플리케이션의 어느 섹션에서 생성되었는지 나타내는 상위 속성이 포함됩니다:
  - `마케팅` - 마케팅 페이지 및 공개 콘텐츠의 이벤트
  - `dashboard` - 메인 애플리케이션 대시보드 및 인증 영역의 이벤트
  - `api-docs` - API 문서 페이지의 이벤트
- **페이지 조회수**: Phoenix LiveView를 이용한 페이지 탐색 자동 추적
- **사용자 정의 이벤트**: 기능 사용 및 사용자 상호작용을 위한 애플리케이션별 이벤트

### 개인정보 보호 고려사항 {#posthog-privacy}

- 인증된 사용자의 경우, PostHog는 고유 식별자로 사용자의 고유 ID를 사용하고 이메일 주소를 포함합니다.
- 익명 사용자의 경우, PostHog는 데이터를 로컬에 저장하지 않기 위해 메모리 전용 지속성을 사용합니다.
- 모든 분석은 사용자 개인정보를 존중하며 데이터 보호 모범 사례를 따릅니다
- PostHog 데이터는 PostHog의 개인정보 처리방침 및 귀하의 설정에 따라 처리됩니다.

## Elixir 메트릭스 {#elixir-metrics}

기본적으로 Elixir 런타임, BEAM, Elixir 및 사용 중인 일부 라이브러리의 메트릭을 포함합니다. 다음은 확인할 수 있는 메트릭의
예시입니다:

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [오반](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

사용 가능한 지표와 사용 방법을 확인하려면 해당 페이지를 참조하시기 바랍니다.

## 실행 메트릭스 {#runs-metrics}

Tuist Runs와 관련된 일련의 지표들.

### `tuist_runs_total` (카운터) {#tuist_runs_total-counter}

총 투이스트 런 수.

#### Tags {#tuist-runs-total-tags}

| Tag      | 설명                                            |
| -------- | --------------------------------------------- |
| `name`   | 실행된 `tuist` 명령어의 이름, 예를 들어 `build`, `test` 등. |
| `is_ci`  | 실행자가 CI인지 개발자의 컴퓨터인지를 나타내는 부울입니다.             |
| `status` | ``` 0 `성공 시`, `1 `실패 시`.                      |

### `tuist_runs_duration_milliseconds` (히스토그램) {#tuist_runs_duration_milliseconds-histogram}

각 tuist 실행의 총 소요 시간(밀리초 단위).

#### Tags {#tuist-runs-duration-miliseconds-tags}

| Tag      | 설명                                            |
| -------- | --------------------------------------------- |
| `name`   | 실행된 `tuist` 명령어의 이름, 예를 들어 `build`, `test` 등. |
| `is_ci`  | 실행자가 CI인지 개발자의 컴퓨터인지를 나타내는 부울입니다.             |
| `status` | ``` 0 `성공 시`, `1 `실패 시`.                      |

## 캐시 메트릭스 {#cache-metrics}

Tuist 캐시와 관련된 일련의 측정 지표.

### `tuist_cache_events_total` (카운터) {#tuist_cache_events_total-counter}

이진 캐시 이벤트의 총 개수.

#### Tags {#tuist-cache-events-total-tags}

| Tag          | 설명                                              |
| ------------ | ----------------------------------------------- |
| `event_type` | `local_hit`, `remote_hit`, `miss` 중 하나일 수 있습니다. |

### `tuist_cache_uploads_total` (카운터) {#tuist_cache_uploads_total-counter}

바이너리 캐시에 업로드된 횟수.

### `tuist_cache_uploaded_bytes` (합계) {#tuist_cache_uploaded_bytes-sum}

바이너리 캐시에 업로드된 바이트 수.

### `tuist_cache_downloads_total` (카운터) {#tuist_cache_downloads_total-counter}

바이너리 캐시에 대한 다운로드 횟수.

### `tuist_cache_downloaded_bytes` (합계) {#tuist_cache_downloaded_bytes-sum}

바이너리 캐시에서 다운로드된 바이트 수.

---

## 미리보기 지표 {#previews-metrics}

미리보기 기능과 관련된 일련의 측정 항목들.

### `tuist_previews_uploads_total` (합계) {#tuist_previews_uploads_total-counter}

업로드된 총 미리보기 수.

### `tuist_previews_downloads_total` (합계) {#tuist_previews_downloads_total-counter}

다운로드된 미리보기의 총 개수.

---

## 저장소 메트릭스 {#storage-metrics}

원격 저장소(예: s3)에 아티팩트를 저장하는 것과 관련된 일련의 측정 지표.

::: tip
<!-- -->
이러한 지표는 스토리지 작업의 성능을 이해하고 잠재적인 병목 현상을 식별하는 데 유용합니다.
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (histogram) {#tuist_storage_get_object_size_size_bytes-histogram}

원격 저장소에서 가져온 객체의 크기(바이트 단위).

#### Tags {#tuist-storage-get-object-size-size-bytes-tags}

| Tag          | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |


### `tuist_storage_get_object_size_duration_miliseconds` (히스토그램) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

원격 저장소에서 객체 크기를 가져오는 데 걸리는 시간(밀리초 단위).

#### Tags {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Tag          | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |


### `tuist_storage_get_object_size_count` (counter) {#tuist_storage_get_object_size_count-counter}

원격 저장소에서 객체 크기를 조회한 횟수.

#### Tags {#tuist-storage-get-object-size-count-tags}

| Tag          | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (히스토그램) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

원격 저장소에서 모든 객체를 삭제하는 데 걸리는 시간(밀리초 단위).

#### Tags {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Tag            | 설명                           |
| -------------- | ---------------------------- |
| `project_slug` | 삭제 대상 객체가 속한 프로젝트의 프로젝트 슬러그. |


### `tuist_storage_delete_all_objects_count` (카운터) {#tuist_storage_delete_all_objects_count-counter}

원격 저장소에서 모든 프로젝트 객체가 삭제된 횟수.

#### Tags {#tuist-storage-delete-all-objects-count-tags}

| Tag            | 설명                           |
| -------------- | ---------------------------- |
| `project_slug` | 삭제 대상 객체가 속한 프로젝트의 프로젝트 슬러그. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (히스토그램) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

원격 저장소로의 업로드 시작 시간(밀리초 단위).

#### Tags {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Tag          | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |

### `tuist_storage_multipart_start_upload_duration_count` (카운터) {#tuist_storage_multipart_start_upload_duration_count-counter}

원격 저장소로의 업로드 시작 횟수.

#### Tags {#tuist-storage-multipart-start-upload-duration-count-tags}

| Tag          | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (히스토그램) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

원격 저장소에서 객체를 문자열로 가져오는 데 걸리는 시간(밀리초 단위).

#### Tags {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Tag          | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |

### `tuist_storage_get_object_as_string_count` (count) {#tuist_storage_get_object_as_string_count-count}

원격 저장소에서 객체가 문자열로 가져온 횟수.

#### Tags {#tuist-storage-get-object-as-string-count-tags}

| Tag          | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |


### `tuist_storage_check_object_existence_duration_milliseconds` (히스토그램) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

원격 저장소에서 객체의 존재 여부를 확인하는 데 걸리는 시간(밀리초 단위).

#### Tags {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Tag          | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |

### `tuist_storage_check_object_existence_count` (count) {#tuist_storage_check_object_existence_count-count}

원격 스토리지에서 개체의 존재를 확인한 횟수입니다.

#### Tags {#tuist-storage-check-object-existence-count-tags}

| Tag          | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

원격 저장소의 객체에 대한 사전 서명된 다운로드 URL을 생성하는 데 소요되는 시간(밀리초 단위).

#### Tags {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Tag          | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |


### `tuist_storage_generate_download_presigned_url_count` (count) {#tuist_storage_generate_download_presigned_url_count-count}

원격 저장소의 객체에 대해 사전 서명된 다운로드 URL이 생성된 횟수입니다.

#### Tags {#tuist-storage-generate-download-presigned-url-count-tags}

| Tag          | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

원격 저장소의 객체에 대한 부분 업로드 사전 서명 URL을 생성하는 데 소요되는 시간(밀리초 단위).

#### Tags {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Tag           | 설명                      |
| ------------- | ----------------------- |
| `object_key`  | 원격 저장소에 있는 개체의 조회 키입니다. |
| `part_number` | 업로드 중인 객체의 부품 번호.       |
| `upload_id`   | 멀티파트 업로드의 업로드 ID.       |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

원격 저장소의 객체에 대해 부분 업로드 사전 서명 URL이 생성된 횟수입니다.

#### Tags {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Tag           | 설명                      |
| ------------- | ----------------------- |
| `object_key`  | 원격 저장소에 있는 개체의 조회 키입니다. |
| `part_number` | 업로드 중인 객체의 부품 번호.       |
| `upload_id`   | 멀티파트 업로드의 업로드 ID.       |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

원격 저장소로의 업로드 완료 소요 시간(밀리초 단위).

#### Tags {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Tag          | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |
| `upload_id`  | 멀티파트 업로드의 업로드 ID.       |


### `tuist_storage_multipart_complete_upload_count` (count) {#tuist_storage_multipart_complete_upload_count-count}

원격 저장소로의 업로드가 완료된 총 횟수.

#### Tags {#tuist-storage-multipart-complete-upload-count-tags}

| Tag          | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |
| `upload_id`  | 멀티파트 업로드의 업로드 ID.       |

---

## 인증 지표 {#authentication-metrics}

인증과 관련된 일련의 측정 기준.

### `tuist_authentication_token_refresh_error_total` (카운터) {#tuist_authentication_token_refresh_error_total-counter}

토큰 새로고침 오류의 총 개수.

#### Tags {#tuist-authentication-token-refresh-error-total-tags}

| Tag           | 설명                                                    |
| ------------- | ----------------------------------------------------- |
| `cli_version` | 오류가 발생한 Tuist CLI 버전.                                 |
| `이유`          | 토큰 새로고침 오류의 원인: `invalid_token_type` ` invalid_token` |

---

## 프로젝트 지표 {#projects-metrics}

프로젝트와 관련된 일련의 지표들.

### `tuist_projects_total` (last_value) {#tuist_projects_total-last_value}

총 프로젝트 수.

---

## 계정 지표 {#accounts-metrics}

계정(사용자 및 조직)과 관련된 일련의 지표.

### `tuist_accounts_organizations_total` (last_value) {#tuist_accounts_organizations_total-last_value}

총 기관 수.

### `tuist_accounts_users_total` (last_value) {#tuist_accounts_users_total-last_value}

총 사용자 수.


## 데이터베이스 메트릭스 {#database-metrics}

데이터베이스 연결과 관련된 일련의 측정값.

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

데이터베이스 연결에 할당되기를 기다리며 대기열에 있는 데이터베이스 쿼리의 수.

### `tuist_repo_pool_ready_conn_count` (last_value) {#tuist_repo_pool_ready_conn_count-last_value}

데이터베이스 쿼리에 할당될 준비가 된 데이터베이스 연결 수.


### `tuist_repo_pool_db_connection_connected` (카운터) {#tuist_repo_pool_db_connection_connected-counter}

데이터베이스에 설정된 연결 수.

### `tuist_repo_pool_db_connection_disconnected` (카운터) {#tuist_repo_pool_db_connection_disconnected-counter}

데이터베이스에서 연결이 끊어진 연결 수.

## HTTP 메트릭스 {#http-metrics}

Tuist가 HTTP를 통해 다른 서비스와 상호작용하는 것과 관련된 일련의 측정값.

### `tuist_http_request_count` (카운터) {#tuist_http_request_count-last_value}

발신 HTTP 요청 수.

### `tuist_http_request_duration_nanosecond_sum` (합계) {#tuist_http_request_duration_nanosecond_sum-last_value}

아웃바운드 요청의 지속 시간 합계(연결 할당 대기 시간 포함).

### `tuist_http_request_duration_nanosecond_bucket` (distribution) {#tuist_http_request_duration_nanosecond_bucket-distribution}
발신 요청의 지속 시간 분포(요청이 연결에 할당되기까지 기다린 시간 포함).

### `tuist_http_queue_count` (카운터) {#tuist_http_queue_count-counter}

풀에서 검색된 요청의 수.

### `tuist_http_queue_duration_nanoseconds_sum` (합계) {#tuist_http_queue_duration_nanoseconds_sum-sum}

연결 풀에서 연결을 검색하는 데 걸리는 시간.

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

연결이 검색을 기다리며 비활성 상태로 있었던 시간.

### `tuist_http_queue_duration_nanoseconds_bucket` (distribution) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

연결 풀에서 연결을 검색하는 데 걸리는 시간.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (distribution) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

연결이 검색을 기다리며 비활성 상태로 있었던 시간.

### `tuist_http_connection_count` (카운터) {#tuist_http_connection_count-counter}

설정된 연결 수.

### `tuist_http_connection_duration_nanoseconds_sum` (합계) {#tuist_http_connection_duration_nanoseconds_sum-sum}

호스트에 대한 연결을 설정하는 데 걸리는 시간.

### `tuist_http_connection_duration_nanoseconds_bucket` (distribution) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

호스트에 대한 연결 설정 시간 분포.

### `tuist_http_send_count` (카운터) {#tuist_http_send_count-counter}

풀에서 연결에 할당된 후 전송된 요청 수.

### `tuist_http_send_duration_nanoseconds_sum` (sum) {#tuist_http_send_duration_nanoseconds_sum-sum}

풀에서 연결에 할당된 후 요청이 완료되는 데 걸리는 시간.

### `tuist_http_send_duration_nanoseconds_bucket` (distribution) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

풀에서 연결에 할당된 후 요청이 완료되는 데 걸리는 시간의 분포.

### `tuist_http_receive_count` (카운터) {#tuist_http_receive_count-counter}

발송된 요청에 대해 수신된 응답의 수.

### `tuist_http_receive_duration_nanoseconds_sum` (합계) {#tuist_http_receive_duration_nanoseconds_sum-sum}

응답을 받는 데 소요된 시간.

### `tuist_http_receive_duration_nanoseconds_bucket` (distribution) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

응답을 받는 데 소요된 시간의 분포입니다.

### `tuist_http_queue_available_connections` (last_value) {#tuist_http_queue_available_connections-last_value}

대기열에서 사용 가능한 연결 수.

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

사용 중인 큐 연결 수.
