---
{
  "title": "Gradle 불안정한 테스트",
  "titleTemplate": ":title · 불안정한 테스트 · 테스트 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist로 Gradle 프로젝트의 불안정한 테스트를 감지하고 관리하며 격리하세요."
}
---
# Gradle 불안정한 테스트 {#gradle-flaky-tests}

불안정한 테스트는 동일한 코드로 여러 번 실행했을 때 서로 다른 결과(통과 또는 실패)를 내는 테스트입니다. 이는 테스트 스위트에 대한 신뢰를 떨어뜨리고, 잘못된 실패를 조사하는 데 개발자의 시간을 낭비하게 만듭니다. Tuist는 불안정한 테스트를 자동으로 감지하고 시간이 지남에 따라 추적할 수 있도록 도와줍니다.

![불안정한 테스트 페이지](/images/guides/features/test-insights/flaky-tests-page.png)

## 불안정성 감지 방식 {#how-it-works}

Tuist는 두 가지 방식으로 불안정한 테스트를 감지합니다:

### 테스트 재시도 {#test-retries}

재시도 기능을 사용해 테스트를 실행하면 Tuist는 각 시도 결과를 분석합니다. 일부 시도에서는 실패하지만 다른 시도에서는 통과하는 테스트는 불안정한 것으로 표시됩니다.

