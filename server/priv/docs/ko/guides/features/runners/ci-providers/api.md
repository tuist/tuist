---
{
  "title": "API",
  "titleTemplate": ":title · CI 제공업체 · 러너 · 기능 · 가이드 · Tuist",
  "description": "자체 Git 포지 또는 오케스트레이터에서 Tuist 러너로 작업을 실행하세요: 하나의 API 요청으로 작업을 생성하고 웹훅으로 후속 처리할 수 있습니다."
}
---
# API {#api}

<!-- @snippet: ./_invite-only -->

자체 러너 프로토콜이 없는 Git 포지, 병합 대기열 및 에이전트 오케스트레이터는 Tuist Runners에서 직접 작업을 실행할 수 있습니다. 한 번의 요청으로 작업을 생성하면, 선택한 <.localized_link href="/guides/features/runners/profiles">프로필</.localized_link>의 Tuist 머신이 커밋을 체크아웃하고 스크립트를 실행하며, Tuist는 결과를 웹훅 엔드포인트로 보고합니다.

## 작업 실행 {#run-a-job}

1. **계정 토큰 생성**, 범위: `account:runners:write`

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **작업 생성.** 일반적인 호출자는 푸시 훅에서 이 작업을 수행하며, 머신이 리포지토리를 클론할 수 있도록 단명 토큰을 사용합니다.

   ```bash
   curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs \
     -H "Authorization: Bearer $TUIST_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "profile": "tuist-macos",
       "repository_url": "https://git.example.com/acme/app.git",
       "clone_token": "<short-lived token>",
       "commit_sha": "4f1c2d0e9b8a7c6d5e4f3a2b1c0d9e8f7a6b5c4d",
       "ref": "refs/heads/main",
       "name": "test",
       "script": "mise install\nmise run test",
       "secrets": { "SIGNING_KEY": "..." },
       "timeout_minutes": 30,
       "idempotency_key": "acme/app:4f1c2d0e:test"
     }'
   ```

   응답에는 `workflow_job_id`이 포함된 작업 정보가 반환됩니다. Tuist 대시보드의 **Runners** 섹션에 즉시 표시되며, 해당 프로필의 머신이 사용 가능해지면 바로 시작됩니다. 웜 머신은 보통 몇 초 내에 작업을 시작합니다.

3. **작업 추적.** <.localized_link href="/guides/integrations/webhooks">웹훅 엔드포인트</.localized_link>를 `runner_job.started` 및 `runner_job.completed`에 구독하세요. 완료 이벤트에는 작업의 `conclusion`가 포함됩니다: `success`, `failure` 또는 `cancelled`. 또한 `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}`를 폴링하고 `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs`에서 로그를 읽을 수 있습니다.

## Git 포지 통합 {#integrate-a-git-forge}

러너 프로토콜이 없는 포지는 작은 브리지를 통해 연결되며, 이는 포지 자체의 서비스이거나 훅에서 호출하는 함수일 수 있습니다.

1. **푸시 시**, 포지의 푸시 훅이 브리지에 도달합니다. 브리지는 훅을 검증하고, 커밋에 필요한 검사를 결정하며, 작업 타임아웃 후에 만료되는 리포지토리용 읽기 전용 클론 토큰을 발급합니다.
2. **각 검사마다**, 브리지는 `idempotency_key`를 `<repository>:<commit>:<check>`로 설정하여 작업을 생성하므로, 다시 전달된 훅은 새로운 작업을 생성하지 않습니다. 반환된 `workflow_job_id`를 저장하고 포지에서 검사를 대기 중으로 표시할 수 있습니다.
3. **`runner_job.started` 및 `runner_job.completed` 발생 시**, 브리지는 엔드포인트의 비밀 키로 `Tuist-Signature` 헤더를 검증하고, `workflow_job_id` 또는 `idempotency_key`로 검사를 찾아 `conclusion`로 포지의 커밋 상태를 업데이트합니다. 상태를 Tuist 대시보드의 작업 페이지와 연결할 수 있습니다.
4. **푸시가 커밋을 대체할 때**, 브리지는 이전 커밋용으로 생성된 작업을 취소합니다.

## 작업 실행 방식 {#how-the-job-runs}

머신은 HTTPS를 통해 `repository_url`에서 `commit_sha`를 가져옵니다. 서버가 SHA로 커밋을 제공하지 않으면, 커밋을 포함해야 하는 `ref`를 대신 가져옵니다. `clone_token`(제공한 경우)는 `Authorization: Bearer <token>`로 리포지토리 호스트에만 전송됩니다. 스크립트나 작업 로그에는 절대 노출되지 않습니다.

스크립트는 체크아웃 루트에서 로그인 셸로 Bash를 통해 `set -eo pipefail` 옵션과 함께 실행됩니다. 스크립트가 0이 아닌 상태로 종료되거나 `timeout_minutes`(기본값 60, 최대 360)을 초과하면 작업이 실패합니다. `env` 및 `secrets` 외에도 스크립트는 `CI=true`, `TUIST_JOB_ID`, `TUIST_JOB_NAME`, `TUIST_JOB_REPOSITORY_URL`, `TUIST_JOB_REF` 및 `TUIST_JOB_COMMIT_SHA`를 사용할 수 있습니다. `secrets`의 값은 작업 로그에서 마스킹됩니다.

## 재시도 및 멱등성 {#idempotency}

각 작업에 용도를 나타내는 `idempotency_key`(예: `<repository>:<commit>:<check>`)를 부여하세요. 계정에서 이미 사용된 키로 요청하면 기존 작업이 상태 코드 201 대신 200으로 반환되며, 새 작업이 생성되지 않습니다. 이를 통해 푸시 훅이 중복 작업 위험 없이 요청을 재시도 큐로 전달할 수 있습니다.

웹훅 배달은 엔드포인트가 2xx 상태로 응답할 때까지 재시도되므로, 이벤트가 여러 번 도착할 수 있습니다. 엔벨로프의 `id` 또는 이벤트 유형과 결합된 작업의 `workflow_job_id`를 사용하여 중복을 제거하세요.

## 작업 취소 {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

어떤 머신도 시작하지 않은 작업은 즉시 취소됩니다. 실행 중인 작업은 몇 초 내에 중지되며, 완료 이벤트는 `cancelled`를 보고합니다. 24시간 이내에 어떤 머신도 시작하지 않은 작업은 자동으로 취소됩니다.

## 캐싱 및 신뢰 {#trust}

리포지토리에 푸시할 수 있는 누구나 작업이 실행하는 내용을 변경할 수 있으므로, API 작업은 신뢰할 수 없는 것으로 취급됩니다. 계정의 공유 <.localized_link href="/guides/features/runners/cache-volumes">캐시 볼륨</.localized_link>이나 캐시 서명 권한을 받지 못합니다. 작업의 비밀 값, 스크립트 및 클론 토큰은 암호화되어 저장되며 작업이 완료되면 삭제됩니다.
