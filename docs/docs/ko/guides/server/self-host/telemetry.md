---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# 원격 분석 {#telemetry}

Prometheus](https://prometheus.io/) 및 [Grafana](https://grafana.com/)와 같은 시각화
도구를 사용하여 Tuist 서버에서 수집한 지표를 수집하여 필요에 맞는 사용자 지정 대시보드를 만들 수 있습니다. Prometheus 메트릭은
포트 9091의 `/metrics` 엔드포인트를 통해 제공됩니다. Prometheus의
[스크랩_간격](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)은
10_000초 미만으로 설정해야 합니다(기본값인 15초를 유지하는 것이 좋습니다).

## PostHog 분석 {#posthog-analytics}

Tuist는 사용자 행동 분석 및 이벤트 추적을 위해 [PostHog](https://posthog.com/)와 통합됩니다. 이를 통해 사용자가
Tuist 서버와 상호 작용하는 방식을 이해하고, 기능 사용을 추적하고, 마케팅 사이트, 대시보드 및 API 문서 전반에서 사용자 행동에 대한
인사이트를 얻을 수 있습니다.

### 구성 {#posthog-configuration}

PostHog 통합은 선택 사항이며 적절한 환경 변수를 설정하여 활성화할 수 있습니다. 설정하면 Tuist는 사용자 이벤트, 페이지 조회수 및
사용자 여정을 자동으로 추적합니다.

| 환경 변수              | 설명                    | 필수  | 기본값 | 예                                                 |
| ------------------ | --------------------- | --- | --- | ------------------------------------------------- |
| `튜이스트_포스트호그_API_키` | PostHog 프로젝트 API 키    | 아니요 |     | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `튜이스트_포스트호그_URL`   | PostHog API 엔드포인트 URL | 아니요 |     | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
분석은 `TUIST_POSTHOG_API_KEY` 및 `TUIST_POSTHOG_URL` 이 모두 구성된 경우에만 활성화됩니다. 두 변수 중
하나라도 누락되면 분석 이벤트가 전송되지 않습니다.
<!-- -->
:::

### 특징 {#posthog-features}

PostHog를 활성화하면 Tuist가 자동으로 추적합니다:

- **사용자 식별**: 사용자는 고유 ID와 이메일 주소로 식별됩니다.
- **사용자 별칭**: 사용자 식별을 쉽게 하기 위해 계정 이름으로 별칭을 지정합니다.
- **그룹 분석**: 세그먼트 분석을 위해 선택한 프로젝트 및 조직별로 사용자를 그룹화합니다.
- **페이지 섹션**: 이벤트에는 애플리케이션의 어느 섹션에서 이벤트를 생성했는지를 나타내는 슈퍼 속성이 포함됩니다:
  - `마케팅` - 마케팅 페이지 및 공개 콘텐츠의 이벤트
  - `대시보드` - 기본 애플리케이션 대시보드 및 인증된 영역의 이벤트
  - `api-docs` - API 문서 페이지의 이벤트
- **페이지 조회수**: 피닉스 라이브뷰를 사용한 페이지 탐색 자동 추적
- **사용자 지정 이벤트**: 기능 사용 및 사용자 상호작용을 위한 애플리케이션별 이벤트

### 개인정보 보호 고려 사항 {#posthog-privacy}

- 인증된 사용자의 경우 PostHog는 사용자의 고유 ID를 고유 식별자로 사용하며 이메일 주소를 포함합니다.
- 익명 사용자의 경우 PostHog는 메모리 전용 지속성을 사용하여 데이터를 로컬에 저장하지 않습니다.
- 모든 분석은 사용자 개인 정보를 존중하고 데이터 보호 모범 사례를 따릅니다.
- PostHog 데이터는 PostHog의 개인정보처리방침 및 사용자 설정에 따라 처리됩니다.

## 엘릭서 지표 {#elixir-metrics}

기본적으로 Elixir 런타임, BEAM, Elixir 및 우리가 사용하는 일부 라이브러리에 대한 메트릭이 포함됩니다. 다음은 예상할 수 있는
몇 가지 메트릭입니다:

- [애플리케이션](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [피닉스](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [피닉스 라이브뷰](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [오반](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

해당 페이지를 확인하여 사용 가능한 메트릭과 사용 방법을 알아보는 것이 좋습니다.

## 메트릭 실행 {#runs-metrics}

튜이스트 런과 관련된 일련의 메트릭입니다.

### `tuist_runs_total` (카운터) {#tuist_runs_total-counter}

총 튜이스트 런 횟수입니다.

#### 태그 {#tuist-runs-total-tags}

| 태그      | 설명                                           |
| ------- | -------------------------------------------- |
| `이름`    | `build`, `test` 등과 같이 실행한 `tuist` 명령의 이름입니다. |
| `is_ci` | 실행자가 CI인지 개발자 머신인지를 나타내는 부울입니다.              |
| `상태`    | `0` ` 성공의 경우`, `1` ` 실패의 경우`.                |

### `튜이스트_런_지속시간_밀리초` (히스토그램) {#tuist_runs_duration_milliseconds-histogram}

각 튜티스트의 총 실행 시간(밀리초)입니다.

#### 태그 {#tuist-runs-duration-miliseconds-tags}

| 태그      | 설명                                           |
| ------- | -------------------------------------------- |
| `이름`    | `build`, `test` 등과 같이 실행한 `tuist` 명령의 이름입니다. |
| `is_ci` | 실행자가 CI인지 개발자 머신인지를 나타내는 부울입니다.              |
| `상태`    | `0` ` 성공의 경우`, `1` ` 실패의 경우`.                |

## 캐시 메트릭 {#cache-metrics}

튜이스트 캐시와 관련된 메트릭 집합입니다.

### `튜이스트_캐시_이벤트_총계` (카운터) {#tuist_cache_events_total-counter}

바이너리 캐시 이벤트의 총 개수입니다.

#### 태그 {#tuist-cache-events-total-tags}

| 태그       | 설명                                                  |
| -------- | --------------------------------------------------- |
| `이벤트 유형` | `local_hit`, `remote_hit`, 또는 `miss` 중 하나 일 수 있습니다. |

### `튜이스트_캐시_업로드_총계` (카운터) {#tuist_cache_uploads_total-counter}

바이너리 캐시에 업로드한 횟수입니다.

### `tuist_cache_uploaded_bytes` (합계) {#tuist_cache_uploaded_bytes-sum}

바이너리 캐시에 업로드된 바이트 수입니다.

### `튜이스트_캐시_다운로드_총계` (카운터) {#tuist_cache_downloads_total-counter}

바이너리 캐시에 대한 다운로드 횟수입니다.

### `tuist_cache_downloaded_bytes` (합계) {#tuist_cache_downloaded_bytes-sum}

바이너리 캐시에서 다운로드한 바이트 수입니다.

---

## 메트릭 미리보기 {#previews-metrics}

미리보기 기능과 관련된 일련의 메트릭입니다.

### `튜이스트_프리뷰_업로드_총계` (합계) {#tuist_previews_uploads_total-counter}

업로드된 총 미리보기 수입니다.

### `튜이스트_프리뷰_다운로드_총계` (합계) {#tuist_previews_downloads_total-counter}

다운로드한 미리보기의 총 개수입니다.

---

## 스토리지 메트릭 {#storage-metrics}

원격 스토리지(예: s3)에 아티팩트 저장과 관련된 메트릭 집합입니다.

::: tip
<!-- -->
이러한 메트릭은 스토리지 작업의 성능을 이해하고 잠재적인 병목 현상을 파악하는 데 유용합니다.
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (히스토그램) {#tuist_storage_get_object_size_size_bytes-histogram}

원격 저장소에서 가져온 개체의 크기(바이트 단위)입니다.

#### 태그 {#tuist-storage-get-object-size-size-bytes-tags}

| 태그           | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |


### `tuist_storage_get_object_size_duration_miliseconds` (히스토그램) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

원격 저장소에서 개체 크기를 가져오는 데 걸리는 시간(밀리초)입니다.

#### 태그 {#tuist-storage-get-object-size-duration-miliseconds-tags}

| 태그           | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |


### `tuist_storage_get_object_size_count` (카운터) {#tuist_storage_get_object_size_count-counter}

원격 스토리지에서 개체 크기를 가져온 횟수입니다.

#### 태그 {#tuist-storage-get-object-size-count-tags}

| 태그           | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (히스토그램) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

원격 스토리지에서 모든 개체를 삭제하는 데 걸리는 기간(밀리초)입니다.

#### 태그 {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| 태그         | 설명                            |
| ---------- | ----------------------------- |
| `프로젝트_슬러그` | 오브젝트가 삭제되는 프로젝트의 프로젝트 슬러그입니다. |


### `튜이스트_저장소_삭제_모든_객체_수` (카운터) {#tuist_storage_delete_all_objects_count-counter}

원격 저장소에서 모든 프로젝트 개체가 삭제된 횟수입니다.

#### 태그 {#tuist-storage-delete-all-objects-count-tags}

| 태그         | 설명                            |
| ---------- | ----------------------------- |
| `프로젝트_슬러그` | 오브젝트가 삭제되는 프로젝트의 프로젝트 슬러그입니다. |


### `tuist_storage_multipart_start_upload_duration_밀리초` (히스토그램) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

원격 저장소에 업로드를 시작하는 기간(밀리초)입니다.

#### 태그 {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| 태그           | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |

### `튜이스트_스토리지_멀티파트_시작_업로드_기간_수` (카운터) {#tuist_storage_multipart_start_upload_duration_count-counter}

원격 스토리지에 업로드가 시작된 횟수입니다.

#### 태그 {#tuist-storage-multipart-start-upload-duration-count-tags}

| 태그           | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (히스토그램) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

원격 저장소에서 객체를 문자열로 가져오는 데 걸리는 기간(밀리초)입니다.

#### 태그 {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| 태그           | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |

### `tuist_storage_get_object_as_string_count` (카운트) {#tuist_storage_get_object_as_string_count-count}

원격 스토리지에서 객체를 문자열로 가져온 횟수입니다.

#### 태그 {#tuist-storage-get-object-as-string-count-tags}

| 태그           | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |


### `tuist_storage_check_object_existence_duration_milliseconds` (히스토그램) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

원격 스토리지에 있는 개체의 존재 여부를 확인하는 기간(밀리초)입니다.

#### 태그 {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| 태그           | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |

### `tuist_storage_check_object_existence_count` (개수) {#tuist_storage_check_object_existence_count-count}

원격 스토리지에서 개체의 존재가 확인된 횟수입니다.

#### 태그 {#tuist-storage-check-object-existence-count-tags}

| 태그           | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (히스토그램) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

원격 저장소에 있는 개체에 대해 미리 지정된 다운로드 URL을 생성하는 데 걸리는 기간(밀리초)입니다.

#### 태그 {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| 태그           | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |


### `tuist_storage_generate_download_presigned_url_count` (카운트) {#tuist_storage_generate_download_presigned_url_count-count}

원격 저장소에 있는 개체에 대해 다운로드 미리 지정된 URL이 생성된 횟수입니다.

#### 태그 {#tuist-storage-generate-download-presigned-url-count-tags}

| 태그           | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (히스토그램) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

원격 저장소에 있는 개체에 대한 파트 업로드 사전 지정 URL을 생성하는 기간(밀리초)입니다.

#### 태그 {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| 태그            | 설명                      |
| ------------- | ----------------------- |
| `object_key`  | 원격 저장소에 있는 개체의 조회 키입니다. |
| `part_number` | 업로드 중인 오브젝트의 부품 번호입니다.  |
| `upload_id`   | 멀티파트 업로드의 업로드 ID입니다.    |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (카운트) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

원격 스토리지의 개체에 대해 파트 업로드 지정 URL이 생성된 횟수입니다.

#### 태그 {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| 태그            | 설명                      |
| ------------- | ----------------------- |
| `object_key`  | 원격 저장소에 있는 개체의 조회 키입니다. |
| `part_number` | 업로드 중인 오브젝트의 부품 번호입니다.  |
| `upload_id`   | 멀티파트 업로드의 업로드 ID입니다.    |

### `튜이스트_스토리지_멀티파트_완료_업로드_지속시간_밀리초` (히스토그램) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

원격 저장소에 업로드를 완료하는 데 걸리는 시간(밀리초)입니다.

#### 태그 {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| 태그           | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |
| `upload_id`  | 멀티파트 업로드의 업로드 ID입니다.    |


### `튜이스트_스토리지_멀티파트_완성_업로드_수` (개수) {#tuist_storage_multipart_complete_upload_count-count}

원격 스토리지에 업로드가 완료된 총 횟수입니다.

#### 태그 {#tuist-storage-multipart-complete-upload-count-tags}

| 태그           | 설명                      |
| ------------ | ----------------------- |
| `object_key` | 원격 저장소에 있는 개체의 조회 키입니다. |
| `upload_id`  | 멀티파트 업로드의 업로드 ID입니다.    |

---

## 인증 메트릭 {#authentication-metrics}

인증과 관련된 메트릭 집합입니다.

### `튜이스트_인증_토큰_리프레시_오류_총계` (카운터) {#tuist_authentication_token_refresh_error_total-counter}

토큰 새로 고침 오류의 총 개수입니다.

#### 태그 {#tuist-authentication-token-refresh-error-total-tags}

| 태그            | 설명                                                           |
| ------------- | ------------------------------------------------------------ |
| `cli_version` | 오류가 발생한 Tuist CLI의 버전입니다.                                    |
| `이유`          | 토큰 새로 고침 오류의 원인(예: `invalid_token_type` 또는 `invalid_token`). |

---

## 프로젝트 메트릭 {#projects-metrics}

프로젝트와 관련된 일련의 메트릭입니다.

### `tuist_projects_total` (last_value) {#tuist_projects_total-last_value}

총 프로젝트 수입니다.

---

## 계정 메트릭 {#accounts-metrics}

계정(사용자 및 조직)과 관련된 일련의 메트릭입니다.

### `tuist_accounts_organizations_total` (last_value) {#tuist_accounts_organizations_total-last_value}

총 조직 수입니다.

### `tuist_accounts_users_total` (last_value) {#tuist_accounts_users_total-last_value}

총 사용자 수입니다.


## 데이터베이스 메트릭 {#database-metrics}

데이터베이스 연결과 관련된 메트릭 집합입니다.

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

데이터베이스 연결에 할당되기를 기다리며 대기열에 있는 데이터베이스 쿼리의 수입니다.

### `tuist_repo_pool_ready_conn_count` (last_value) {#tuist_repo_pool_ready_conn_count-last_value}

데이터베이스 쿼리에 할당할 준비가 된 데이터베이스 연결 수입니다.


### `튜이스트_재풀_DB_연결_연결_연결` (카운터) {#tuist_repo_pool_db_connection_connected-counter}

데이터베이스에 설정된 연결 수입니다.

### `tuist_repo_pool_db_connection_disconnected` (카운터) {#tuist_repo_pool_db_connection_disconnected-counter}

데이터베이스에서 연결이 끊어진 연결 수입니다.

## HTTP 메트릭 {#http-metrics}

HTTP를 통해 다른 서비스와 Tuist의 상호작용과 관련된 일련의 메트릭입니다.

### `tuist_http_request_count` (카운터) {#tuist_http_request_count-last_value}

발신 HTTP 요청 수입니다.

### `tuist_http_request_duration_nanosecond_sum` (합계) {#tuist_http_request_duration_nanosecond_sum-last_value}

발신 요청 기간의 합계(연결에 할당되기 위해 대기한 시간 포함)입니다.

### `tuist_http_request_duration_nanosecond_bucket` (배포) {#tuist_http_request_duration_nanosecond_bucket-distribution}
발신 요청의 기간 분포(연결에 할당되기 위해 대기한 시간 포함).

### `tuist_http_queue_count` (카운터) {#tuist_http_queue_count-counter}

풀에서 검색된 요청 수입니다.

### `tuist_http_queue_duration_nanoseconds_sum` (합계) {#tuist_http_queue_duration_nanoseconds_sum-sum}

풀에서 연결을 검색하는 데 걸리는 시간입니다.

### `tuist_http_queue_idle_time_nanoseconds_sum` (합계) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

연결이 검색되기를 기다리며 유휴 상태인 시간입니다.

### `tuist_http_queue_duration_nanoseconds_bucket` (배포) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

풀에서 연결을 검색하는 데 걸리는 시간입니다.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (배포) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

연결이 검색되기를 기다리며 유휴 상태인 시간입니다.

### `tuist_http_connection_count` (카운터) {#tuist_http_connection_count-counter}

설정된 연결 수입니다.

### `tuist_http_connection_duration_nanoseconds_sum` (sum) {#tuist_http_connection_duration_nanoseconds_sum-sum}

호스트에 대한 연결을 설정하는 데 걸리는 시간입니다.

### `tuist_http_connection_duration_nanoseconds_bucket` (배포) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

호스트에 대한 연결을 설정하는 데 걸리는 시간의 분포입니다.

### `tuist_http_send_count` (카운터) {#tuist_http_send_count-counter}

풀에서 연결에 할당된 후 전송된 요청 수입니다.

### `tuist_http_send_duration_nanoseconds_sum` (합계) {#tuist_http_send_duration_nanoseconds_sum-sum}

풀에서 연결에 할당된 후 요청이 완료되는 데 걸리는 시간입니다.

### `tuist_http_send_duration_nanoseconds_bucket` (배포) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

풀에서 연결에 할당된 후 요청이 완료되는 데 걸리는 시간의 분포입니다.

### `tuist_http_receive_count` (카운터) {#tuist_http_receive_count-counter}

보낸 요청에 대해 수신된 응답 수입니다.

### `tuist_http_receive_duration_nanoseconds_sum` (합계) {#tuist_http_receive_duration_nanoseconds_sum-sum}

응답을 받는 데 소요된 시간입니다.

### `tuist_http_receive_duration_nanoseconds_bucket` (배포) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

응답 수신에 소요된 시간의 분포입니다.

### `tuist_http_queue_available_connections` (last_value) {#tuist_http_queue_available_connections-last_value}

대기열에서 사용 가능한 연결 수입니다.

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

사용 중인 대기열 연결 수입니다.
