---
{
  "title": "웹훅",
  "titleTemplate": ":title | 통합 | 가이드 | Tuist",
  "description": "Tuist 이벤트에 HTTPS 엔드포인트를 구독하고, 서명된 페이로드로 전달을 검증하며, 대시보드에서 모든 시도 내역을 확인하세요."
}
---
# 웹훅 {#webhooks}

웹훅을 사용하면 시스템이 Tuist 내부의 변경 사항이 발생하는 즉시 반응할 수 있습니다. 새로운 테스트 케이스가 관찰되거나, 미리보기 업로드가 완료되거나, 불안정한 테스트가 수정되는 등 관련 이벤트가 발생하면 Tuist는 해당 이벤트 유형을 구독한 모든 엔드포인트에 HTTP POST 요청을 보냅니다. 요청 본문은 JSON 봉투 형식이며, 각 전달에는 엔드포인트의 서명 비밀 키로 검증할 수 있는 서명 헤더가 포함됩니다.

대상 URL을 등록하고 원하는 이벤트를 선택하면, Tuist가 서명, 재시도 및 전달 감사 로그를 처리합니다.

## 웹훅 수신 단계 {#steps}

다음 단계에 따라 앱에서 이벤트 알림 수신을 시작할 수 있습니다:

1. [앱에서 수신하려는 이벤트를 식별합니다](#event-types).
2. 로컬 서버에서 HTTP 엔드포인트(URL)로 [웹훅 엔드포인트를 생성합니다](#create-an-endpoint).
3. [페이로드를 파싱](#payload)하고 [2xx 상태 코드](#responding)를 반환하여 Tuist가 전달을 성공으로 표시하도록 Tuist의 요청을 처리합니다.
4. 모든 요청에서 [서명을 검증](#verify-signature)하여 Tuist에서 발송되었음을 확인합니다.
5. 빌드 중에 디버깅할 때 Tuist 대시보드의 [이벤트 로그](#inspect-deliveries)를 사용합니다.

## 이벤트 유형 {#event-types}

Tuist는 이벤트가 설명하는 리소스별로 이벤트를 그룹화합니다. 봉투 내의 `type` 필드는 점 표기법(`{resource}.{action}`)을 사용하며, 이는 대시보드에서 구독할 때 사용하는 값과 동일합니다.

{{webhook_events_table}}

추가적인 이벤트 유형이 곧 제공될 예정입니다. 현재 제공되지 않는 이벤트 유형이 필요하면 알려주시면 카탈로그에 추가하겠습니다.

## 엔드포인트 생성 {#create-an-endpoint}

엔드포인트는 계정별로 구성됩니다. 계정 설정에서 **웹훅**을 열고 **엔드포인트 추가**를 클릭한 후 다음 정보를 입력하세요:

- **이름** — 목록에서 엔드포인트가 표시되는 이름입니다.
- **엔드포인트 URL** — `https://`를 사용해야 합니다.
- **수신할 이벤트** — 특정 이벤트를 선택하거나 그룹 수준에서 **모두 선택**을 사용합니다. Tuist는 구독된 이벤트 중 하나가 발생할 때만 엔드포인트에 POST 요청을 보냅니다.

![각각 두 개의 이벤트에 구독된 두 개의 웹훅 엔드포인트가 있는 엔드포인트 목록](/images/guides/integrations/webhooks/endpoints.png)

저장하면 Tuist가 새로운 서명 비밀 키를 생성하고 한 번만 표시합니다. 이를 애플리케이션 구성에 즉시 복사하세요. 대시보드에서는 다시 조회할 수 없습니다. 비밀 키를 잃어버린 경우 엔드포인트 작업 메뉴에서 **비밀 키 회전**을 사용하여 새 키를 발급받으세요.

<img src="/images/guides/integrations/webhooks/create-endpoint.png" alt="이름, URL 및 그룹화된 이벤트 유형 체크박스가 있는 웹훅 엔드포인트 생성 모달" style="max-width: 500px;" />

## 페이로드 {#payload}

모든 전달은 단일 JSON 객체입니다. 이 봉투는 전달의 중복 제거, 라우팅 및 감사를 위해 사용할 수 있는 메타데이터 내에 이벤트별 리소스 스냅샷을 감싸고 있습니다:

| 필드     | 설명                                                              |
| --------- | ------------------------------------------------------------------------ |
| `id`      | 이 전달에 고유한 UUID입니다. 재시도가 발생할 때 중복을 제거하는 데 사용합니다. |
| `type`    | 점 표기법의 이벤트 유형(예: `test_case.updated`).                         |
| `created` | Tuist가 전달을 큐에 넣은 시점의 Unix 타임스탬프(초)입니다.           |
| `object`  | 리소스 스냅샷입니다. 구조는 이벤트 유형에 따라 달라집니다.              |

각 이벤트 유형에 대한 정확한 페이로드 스키마는 [Tuist API 참조](https://tuist.dev/api/docs#section/Webhook-events)의 **웹훅 이벤트** 섹션에 문서화되어 있습니다. 모든 이벤트에는 `components.schemas` 아래의 일치하는 `WebhookXxxEvent` 스키마가 있으며, 코드 생성기에서 `$ref`로 참조할 수 있습니다.

예를 들어 `test_case.updated` 페이로드에는 쓰기를 유발한 표준 전환(`marked_flaky`, `muted`, `unskipped`, …)을 나열하는 `events` 배열과 함께 수신자가 수동 편집과 자동화 기반 변경 사항을 구분할 수 있도록 `actor_id` 및 `alert_id`도 포함됩니다.

각 요청에는 다음 HTTP 헤더도 포함됩니다:

| 헤더              | 설명                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------------- |
| `Content-Type`      | 항상 `application/json`입니다.                                                                    |
| `User-Agent`        | `Tuist-Webhooks/1.0`.                                                                         |
| `Tuist-Event-Id`    | 본문의 `id`와 동일한 UUID입니다. 페이로드를 파싱하기 전에 헤더를 로깅할 경우 유용합니다.     |
| `Tuist-Event-Type`  | 본문의 `type`와 동일한 문자열입니다.                                                            |
| `Tuist-Signature`   | HMAC-SHA256 서명으로, `t={timestamp},v1={hex_digest}` 형식입니다. 아래를 참조하세요.          |

## 웹훅 응답 {#responding}

전달을 확인하려면 엔드포인트에서任意의 `2xx` 상태 코드를 반환해야 합니다. `2xx` 범위 밖의 모든 응답은 연결 실패 및 시간 초과와 함께 전달 실패로 처리되어 재시도됩니다. Tuist는 `3xx` 응답을 따르지 않으므로, 리다이렉트하지 않고 정규 URL에서 직접 응답하세요.

핸들러를 **빠르게** 유지하세요: Tuist는 응답을 위해 최대 **10초**까지 기다립니다. 다른 API 호출, 데이터베이스 업데이트, 알림 전송 등 무거운 작업이 필요한 경우, 요청을 수락하고 비동기적으로 처리하세요. 조기에 응답하면 다운스트림 서비스의 일시적인 지연에도 견고하게 대응할 수 있습니다.

## 서명 검증 {#verify-signature}

엔드포인트 URL을 아는 사람은 누구나 해당 URL로 POST 요청을 보낼 수 있습니다. 서명 비밀 키를 사용하면 Tuist에서 오지 않은 요청을 서버에서 거부할 수 있습니다.

Tuist는 모든 요청에 대해 다음을 계산합니다:

```
signed_payload = "{timestamp}.{raw_request_body}"
signature      = HMAC-SHA256(signing_secret, signed_payload)
header         = "t={timestamp},v1={hex(signature)}"
```

귀하의 측에서 검증하려면:

1. `Tuist-Signature` 헤더를 읽고 `t=`(타임스탬프)와 `v1=`(16진수 다이제스트) 부분으로 분할하세요.
2. 타임스탬프가 서버의 현재 시간과 **5분** 이상 차이가 나면 요청을 거부하세요. 이는 재생 공격 창을 *제한*하지만 완전히 닫지는 않으므로, 아래에 설명된 멱등성과 함께 사용하세요.
3. `HMAC-SHA256(signing_secret, "{timestamp}.{raw_body}")`를 다시 계산하고 **일정 시간** 내에 다이제스트와 비교하세요.
4. 페이로드 `id`(`Tuist-Event-Id` 헤더로도 노출됨)를 기준으로 전달을 중복 제거하세요. 이 ID는 재시도 동안 안정적이므로, 이미 처리한 ID를 저장하면 허용 오차 범위 내에서 캡처된 요청이 재생되는 것을 방지하고 재시도 시 이중 처리로부터 보호할 수 있습니다.

> [!IMPORTANT] USE THE RAW BODY
> 서명은 Tuist가 보낸 바이트를 기반으로 계산됩니다. 웹 프레임워크가 검증 전에 JSON을 다시 파싱하고 직렬화하면 다이제스트가 일치하지 않습니다. 원본 본문(예: Rack의 `request.body.read`, Express의 원본 `Buffer`)을 캡처하여 검증기에 전달하세요.

Node.js용 참조 검증기 — 수신기가 작성된 언어에 맞게 동일한 네 단계(헤더 파싱, 타임스탬프 편차 확인, HMAC 재계산, 일정 시간 내 비교)를 변환하세요:

```javascript
import crypto from "node:crypto";

function verifyTuistSignature(rawBody, header, secret, toleranceSeconds = 300) {
  const parts = Object.fromEntries(
    header.split(",").map((kv) => kv.split("=", 2))
  );
  const timestamp = Number(parts.t);
  const signature = parts.v1;
  if (!timestamp || !signature) return false;

  const drift = Math.abs(Math.floor(Date.now() / 1000) - timestamp);
  if (drift > toleranceSeconds) return false;

  const expected = crypto
    .createHmac("sha256", secret)
    .update(`${timestamp}.${rawBody}`)
    .digest("hex");

  const a = Buffer.from(expected, "hex");
  const b = Buffer.from(signature, "hex");
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
```

## 재시도 {#retries}

Tuist는 non-`2xx` 상태를 반환하거나, 시간이 초과되거나, 연결에 실패한 모든 전달을 재시도합니다. 일정은 고정되어 있습니다:

| 시도 | 전송 전 대기 시간 |
| ------- | ------------------- |
| 1       | (즉시)         |
| 2       | 1분            |
| 3       | 5분           |
| 4       | 30분          |
| 5       | 2시간             |
| 6       | 8시간             |
| 7       | 24시간            |

7번째 시도가 실패하면 전달은 영구적으로 실패로 표시됩니다. 모든 시도는 전송된 시점의 타임스탬프로 서명되므로, 재생 보호 창은 재시도에서도 여전히 적용되며 넓힐 필요가 없습니다.

## 전달 검사 {#inspect-deliveries}

**웹훅** 페이지에서 엔드포인트를 열어 전달 기록을 확인하세요. 상세 페이지에는 다음 정보가 표시됩니다:

- 대상 URL, 마스킹된 서명 비밀 키, 구독한 이벤트 및 생성 날짜가 포함된 **요약 카드**.
- 선택한 시간 범위를 기준으로 한 누적 합계와 실패 횟수가 포함된 **전달 차트**.
- 상태, 이벤트 유형 또는 이벤트 ID로 필터링할 수 있는 **이벤트 테이블**.

![요약 카드와 이벤트 전달 차트를 보여주는 웹훅 엔드포인트 상세 페이지](/images/guides/integrations/webhooks/endpoint-detail.png)

이벤트를 클릭하면 해당 시도의 전체 요청과 응답(Tuist가 보낸 정확한 페이로드, 헤더, 업스트림 상태 코드 및 응답 본문)을 확인할 수 있습니다. 이는 서버가 본 것과 동일한 데이터이므로, 서명 검증 불일치 또는 5xx 업스트림 오류를 디버깅하는 가장 빠른 방법입니다.

![요약, 요청 헤더 및 본문, 그리고 업스트림 응답을 보여주는 웹훅 이벤트 상세 페이지](/images/guides/integrations/webhooks/event-detail.png)

통합 문제를 디버깅할 때 과거 기록을 조회할 수 있도록 전달 기록은 무기한 보관됩니다. 다운스트림 시스템에서 내구성이 필요한 복사본(예: 규정 준수용)이 필요한 경우, 도착하는 대로 자체 인프라에서 전달 내용을 캡처하세요.

## 엔드포인트 회전 또는 삭제 {#rotate-or-delete}

두 작업 모두 엔드포인트 행의 케밥 메뉴와 엔드포인트 상세 페이지에 있습니다:

- **비밀 키 회전** — 새로운 서명 비밀 키를 생성하고 한 번만 표시합니다. 기존 소비자는 업데이트하기 전까지 검증에 실패하므로, 배포와 함께 회전을 계획하세요.
- **엔드포인트 삭제** — 엔드포인트를 제거하고 전달을 중지합니다. 이미 기록된 전달 시도는 표준 보존 기간이 만료될 때까지 유지됩니다.

## 보안 주의 사항 {#security}

- 엔드포인트 URL은 HTTPS여야 합니다. Tuist는 평문 대상으로는 전달을 거부합니다.
- Tuist는 각 전달 전에 대상 호스트 이름을 해결하며 루프백, RFC1918, 링크 로컬, ULA 및 클라우드 메타데이터 주소(`169.254.169.254`, `fd00::/8`, …)를 거부합니다. 이를 통해 잘못 구성된 웹훅이 Tuist 서버를 실행하는 호스트를 스캔하거나 공격하는 데 사용되는 것을 방지합니다.
- 엔드포인트 URL과 서명 비밀 키는 저장 시 암호화됩니다. 이들은 베어러 자격 증명으로 간주되어 GDPR/CCPA 데이터 내보내기에서 제외됩니다.
- 서명 비밀 키는 한 번만 표시됩니다. 비밀번호처럼 취급하여 리포지토리가 아닌 비밀 관리자에 저장하세요.
