---
{
  "title": "Elixir 불안정한 테스트",
  "titleTemplate": ":title · 불안정한 테스트 · 테스트 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Mix로 빌드한 Elixir 프로젝트에서 불안정한 테스트를 감지하고 관리합니다."
}
---
# Elixir 불안정한 테스트 {#elixir-flaky-tests}

> [!IMPORTANT]
> **필수 조건**
>
> - 테스트 실행 결과를 보고하려면 <.localized_link href="/guides/get-started/elixir-project">공유 Elixir 설정</.localized_link>을 완료하세요

<!-- @snippet: ./_intro -->

![Phoenix 애플리케이션의 불안정한 테스트](/images/guides/features/elixir/flaky-tests.png)

## 불안정성 감지 방식 {#how-it-works}

Tuist는 두 가지 방식으로 불안정한 테스트를 감지합니다:

### 테스트 재시도 {#test-retries}

ExUnit은 각 테스트를 한 번만 실행하므로, 간헐적으로 실패하는 테스트는 완전히 깨진 테스트와 동일하게 보입니다. 재시도를 활성화하면 Hex 패키지가 설정한 횟수만큼 실패한 테스트를 다시 실행합니다. 재시도에서 통과한 테스트는 불안정한 것으로 보고되며, 모든 실패한 테스트가 결국 통과하면 실행은 성공합니다.

재시도는 기본적으로 비활성화되어 있습니다. 이를 활성화하려면 `mix.exs`의 기존 Tuist 옵션에 `test_retries`을 추가하세요:

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

또는 플래그나 환경 변수를 사용하여 단일 실행에 적용할 수 있습니다:

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

플래그는 환경 변수보다 우선하며, 환경 변수는 `mix.exs`보다 우선합니다.

실패한 테스트만 다시 실행되며, 이는 `mix test --failed`이 테스트를 실행하는 방식과 동일합니다. 대시보드에는 각 테스트의 시도 횟수와 소요 시간이 표시됩니다. `--max-failures`로 인해 ExUnit이 조기에 중단한 실행은 재시도되지 않습니다. 실패한 테스트가 모두 타임아웃된 실행도 재시도되지 않는데, 이는 각 재시도가 모든 타임아웃을 다시 기다려야 하기 때문입니다. 또한 `--warnings-as-errors`를 사용하면 재시도가 건너뛰어지며, 이 경우 `mix test`가 더 이상 강제되지 않습니다. umbrella 프로젝트의 루트에서도 재시도가 건너뛰어지므로, 재시도를 수행하려면 해당 프로젝트 내의 개별 애플리케이션에서 테스트를 실행하세요.

![불안정한 ExUnit 테스트 및 그 기록](/images/guides/features/elixir/flaky-test-case.png)

### 교차 실행 감지 {#cross-run-detection}

테스트 재시도가 없어도 Tuist는 동일한 커밋에 대한 다양한 CI 실행 간 결과를 비교하여 불안정한 테스트를 감지할 수 있습니다. 테스트가 한 CI 실행에서는 통과하지만 동일한 커밋 및 스킴 레이블(`--scheme`)에 대한 다른 실행에서는 실패하면, 해당 실패 실행은 불안정한 것으로 표시됩니다.

이는 재시도로 포착될 만큼 일관되게 실패하지는 않지만 여전히 간헐적인 CI 실패를 유발하는 불안정한 테스트를 포착하는 데 특히 유용합니다.

<!-- @snippet: ./_managing -->

## 불안정한 테스트 격리 {#quarantining}

격리는 수정 중인 동안 불안정한 테스트가 CI를 차단하지 않도록 합니다. 대시보드의 테스트 페이지에서 상태를 **음소거** 또는 **건너뛰기**로 변경하거나, **설정 → 자동화**에서 테스트가 불안정해지면 음소거하거나 건너뛰고 복구되면 다시 활성화하는 자동화를 구성할 수 있습니다. 테스트를 실행하기 전에 `mix test`는 프로젝트의 모든 격리된 테스트를 읽고 적용합니다:

- **음소거**: 테스트가 실행되고 실패가 여전히 보고되지만, 실패가 음소거된 테스트뿐인 실행은 통과합니다. 재시도는 여전히 실패하는 음소거 테스트를 다시 실행하므로, 불안정한 테스트가 통과하여 불안정한 것으로 보고될 수 있습니다.
- **건너뛰기**: 테스트가 실행되지 않습니다. `mix test`는 실행 시작 전에 건너뛴 테스트를 나열합니다.

```text
Tuist: skipping 1 quarantined test:
  MyApp.CheckoutTest: create_order/2 times out
Tuist: 1 muted test run, and their failures do not fail the run.
```

