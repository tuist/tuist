---
{
  "title": "Rust Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky Cargo tests using CI history."
}
---
# Rust 불안정 테스트 {#rust-flaky-tests}

Tuist는 일관되지 않은 Cargo 테스트 결과를 감지하고 **Tests → Flaky Tests**에서 조사할 수 있도록 도와줍니다.

> [!IMPORTANT] Requirements
> - <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>를 구성하세요.

## 불안정성 감지 방식 {#how-it-works}

Tuist는 동일한 커밋에 대한 CI 실행을 비교합니다. 한 번의 실행에서는 통과하지만 다른 실행에서는 실패하는 테스트는 불안정한 것으로 표시될 수 있습니다.

일반적인 명령어를 통해 각 실행을 보고하세요:

```sh
tuist cargo test --workspace
```

Cargo는 실패한 테스트를 자동으로 재시도하지 않습니다. 동일한 커밋에서 CI 작업을 다시 실행하면 교차 실행 감지를 위한 또 다른 결과를 얻을 수 있습니다.

## 불안정 테스트 관리 {#managing-flaky-tests}

### 자동 해제

감지 및 복구는 프로젝트의 "Flaky test detection" 자동화를 통해 실행됩니다. 기본적으로 불안정 플래그는 14일 동안 재발생하지 않으면 해제됩니다. **Settings → Automations**에서 복구 기간과 작업을 편집하세요.

### 수동 관리

**Tests → Flaky Tests**를 열어 테스트 기록을 확인하세요. 상세 페이지에서 수동으로 불안정 여부를 표시하거나 해제할 수 있습니다.

## 격리 및 스트레스 테스트 {#quarantine}

상세 페이지에서 테스트를 음소거하거나 건너뛰거나, **Settings → Automations**에서 격리를 구성하세요. 다음 `tuist cargo test`은 프로젝트의 현재 격리 상태를 가져옵니다:

- **음소거된** 테스트는 여전히 실행되고 실제 결과를 보고하지만, 해당 테스트의 실패로 인해 명령어가 실패하지는 않습니다. 다른 테스트 실패, 컴파일 오류, 충돌 및 불완전한 결과는 정상적으로 실패를 유발합니다.
- **건너뛴** 테스트는 실행에서 제외되며 격리된 건너뛰기로 보고됩니다. 매칭에는 패키지, 타겟, Rust 모듈 경로 및 테스트 이름이 포함되므로 이름이 유사한 테스트도 독립적으로 유지됩니다.

음소거는 선택된 워크스페이스 패키지와 기능을 유지하며, 음소거된 타겟이 실패하더라도 선택된 모든 타겟을 실행합니다. 건너뛰기 격리는 하나의 선택된 패키지가 필요합니다. 다중 패키지 워크스페이스 명령어 대신 `tuist cargo test -p store`를 사용하세요. Tuist는 명령어를 좁히면 Cargo의 통합된 종속성 기능이 변경될 수 있으므로 다중 패키지 건너뛰기를 거부합니다.

격리는 <.localized_link href="/guides/features/test-sharding/rust">sharded Cargo runs</.localized_link>에도 적용됩니다. Tuist가 상태를 가져올 수 없는 경우 경고를 표시하고 격리 없이 실행하며, 실패는 억제되지 않습니다. 의도적으로 격리 없이 실행하려면:

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

적용을 위해서는 표준 libtest 하네스와 캡처된 기본 출력이 필요합니다. 조용함, 상세, 대체 형식 또는 캡처되지 않은 출력을 사용하는 명령어는 격리를 적용해야 할 때 실패합니다. 타겟 귀속이 모호한 경우 `-p <package>`를 사용하여 정확한 워크스페이스 패키지를 선택하세요.自定义 하네스, 패키지/타겟 이름 글롭 및 해결되지 않은 패키지 선택은 지원되지 않습니다. Doctest도 음소거하거나 건너뛸 수 있지만, Rustdoc의 테스트 필터링은 모든 가능한 예제 이름 쌍을 구별할 수 없습니다. 예제를 건너뛰면 활성화된 예제도 함께 건너뛰게 되거나 부분적인 doctest 제외가 `--exact`를 사용하는 경우, Tuist는 건너뛴 예제를 실행하거나 활성화된 테스트를 묵시적으로 생략하는 대신 진단 정보와 함께 실패합니다. 조사 중에는 위의 재정의 방법을 사용하세요.

Tuist는 새로운 Cargo 테스트에 대해 스트레스 테스트를 수행하지 않습니다. 조사 중에 실패하는 테스트를 반복하려면 Cargo 테스트 필터를 사용하세요:

```sh
tuist cargo test -p store rejects_invalid_token
```

## Slack 알림 {#notifications}

테스트가 불안정해질 때 팀에 알림을 보내도록 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack flaky test alerts</.localized_link>를 구성하세요.
