---
{
  "title": "Once 캐시",
  "titleTemplate": ":title · 캐시 · 기능 · 가이드 · Tuist",
  "description": "Tuist의 원격 캐시를 사용해 Once 액션 결과를 개발자 머신과 CI 간에 공유하세요."
}
---
# Once 캐시 {#once-cache}

Once는 로컬에서 결과를 재사용할 수 있지만, 개발자의 로컬 캐시는 팀원이나 새로 생성된 CI 작업자에게 공유되지 않습니다. Tuist는 공유 원격 캐시를 제공하여 동일한 작업을 한 머신에서만 실행하면 되도록 합니다.

## 설정 {#setup}

<.localized_link href="/guides/get-started/once-project#connect-the-project">Once 시작하기</.localized_link>를 완료한 후, 저장소의 `once.toml`에서 캐시 바인딩을 확인하세요:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.cache]
provider = "tuist"
```

`once auth login --provider tuist`로 인증하세요. Tuist 실행 파일이나 추가 캐시 플러그인이 필요하지 않습니다. 동일한 공급자는 [캐싱 가능한 스크립트](https://buildonce.dev/docs/guide/scripted/caching)와 [그래프 타겟](https://buildonce.dev/docs/guide/graph)을 지원합니다.

Once에서 캐싱 가능하다고 선언된 작업만 재사용할 수 있습니다. 작업이 의존하는 입력, 출력 및 환경을 선언하세요. 원격 캐시를 구성한다고 해서 임의의 명령어가 재현 가능해지는 것은 아닙니다.

## 공유 재사용 확인 {#verify-shared-reuse}

입력과 구성이 일치하는 두 대의 머신에서 동일한 캐싱 가능한 스크립트나 그래프 타겟을 실행하세요:

```bash
once build MyApplication
```

첫 번째 머신이 공유 캐시를 채웁니다. 해당 결과를 로컬 캐시에서 찾지 못하는 두 번째 머신에서는 캐시 히트와 복원된 출력을 통해 원격 재사용이 확인됩니다. 첫 번째 머신에서만 명령어를 반복 실행하면 로컬 히트를 확인할 수 있을 뿐, Tuist가 결과를 제공했다는 것을 의미하지는 않습니다.

## 캐시 활동 검사 {#inspect-cache-activity}

Tuist 프로젝트에서 **Once 캐시**를 열어 액션 캐시 히트, 전송, 지연 시간 및 처리량을 검사하세요. 실행의 **캐시** 뷰를 열어 보고된 액션 결정과 콘텐츠 객체 활동을 검사하세요.

액션 결과와 콘텐츠 객체는 서로 다른 질문에 답합니다. 액션 결과가 누락되면 Once가 작업을 수행해야 함을 의미하며, 콘텐츠 객체 요청은 입력 또는 출력을 전송합니다. 블롭 다운로드를 실행된 액션이나 액션 캐시 히트로 간주하지 마세요.

실행의 액션 그래프와 구조화된 오류는 <.localized_link href="/guides/features/build-insights/once">Once 빌드 인사이트</.localized_link>를 참조하세요.

## 지속적 통합 {#continuous-integration}

<.localized_link href="/guides/integrations/continuous-integration#once">지속적 통합에서의 Once</.localized_link>에 설명된 대로 `TUIST_TOKEN` 또는 Once의 헤드리스 OIDC 로그인을 사용하세요. 자격 증명은 `once.toml`에 포함하지 마세요.

계정의 <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">캐시 업로드 정책</.localized_link>에 따라 결과를 게시할 수 있는 사용자가 결정됩니다. 읽기 전용 개발자는 캐시 작성자가 되지 않고도 CI에서 생성된 항목을 사용할 수 있습니다.

연결 재시도 및 문제 해결은 [Once의 Tuist 통합](https://buildonce.dev/docs/guide/infrastructure/tuist#connection-recovery)을 참조하세요. 재시도로 중단된 업로드를 재개할 수 있게 되지는 않습니다.