음소거되지 않은 테스트가 실패하거나 `--max-failures`로 인해 ExUnit이 조기에 중단되면 실행은 평소와 같이 실패합니다.

> [!WARNING]
> **제한 사항**
>
> - 최근 버전의 Hex 패키지만이 격리를 적용합니다. 이전 버전은 음소거 및 건너뛰기 테스트를 다른 테스트와 동일하게 실행하므로, 음소거된 테스트의 실패는 여전히 실행을 실패시킵니다. 이에 의존하기 전에 `tuist_ex`를 업데이트하세요.
> - 음소거 테스트는 `--warnings-as-errors`와 함께 사용하거나 umbrella 프로젝트의 루트에서 실행할 때 적용되지 않습니다. 이러한 경우 실패는 실행을 실패시킵니다. 대신 umbrella의 각 애플리케이션 내부에서 테스트를 실행하세요.
> - 건너뛰기는 모듈이 아닌 describe 블록과 이름으로 테스트를 일치시킵니다. 다른 모듈에 동일한 describe 블록과 이름을 가진 테스트도 건너뜁니다. [건너뛰기가 테스트를 선택하는 방법](#how-skipping-selects-tests)을 참조하세요.
> - 건너뛴 테스트는 `--only`, `--include` 또는 `path:line`로 선택하거나 `test`로 선언되지 않은 경우(예: StreamData `property`)에도 여전히 실행됩니다.
> - `mix test`가 격리된 테스트를 읽을 수 없는 경우 모든 테스트를 실행하고 모든 실패를 계산합니다.
> - 격리된 테스트를 읽으려면 공개 프로젝트라도 자격 증명이 필요합니다. `TUIST_TOKEN`, `mix tuist.login` 세션 또는 지속적 통합 신원 토큰 없이 실행하면 격리가 적용되지 않습니다. 여기에는 일반적으로 시크릿 없이 실행되는 포크의 풀 리퀘스트도 포함됩니다.
> - `--cover`를 사용하면 건너뛴 테스트가 제거된 것으로 간주됩니다: 해당 테스트만 커버했던 라인은 커버되지 않은 것으로 보고됩니다.
>
> `mix test`는 요약 후에 실수로 제외된 테스트와 어쨌든 실행된 건너뛴 테스트의 이름을 표시합니다.

### 건너뛰기가 테스트를 선택하는 방법 {#how-skipping-selects-tests}

건너뛴 테스트는 전체 이름에 대한 ExUnit 필터(예: `--exclude "test:test create_order/2 times out"`)로 제외됩니다. ExUnit 필터는 모듈을 일치시킬 수 없으므로:

- 다른 모듈에 동일한 describe 블록과 이름을 가진 테스트도 제외됩니다. `mix test`는 실행 후에 이러한 테스트의 이름을 표시합니다.
- `--only`, `--include` 또는 `path:line`로 선택한 테스트는 ExUnit이 제외 필터 이후에 포함 필터를 적용하므로 건너뛰어져도 실행됩니다. `test`로 선언되지 않은 테스트(예: StreamData `property`)도 마찬가지입니다. `mix test`는 실행 후에 이러한 테스트의 이름을 표시합니다.

### 격리된 테스트 다시 실행 {#running-quarantined-tests-again}

모든 테스트를 실행하고 모든 실패를 계산하려면 `--no-quarantine`를 전달하세요. 예를 들어 수정 사항을 확인할 때 사용합니다:

```bash
mix test --no-quarantine
```

페이지에서 테스트를 **활성화** 상태로 반환하여 이후 실행에 포함시키세요. 건너뛴 테스트는 다시 실행될 때까지 새로운 결과를 생성하지 않습니다.

`mix test`가 격리된 테스트를 읽을 수 없는 경우 경고를 출력하고 격리 없이 모든 테스트를 실행합니다. 자격 증명이나 구성된 프로젝트가 없으면 경고 없이 모든 테스트를 실행합니다.

Hex 패키지는 아직 새 테스트에 대한 스트레스 테스트를 수행하지 않습니다.

<!-- @snippet: ./_slack -->

## 불안정 상태 쿼리 {#querying}

데이터는 HTTP를 통해 제공됩니다. 전체 경로, 필터 및 응답 필드 목록은 API 참조의 [테스트 케이스 엔드포인트](https://tuist.dev/api/docs#tag/test-cases)를 참조하세요. 테스트 케이스를 불안정으로 표시하거나 해제하려면 `is_flaky`와 함께 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`를 전송하거나 `update_test_case` 모델 컨텍스트 프로토콜 도구를 사용하세요.
