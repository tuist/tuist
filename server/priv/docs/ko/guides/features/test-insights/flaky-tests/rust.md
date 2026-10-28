---
{
  "title": "Rust Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky Cargo tests using CI history."
}
---
# Rust 불안정한 테스트 {#rust-flaky-tests}

Tuist는 일관되지 않은 Cargo 테스트 결과를 감지하고 **테스트 → 불안정한 테스트**에서 이를 조사하는 데 도움을 줄 수 있습니다.

> [!IMPORTANT] Requirements
> - <.localized_link href="/guides/features/test-insights/rust">Rust 테스트 인사이트</.localized_link>를 구성하세요.

## 불안정성 감지 작동 방식 {#how-it-works}

Tuist는 동일한 커밋에 대한 CI 실행을 비교합니다. 한 번의 실행에서는 통과하지만 다른 실행에서는 실패하는 테스트는 불안정한 것으로 표시될 수 있습니다.

일반적인 명령어를 통해 각 실행을 보고하세요:

```sh
tuist cargo test --workspace
```

Cargo는 실패한 테스트를 자동으로 재시도하지 않습니다. 동일한 커밋에서 CI 작업을 다시 실행하면 교차 실행 감지를 위한 또 다른 결과를 얻을 수 있습니다.

## 불안정한 테스트 관리 {#managing-flaky-tests}

### 자동 해제

감지 및 복구는 프로젝트의 "불안정한 테스트 감지" 자동화를 통해 실행됩니다. 기본적으로 불안정 플래그는 14일 동안 다시 트리거되지 않으면 해제됩니다. **설정 → 자동화**에서 복구 기간과 작업을 편집하세요.

### 수동 관리

**테스트 → 불안정한 테스트**를 열어 테스트 기록을 검사하세요. 상세 페이지에서 수동으로 불안정한 상태로 표시하거나 해제할 수 있습니다.

## 격리 및 스트레스 테스트 {#quarantine}

Cargo 통합은 아직 격리를 적용하지 않습니다: 대시보드에서 음소거되거나 건너뛴 테스트는 여전히 실행되며, 해당 실패는 결과에 여전히 영향을 미칩니다. 또한 새 테스트에 대한 스트레스 테스트도 수행하지 않습니다. 조사 중인 실패하는 테스트를 반복하려면 Cargo 테스트 필터를 사용하세요:

```sh
tuist cargo test -p store rejects_invalid_token
```

## Slack 알림 {#notifications}

테스트가 불안정해질 때 팀에 알림을 보내도록 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack 불안정한 테스트 알림</.localized_link>을 구성하세요.
