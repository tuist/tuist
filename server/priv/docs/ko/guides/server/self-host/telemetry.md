---
{
  "title": "텔레메트리",
  "titleTemplate": ":title | 자체 호스팅 | 서버 | 가이드 | Tuist",
  "description": "Prometheus 메트릭, OpenTelemetry 트레이스 및 로그 전달로 Tuist 서버를 모니터링하세요."
}
---
# 텔레메트리 {#telemetry}

Tuist는 세 가지 상호 보완적인 관찰 가능성 신호를 제공합니다: **메트릭**(Prometheus), **트레이스**(OpenTelemetry), 그리고 **로그**(Loki 호환). 이 세 가지는 모두 선택 사항이며 독립적으로 활성화할 수 있습니다.

## 분산 트레이싱 (OpenTelemetry) {#opentelemetry}

Tuist는 분산 트레이싱을 위해 [OpenTelemetry](https://opentelemetry.io/)를 지원합니다. 활성화되면 서버는 HTTP 요청(Phoenix 및 Bandit), 데이터베이스 쿼리(Ecto), 외부 HTTP 호출(Finch) 및 Broadway 메시지 처리에 대한 트레이스를 생성합니다. 이러한 트레이스를 통해 요청 지연 시간을 이해하고, 느린 쿼리를 식별하며, 서비스 간 요청 흐름을 추적할 수 있습니다.

### 설정 {#opentelemetry-configuration}

트레이스 export를 활성화하려면 다음 환경 변수를 설정하세요:

| 환경 변수 | 설명 | 필수 여부 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry Collector의 gRPC 엔드포인트 (예: Grafana Alloy, Jaeger 또는 OTLP 호환 콜렉터) | 아니요 | | `http://localhost:4317` |

이 변수가 설정되지 않으면 트레이싱이 비활성화되며 오버헤드가 발생하지 않습니다.

### 계측된 라이브러리 {#opentelemetry-instrumented-libraries}

트레이싱이 활성화되면 다음 라이브러리가 자동으로 계측됩니다:

- **Bandit** -- HTTP 서버 연결 스팬
- **Phoenix** -- 요청 라이프사이클 스팬 (컨트롤러 액션, LiveView)
- **Ecto** -- 쿼리 메타데이터가 포함된 데이터베이스 쿼리 스팬
- **Finch** -- 외부 HTTP 클라이언트 요청 스팬
- **Broadway** -- 메시지 처리 파이프라인 스팬

### Grafana Alloy 예시 설정 {#opentelemetry-alloy-example}

콜렉터로 [Grafana Alloy](https://grafana.com/docs/alloy/latest/)를 사용하는 경우, OTLP 트레이스를 수신하고 이를 트레이싱 백엔드(예: Grafana Cloud Tempo)로 전달하도록 구성하세요:

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

그런 다음 `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT`를 Alloy 인스턴스를 가리키도록 설정하세요. 예: `http://alloy:4317`.

## 로그 전달 (Loki) {#log-forwarding}

Tuist는 애플리케이션 로그를 [Loki](https://grafana.com/oss/loki/) 호환 엔드포인트로 전달할 수 있습니다. 이를 통해 메트릭 및 트레이스와 함께 로그를 중앙화하여 완전한 관찰 가능성 그림을 얻을 수 있습니다. 로그는 Loki HTTP 푸시 API(`/loki/api/v1/push`)를 통해 푸시되며 `app`, `env`, `level`에 대한 라벨을 포함합니다.

### 설정 {#log-forwarding-configuration}

| 환경 변수 | 설명 | 필수 여부 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_LOKI_URL` | Loki 호환 푸시 API 엔드포인트의 기본 URL | 아니요 | | `http://localhost:3100` |

이 변수가 설정되지 않으면 로그 전달이 비활성화됩니다.

### Grafana Alloy 예시 설정 {#log-forwarding-alloy-example}

Grafana Alloy는 [`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/) 컴포넌트를 사용하여 로컬 로그 릴레이 역할을 할 수 있습니다:

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

그런 다음 `TUIST_LOKI_URL=http://alloy:3100`를 설정하세요.

푸시 API를 노출하는 Loki 인스턴스가 있는 경우 `TUIST_LOKI_URL`를 직접 해당 인스턴스를 가리키도록 설정할 수도 있습니다.

## Prometheus 메트릭 {#prometheus-metrics}

[Prometheus](https://prometheus.io/)와 [Grafana](https://grafana.com/) 같은 시각화 도구를 사용하여 Tuist 서버가 수집한 메트릭을 가져오고, 필요에 맞는 맞춤형 대시보드를 만들 수 있습니다. Prometheus 메트릭은 포트 9091의 `/metrics` 엔드포인트를 통해 제공됩니다. Prometheus의 [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)은 10_000초 미만으로 설정해야 합니다(관찰 가능성과 메트릭 수집 비용 간의 균형을 위해 30초를 권장합니다).

## 실제 사용자 모니터링 {#real-user-monitoring}

Tuist는 제공되는 JavaScript에 번들로 포함된 [Grafana Faro](https://grafana.com/oss/faro/) Web SDK를 사용하여 마케팅 사이트, 문서 및 대시보드의 브라우저 성능을 보고할 수 있습니다. 이는 Core Web Vitals(Largest Contentful Paint 포함), 처리되지 않은 오류 및 페이지 뷰를 캡처하고 실행 중인 [Faro receiver](https://grafana.com/docs/alloy/latest/reference/components/faro/faro.receiver/)(예: Loki와 Tempo로 전달하는 Grafana Alloy의 `faro.receiver` 컴포넌트)로 전송합니다.

### 설정 {#real-user-monitoring-configuration}

| 환경 변수 | 설명 | 필수 여부 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_FARO_COLLECTOR_URL` | 브라우저가 Faro 페이로드를 게시하는 URL | 아니요 | | `/-/faro` |

> [!NOTE]
> 실제 사용자 모니터링은 `TUIST_FARO_COLLECTOR_URL`가 설정된 경우에만 활성화됩니다. 이 설정이 없으면 브라우저 텔레메트리가 수집되지 않으며 서드파티 스크립트가 로드되지 않습니다.

`/-/faro`와 같은 동일 출처 경로는 크로스 오리진 요청을 방지하고 브라우저의 콘텐츠 보안 정책을 변경하지 않습니다. 인그레스를 통해 Faro 리시버를 가리키도록 설정하세요.

### 수집 항목 {#real-user-monitoring-collected}

- **웹 바이탈**: LCP, CLS, INP, FCP 및 TTFB는 브라우저에서 자동으로 캡처됩니다
- **페이지 뷰**: 로드 시 및 Phoenix LiveView 네비게이션 시 기록됩니다
- **뷰**: 각 페이로드에는 이를 생성한 섹션(`marketing`, `docs`, `dashboard` 또는 `api-docs`)이 포함됩니다
- **오류**: 처리되지 않은 예외 및 핸들링되지 않은 프로미스 거부

### 개인 정보 고려 사항 {#real-user-monitoring-privacy}

- 사용자 신원이 첨부되지 않음: 페이로드에는 사용자 ID, 이메일 또는 계정 정보가 포함되지 않습니다
- 세션은 방문 간에 지속되지 않으므로 브라우저 저장소에 아무것도 기록되지 않습니다
- 콘솔 캡처가 비활성화되어 있으므로 애플리케이션 로그 출력은 브라우저에서 전송되지 않습니다

## Elixir 메트릭 {#elixir-metrics}

기본적으로 Elixir 런타임, BEAM, Elixir 및 사용하는 일부 라이브러리의 메트릭을 포함합니다. 확인할 수 있는 메트릭은 다음과 같습니다:

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

사용 가능한 메트릭과 사용 방법을 확인하려면 해당 페이지를 참조하는 것을 권장합니다.

## 실행 메트릭 {#runs-metrics}

Tuist Runs와 관련된 메트릭 세트입니다.

### `tuist_runs_total` (카운터) {#tuist_runs_total-counter}

Tuist Runs의 총 횟수입니다.

#### 태그 {#tuist-runs-total-tags}

| 태그 | 설명 |
|--- | ---- |
| `name` | 실행된 `tuist` 명령의 이름(예: `build`, `test` 등) |
| `is_ci` | 실행자가 CI인지 개발자의 머신인지 나타내는 불리언 값입니다. |
| `status` | `success`인 경우 `0`, `failure`인 경우 `1`입니다. |

### `tuist_runs_duration_milliseconds` (히스토그램) {#tuist_runs_duration_milliseconds-histogram}

각 tuist 실행의 총 지속 시간(밀리초)입니다.

#### 태그 {#tuist-runs-duration-miliseconds-tags}

| 태그 | 설명 |
|--- | ---- |
| `name` | 실행된 `tuist` 명령의 이름(예: `build`, `test` 등) |
| `is_ci` | 실행자가 CI인지 개발자의 머신인지 나타내는 불리언 값입니다. |
| `status` | `success`인 경우 `0`, `failure`인 경우 `1`입니다. |

## 캐시 메트릭 {#cache-metrics}

Tuist Cache와 관련된 메트릭 세트입니다.

### `tuist_cache_events_total` (카운터) {#tuist_cache_events_total-counter}

바이너리 캐시 이벤트의 총 횟수입니다.

#### 태그 {#tuist-cache-events-total-tags}

| 태그 | 설명 |
|--- | ---- |
| `event_type` | `local_hit`, `remote_hit` 또는 `miss` 중 하나일 수 있습니다. |

### `tuist_cache_uploads_total` (카운터) {#tuist_cache_uploads_total-counter}

바이너리 캐시로 업로드된 횟수입니다.

### `tuist_cache_uploaded_bytes` (합계) {#tuist_cache_uploaded_bytes-sum}

바이너리 캐시로 업로드된 바이트 수입니다.

### `tuist_cache_downloads_total` (카운터) {#tuist_cache_downloads_total-counter}

바이너리 캐시에서 다운로드된 횟수입니다.

### `tuist_cache_downloaded_bytes` (합계) {#tuist_cache_downloaded_bytes-sum}

바이너리 캐시에서 다운로드된 바이트 수입니다.

---

## 프리뷰 메트릭 {#previews-metrics}

프리뷰 기능과 관련된 메트릭 세트입니다.

### `tuist_previews_uploads_total` (합계) {#tuist_previews_uploads_total-counter}

업로드된 프리뷰의 총 횟수입니다.

### `tuist_previews_downloads_total` (합계) {#tuist_previews_downloads_total-counter}

다운로드된 프리뷰의 총 횟수입니다.

---

## 스토리지 메트릭 {#storage-metrics}

원격 스토리지(예: S3)에 아티팩트를 저장하는 것과 관련된 메트릭 세트입니다.

> [!TIP]
> 이 메트릭은 스토리지 작업의 성능을 이해하고 잠재적인 병목 현상을 식별하는 데 유용합니다.


### `tuist_storage_get_object_size_size_bytes` (히스토그램) {#tuist_storage_get_object_size_size_bytes-histogram}

원격 스토리지에서 가져온 객체의 크기(바이트)입니다.

#### 태그 {#tuist-storage-get-object-size-size-bytes-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |


### `tuist_storage_get_object_size_duration_miliseconds` (히스토그램) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

원격 스토리지에서 객체 크기를 가져오는 데 걸린 시간(밀리초)입니다.

#### 태그 {#tuist-storage-get-object-size-duration-miliseconds-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |


### `tuist_storage_get_object_size_count` (카운터) {#tuist_storage_get_object_size_count-counter}

원격 스토리지에서 객체 크기를 가져온 횟수입니다.

#### 태그 {#tuist-storage-get-object-size-count-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (히스토그램) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

원격 스토리지에서 모든 객체를 삭제하는 데 걸린 시간(밀리초)입니다.

#### 태그 {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| 태그 | 설명 |
|--- | ---- |
| `project_slug` | 객체가 삭제되는 프로젝트의 프로젝트 슬러그입니다. |


### `tuist_storage_delete_all_objects_count` (카운터) {#tuist_storage_delete_all_objects_count-counter}

원격 스토리지에서 모든 프로젝트 객체가 삭제된 횟수입니다.

#### 태그 {#tuist-storage-delete-all-objects-count-tags}

| 태그 | 설명 |
|--- | ---- |
| `project_slug` | 객체가 삭제되는 프로젝트의 프로젝트 슬러그입니다. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (히스토그램) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

원격 스토리지로 업로드를 시작하는 데 걸린 시간(밀리초)입니다.

#### 태그 {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |

### `tuist_storage_multipart_start_upload_duration_count` (카운터) {#tuist_storage_multipart_start_upload_duration_count-counter}

원격 스토리지로 업로드가 시작된 횟수입니다.

#### 태그 {#tuist-storage-multipart-start-upload-duration-count-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (히스토그램) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

원격 스토리지에서 객체를 문자열로 가져오는 데 걸린 시간(밀리초)입니다.

#### 태그 {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |

### `tuist_storage_get_object_as_string_count` (카운트) {#tuist_storage_get_object_as_string_count-count}

원격 스토리지에서 객체를 문자열로 가져온 횟수입니다.

#### 태그 {#tuist-storage-get-object-as-string-count-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |


### `tuist_storage_check_object_existence_duration_milliseconds` (히스토그램) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

원격 스토리지에서 객체의 존재 여부를 확인하는 데 걸린 시간(밀리초)입니다.

#### 태그 {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |

### `tuist_storage_check_object_existence_count` (카운트) {#tuist_storage_check_object_existence_count-count}

원격 스토리지에서 객체의 존재 여부를 확인한 횟수입니다.

#### 태그 {#tuist-storage-check-object-existence-count-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (히스토그램) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

원격 스토리지의 객체에 대한 다운로드 사전 서명 URL을 생성하는 데 걸린 시간(밀리초)입니다.

#### 태그 {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |


### `tuist_storage_generate_download_presigned_url_count` (카운트) {#tuist_storage_generate_download_presigned_url_count-count}

원격 스토리지의 객체에 대한 다운로드 사전 서명 URL이 생성된 횟수입니다.

#### 태그 {#tuist-storage-generate-download-presigned-url-count-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (히스토그램) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

원격 스토리지의 객체에 대한 파트 업로드 사전 서명 URL을 생성하는 데 걸린 시간(밀리초)입니다.

#### 태그 {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |
| `part_number` | 업로드 중인 객체의 파트 번호입니다. |
| `upload_id` | 멀티파트 업로드의 업로드 ID입니다. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (카운트) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

원격 스토리지의 객체에 대한 파트 업로드 사전 서명 URL이 생성된 횟수입니다.

#### 태그 {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |
| `part_number` | 업로드 중인 객체의 파트 번호입니다. |
| `upload_id` | 멀티파트 업로드의 업로드 ID입니다. |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (히스토그램) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

원격 스토리지로 업로드를 완료하는 데 걸린 시간(밀리초)입니다.

#### 태그 {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |
| `upload_id` | 멀티파트 업로드의 업로드 ID입니다. |


### `tuist_storage_multipart_complete_upload_count` (카운트) {#tuist_storage_multipart_complete_upload_count-count}

원격 스토리지로 업로드가 완료된 총 횟수입니다.

#### 태그 {#tuist-storage-multipart-complete-upload-count-tags}

| 태그 | 설명 |
|--- | ---- |
| `object_key` | 원격 스토리지에서 객체를 조회하는 키입니다. |
| `upload_id` | 멀티파트 업로드의 업로드 ID입니다. |

---

## 인증 메트릭 {#authentication-metrics}

인증과 관련된 메트릭 집합입니다.

### `tuist_authentication_token_refresh_error_total` (카운터) {#tuist_authentication_token_refresh_error_total-counter}

토큰 새로 고침 오류의 총 횟수입니다.

#### 태그 {#tuist-authentication-token-refresh-error-total-tags}

| 태그 | 설명 |
|--- | ---- |
| `cli_version` | 오류를 발생시킨 Tuist CLI의 버전입니다. |
| `reason` | 토큰 새로 고침 오류의 원인(예: `invalid_token_type` 또는 `invalid_token`)입니다. |

---

## 프로젝트 메트릭 {#projects-metrics}

프로젝트와 관련된 메트릭 집합입니다.

### `tuist_projects_total` (마지막 값) {#tuist_projects_total-last_value}

프로젝트의 총 개수입니다.

---

## 계정 메트릭 {#accounts-metrics}

계정(사용자 및 조직)과 관련된 메트릭 집합입니다.

### `tuist_accounts_organizations_total` (마지막 값) {#tuist_accounts_organizations_total-last_value}

조직의 총 개수입니다.

### `tuist_accounts_users_total` (마지막 값) {#tuist_accounts_users_total-last_value}

사용자의 총 개수입니다.


## 데이터베이스 메트릭 {#database-metrics}

데이터베이스 연결과 관련된 메트릭 집합입니다.

리포지토리 풀 메트릭은 내부적으로 100ms마다 샘플링된 후 `/metrics`에서 Prometheus로 노출됩니다. 아래의 `last_value` 메트릭은 스크랩 시점의 가장 최근 풀 상태를 보여줍니다. 하단의 부하 메트릭은 해당 100ms 샘플에서 파생된 합계로, 다음 스크랩 전에 복구되더라도 짧은 포화 구간을 쉽게 파악할 수 있게 해줍니다.

### `tuist_repo_pool_checkout_queue_length` (마지막 값) {#tuist_repo_pool_checkout_queue_length-last_value}

데이터베이스 연결 할당을 기다리며 큐에 대기 중인 데이터베이스 쿼리의 수입니다.

#### 태그 {#tuist_repo_pool_checkout_queue_length-tags}

| 태그 | 설명 |
|--- | ---- |
| `repo` | 메트릭을 생성한 리포지토리(예: `postgres`, `clickhouse_read` 또는 `clickhouse_write`). |
| `database` | 백엔드 데이터베이스 유형(예: `postgres` 또는 `clickhouse`). |

### `tuist_repo_pool_ready_conn_count` (마지막 값) {#tuist_repo_pool_ready_conn_count-last_value}

데이터베이스 쿼리에 할당될 준비가 된 데이터베이스 연결의 수입니다.

#### 태그 {#tuist_repo_pool_ready_conn_count-tags}

| 태그 | 설명 |
|--- | ---- |
| `repo` | 메트릭을 생성한 리포지토리(예: `postgres`, `clickhouse_read` 또는 `clickhouse_write`). |
| `database` | 백엔드 데이터베이스 유형(예: `postgres` 또는 `clickhouse`). |

### `tuist_repo_pool_size` (마지막 값) {#tuist_repo_pool_size-last_value}

풀에 구성된 연결의 수입니다.

#### 태그 {#tuist_repo_pool_size-tags}

| 태그 | 설명 |
|--- | ---- |
| `repo` | 메트릭을 생성한 리포지토리(예: `postgres`, `clickhouse_read` 또는 `clickhouse_write`). |
| `database` | 백엔드 데이터베이스 유형(예: `postgres` 또는 `clickhouse`). |

### `tuist_repo_pool_checkout_queue_total_samples_sum` (합계) {#tuist_repo_pool_checkout_queue_total_samples_sum-sum}

수행된 리포지토리 풀 폴링의 총 횟수(폴링마다 1씩 증가). 바쁨 또는 기아 비율을 계산할 때 분모로 사용합니다: `rate(busy_samples) / rate(total_samples)` 또는 `rate(starved_samples) / rate(total_samples)`.

#### 태그 {#tuist_repo_pool_checkout_queue_total_samples_sum-tags}

| 태그 | 설명 |
|--- | ---- |
| `repo` | 메트릭을 생성한 리포지토리(예: `postgres`, `clickhouse_read` 또는 `clickhouse_write`). |
| `database` | 백엔드 데이터베이스 유형(예: `postgres` 또는 `clickhouse`). |

### `tuist_repo_pool_checkout_queue_observed_sum` (합계) {#tuist_repo_pool_checkout_queue_observed_sum-sum}

리포지토리 풀 폴링 동안 관찰된 큐잉된 체크아웃 요청의 합계입니다. 최신 큐 길이 샘플만으로는 확인하기 어려운 짧은 풀 경합 버스트를 감지하는 데 유용합니다.

#### 태그 {#tuist_repo_pool_checkout_queue_observed_sum-tags}

| 태그 | 설명 |
|--- | ---- |
| `repo` | 메트릭을 생성한 리포지토리(예: `postgres`, `clickhouse_read` 또는 `clickhouse_write`). |
| `database` | 백엔드 데이터베이스 유형(예: `postgres` 또는 `clickhouse`). |

### `tuist_repo_pool_checkout_queue_busy_samples_sum` (합계) {#tuist_repo_pool_checkout_queue_busy_samples_sum-sum}

큐에서 대기 중인 데이터베이스 체크아웃 요청이 하나 이상 있었던 리포지토리 풀 폴링 횟수입니다.

#### 태그 {#tuist_repo_pool_checkout_queue_busy_samples_total-tags}

| 태그 | 설명 |
|--- | ---- |
| `repo` | 메트릭을 생성한 리포지토리(예: `postgres`, `clickhouse_read` 또는 `clickhouse_write`). |
| `database` | 백엔드 데이터베이스 유형(예: `postgres` 또는 `clickhouse`). |

### `tuist_repo_pool_checkout_queue_starved_samples_sum` (합계) {#tuist_repo_pool_checkout_queue_starved_samples_sum-sum}

체크아웃 요청이 큐에 쌓였고 사용 가능한 준비 상태 연결이 없었던 리포지토리 풀 폴링 횟수입니다. 이 값이 지속적으로 증가하면 일반적으로 풀이 포화되었음을 의미합니다.

#### 태그 {#tuist_repo_pool_checkout_queue_starved_samples_total-tags}

| 태그 | 설명 |
|--- | ---- |
| `repo` | 메트릭을 생성한 리포지토리(예: `postgres`, `clickhouse_read` 또는 `clickhouse_write`). |
| `database` | 백엔드 데이터베이스 유형(예: `postgres` 또는 `clickhouse`). |

### `tuist_repo_pool_db_connection_connected` (카운터) {#tuist_repo_pool_db_connection_connected-counter}

데이터베이스에 설정된 연결의 수입니다.

### `tuist_repo_pool_db_connection_disconnected` (카운터) {#tuist_repo_pool_db_connection_disconnected-counter}

데이터베이스에서 끊어진 연결의 수입니다.

#### 태그 {#tuist_repo_pool_db_connection_connected_and_disconnected-tags}

| 태그 | 설명 |
|--- | ---- |
| `tag` | 메트릭을 생성한 리포지토리를 식별하는 DBConnection 리스너 태그입니다. |

## HTTP 메트릭 {#http-metrics}

Tuist가 HTTP를 통해 다른 서비스와 상호작용할 때 관련된 메트릭 집합입니다.

### `tuist_http_request_count` (카운터) {#tuist_http_request_count-last_value}

발신 HTTP 요청의 수입니다.

### `tuist_http_request_duration_nanosecond_sum` (합계) {#tuist_http_request_duration_nanosecond_sum-last_value}

발신 요청 지속 시간의 합계(연결 할당을 기다리는 시간 포함).

### `tuist_http_request_duration_nanosecond_bucket` (분포) {#tuist_http_request_duration_nanosecond_bucket-distribution}
발신 요청 지속 시간의 분포(연결 할당을 기다리는 시간 포함).

### `tuist_http_queue_count` (카운터) {#tuist_http_queue_count-counter}

풀에서 가져온 요청의 수입니다.

### `tuist_http_queue_duration_nanoseconds_sum` (합계) {#tuist_http_queue_duration_nanoseconds_sum-sum}

풀에서 연결을 가져오는 데 걸리는 시간입니다.

### `tuist_http_queue_idle_time_nanoseconds_sum` (합계) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

연결이 검색되기를 기다리며 유휴 상태로 있던 시간입니다.

### `tuist_http_queue_duration_nanoseconds_bucket` (분포) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

풀에서 연결을 가져오는 데 걸리는 시간입니다.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (분포) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

연결이 검색되기를 기다리며 유휴 상태로 있던 시간입니다.

### `tuist_http_connection_count` (카운터) {#tuist_http_connection_count-counter}

설정된 연결의 수입니다.

### `tuist_http_connection_duration_nanoseconds_sum` (합계) {#tuist_http_connection_duration_nanoseconds_sum-sum}

호스트에 대한 연결을 설정하는 데 걸리는 시간입니다.

### `tuist_http_connection_duration_nanoseconds_bucket` (분포) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

호스트에 대한 연결을 설정하는 데 걸리는 시간의 분포입니다.

### `tuist_http_send_count` (카운터) {#tuist_http_send_count-counter}

풀의 연결에 할당되어 전송된 요청의 수입니다.

### `tuist_http_send_duration_nanoseconds_sum` (합계) {#tuist_http_send_duration_nanoseconds_sum-sum}

풀의 연결에 할당된 후 요청이 완료되는 데 걸리는 시간입니다.

### `tuist_http_send_duration_nanoseconds_bucket` (분포) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

풀의 연결에 할당된 후 요청이 완료되는 데 걸리는 시간의 분포입니다.

### `tuist_http_receive_count` (카운터) {#tuist_http_receive_count-counter}

전송된 요청에서 수신된 응답의 수입니다.

### `tuist_http_receive_duration_nanoseconds_sum` (합계) {#tuist_http_receive_duration_nanoseconds_sum-sum}

응답을 수신하는 데 소요된 시간입니다.

### `tuist_http_receive_duration_nanoseconds_bucket` (분포) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

응답을 수신하는 데 소요된 시간의 분포입니다.

### `tuist_http_queue_available_connections` (마지막 값) {#tuist_http_queue_available_connections-last_value}

큐에서 사용 가능한 연결의 수입니다.

### `tuist_http_queue_in_use_connections` (마지막 값) {#tuist_http_queue_in_use_connections-last_value}

사용 중인 큐 연결의 수입니다.