실패한 테스트를 다시 실행하려면 [Test Retry 플러그인](https://github.com/gradle/test-retry-gradle-plugin)이나 유사한 메커니즘을 사용할 수 있습니다. Tuist는 일부 시도에서는 통과하지만 다른 시도에서는 실패하는 테스트를 감지합니다.

플러그인을 `build.gradle.kts`에 추가하세요:

```kotlin
plugins {
    id("org.gradle.test-retry") version "1.6.2"
}

tasks.test {
    retry {
        maxRetries = 3
        maxFailures = 5
        failOnPassedAfterRetry = false
    }
}
```

![불안정한 테스트 케이스 상세](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 교차 실행 감지 {#cross-run-detection}

테스트 재시도가 없어도 Tuist는 동일한 커밋과 동일한 Gradle 프로젝트에서 수행된 서로 다른 CI 실행 간 결과를 비교하여 불안정한 테스트를 감지할 수 있습니다. 동일한 커밋과 프로젝트에서 한 CI 실행에서는 통과했지만 다른 실행에서는 실패한 경우, 두 실행 모두 불안정한 것으로 표시됩니다.

동일한 테스트라도 프로젝트에 따라 결정론적으로 다르게 동작할 수 있기 때문에(예: 다른 의존성으로 컴파일된 공유 테스트 클래스나 다른 모듈 픽스처에서 실행되는 경우) Gradle 프로젝트가 비교 키의 일부로 포함됩니다. 서로 다른 Gradle 프로젝트에서 동일한 커밋을 두 번 실행한 경우는 별도의 실행 변형으로 취급되며 서로를 불안정하다고 표시하지 않습니다.

이는 재시도로 잡힐 만큼 일관되게 실패하지는 않지만 여전히 간헐적인 CI 실패를 유발하는 불안정한 테스트를 잡아내는 데 특히 유용합니다.

## 불안정한 테스트 관리 {#managing-flaky-tests}

### 자동 해제

감지와 해제는 프로젝트의 **자동화 알림**을 통해 진행됩니다. 모든 프로젝트에는 기본 "불안정한 테스트 감지" 자동화가 제공되며, 이 자동화의 *트리거*는 테스트를 불안정하다고 표시하고 *복구*는 테스트가 구성된 복구 기간(기본값 **14일**) 동안 다시 트리거되지 않으면 플래그를 해제합니다. **설정 → 자동화**에서 편집하여 복구 기간을 변경하거나 복구 작업을 교체(예: 격리 해제 포함)하거나 복구를 완전히 비활성화하여 테스트가 직접 해제할 때까지 불안정한 상태로 유지되도록 할 수 있습니다.

### 수동 관리

테스트 케이스 상세 페이지에서 테스트를 수동으로 불안정하다고 표시하거나 표시를 해제할 수도 있습니다. 다음과 같은 경우에 유용합니다:
- 수정 작업을 진행 중인 알려진 불안정한 테스트를 인지하고 싶을 때
- 인프라 문제 때문에 테스트가 잘못 표시되었을 때

## 불안정한 테스트 격리 {#quarantining}

격리는 불안정한 테스트를 분리하여 수정 중인 동안 CI를 차단하지 않도록 합니다. 기본적으로 이는 **수동 작업**이며 — 대시보드의 테스트 케이스 상세 페이지에서 격리, 격리 해제 및 모드 전환을 수행합니다 — 하지만 **설정 → 자동화** 아래에서 **자동화 알림**에 연결하여 테스트가 불안정성 임계값을 초과할 때 자동으로 음소거(또는 건너뛰기)되고 복구되면 격리가 해제되도록 설정할 수도 있습니다. 수동이든 자동이든 모든 전환은 테스트 케이스의 감사 로그에 기록됩니다.

격리된 테스트는 다음 두 모드 중 하나에 있습니다:

- **음소거됨**: 테스트는 여전히 실행되지만 플러그인이 `ignoreFailures = true`를 설정하고 격리되지 않은 실패에서만 빌드를 다시 실패시킵니다. 실패는 여전히 불안정한 테스트 감지기에 피드되므로 빌드를 중단하지 않고 테스트를 계속 모니터링할 수 있습니다. 적극적으로 조사 중인 테스트에 이 모드를 선택하세요.
- **건너뛰기**: 플러그인이 Gradle의 `excludeTestsMatching`를 통해 테스트를 필터링하므로 테스트가 전혀 시작되지 않습니다. 새로운 결과가 생성되지 않으며 다시 활성화할 때까지 불안정한 테스트 대시보드에서 제외됩니다. 테스트가 손상되었거나 느리거나 지나치게 지속적으로 불안정해서 실행하는 것이 CI 시간 낭비일 때 이 모드를 선택하세요.

### 격리된 테스트가 통과로 표시될 수 있는 이유 {#quarantined-passing}

- **음소거된 테스트**는 여전히 실행됩니다. 실패한 음소거 테스트는 테스트 케이스 실행에서 **실패**로 기록되고 불안정하다고 플래그됩니다 — 테스트별 상태는 재작성되지 않습니다. 재정의되는 것은 **전체 테스트 실행**입니다: 실행 내 모든 실패한 테스트 케이스가 음소거되면 실행 전체가 통과로 보고되므로 음소거된 실패는 CI를 중단시키지 않습니다.
- **건너뛴 테스트**는 전혀 실행되지 않으므로 대시보드는 테스트의 마지막 실제 실행 상태를 계속 표시합니다 — 해당 스냅샷은 몇 주 전 것일 수 있습니다.

### 격리 활성화 {#enabling-quarantine}

격리는 CI에서 **자동으로 활성화**되며(`CI` 환경 변수가 설정된 경우) 로컬 빌드에서는 비활성화됩니다. 플러그인은 각 테스트 태스크 전에 Tuist 서버에서 격리된 테스트 목록을 가져옵니다. 음소거된 테스트는 정상적으로 실행되고 실패가 마스킹되며, 건너뛴 테스트는 필터링됩니다.

이를 `settings.gradle.kts`에서 명시적으로 제어할 수 있습니다:

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

`enabled`가 설정되지 않으면 자동 감지가 기본값으로 적용됩니다: CI에서는 활성화, 로컬에서는 비활성화.

## 새 테스트 스트레스 테스트 {#stress-testing-new-tests}

스트레스 게이트는 브랜치가 추가한 테스트 케이스를 각각 새 프로세스에서 여러 번 다시 실행하고 불안정한 것으로 판명된 것을 보고합니다.几周 후가 아니라 이를 도입한 풀 리퀘스트에서 새로운 불안정한 테스트를 확인할 수 있습니다.

프로젝트의 기본 브랜치 또는 이후 해당 브랜치에 병합된 커밋에서 지난 90일 동안 CI에서 실행되지 않은 테스트 케이스는 새로운 것으로 간주됩니다. 머지 큐를 사용하는 경우 큐가 실행한 테스트 케이스는 큐의 커밋이 병합되면 알려지며 큐가 이를 제거하면 새로운 상태로 유지됩니다. 커밋은 Tuist가 CI에서 수집하는 <.localized_link href="/guides/features/test-insights/gradle#git-history">Git 히스토리</.localized_link>를 통해 매칭됩니다.

### 활성화하기

게이트는 기본적으로 꺼져 있습니다. 모드를 설정하세요:

- **`report`**: 각 불안정한 테스트 케이스에 대해 경고합니다. 실행은 여전히 자체 결과로 종료됩니다.
- **`enforce`**: 불안정한 테스트 케이스가 실행을 실패시키며, 실패한 테스트와 동일한 종료 코드를 반환합니다.

몇 주 동안 `report`로 시작하여 `enforce`가 무엇을 차단했을지 확인하세요.

`settings.gradle.kts`에 선언하거나, CI 레인별로 모드를 변경하려면 `TUIST_TEST_STRESS_NEW_TESTS`를 설정하세요:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

격리와 달리 게이트에는 CI 인식 기본값이 없습니다. `mode`가 설정되지 않으면 어디에서도 실행되지 않습니다.

### 각 테스트의 재실행 횟수

첫 번째 통과 시 테스트 케이스 소요 시간에 따라 달라집니다:

| 첫 번째 통과 | 재실행 |
| --- | --- |
| 최대 5초 | 10 |
| 최대 10초 | 5 |
| 최대 30초 | 3 |
| 최대 5분 | 2 |
| 5분 초과 | 재실행 안 함 |

각 재실행은 해당 테스트 케이스 하나로 필터링된 중첩 Gradle 빌드이므로 매 재실행마다 새로운 테스트 JVM을 사용합니다. 통과는 200개 테스트 케이스 또는 10분 중 먼저 도달하는 기준에서 멈추며 어느 제한에 도달했는지 표시합니다.

### 게이트가 실행되지 않는 경우

- 첫 번째 통과가 이미 실패했습니다. 해당 테스트를 먼저 수정하세요.
- 프로젝트에 기본 브랜치가 없거나 아직 CI에서 아무것도 실행되지 않았습니다.
- 프로젝트 테스트 케이스의 30% 이상이 새로 보입니다. 이렇게 많은 수를 재실행하는 것은 비용 대비 효과가 떨어집니다. Tuist 보고를 막 시작한 프로젝트나 한 번에 많은 테스트를 이동시키는 이름 변경 후에는 이러한 상황을 예상하세요.

## Slack 알림 {#slack-notifications}

Slack 통합에서 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">불안정한 테스트 알림</.localized_link>을 설정하면 테스트가 불안정해질 때 즉시 알림을 받을 수 있습니다.

## 불안정 및 격리 상태 조회 {#querying}

### CLI

`tuist test case` 명령어 트리는 Tuist가 테스트 케이스에 대해 추적하는 모든 정보를 제공합니다:

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

이들 모두 스크립팅을 위해 `--json`를 지원합니다.

### REST API

동일한 데이터를 HTTP를 통해 사용할 수 있습니다 — 전체 경로, 필터 및 응답 필드 목록은 API 참조의 [테스트 케이스 엔드포인트](https://tuist.dev/api/docs#tag/test-cases)를 참조하세요. 테스트 케이스 상태(불안정 표시/해제, 음소거, 건너뛰기)를 변경하려면 `is_flaky` 또는 `state`와 함께 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`를 보내세요. 동일한 변경은 `tuist test case update` 및 `update_test_case` Model Context Protocol 도구로도 가능합니다.
