---
{
  "title": "생성된 Xcode 프로젝트",
  "titleTemplate": ":title · 불안정한 테스트 · 테스트 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist로 생성된 Xcode 프로젝트에서 불안정한 테스트를 감지, 관리 및 격리합니다."
}
---
# 생성된 Xcode 프로젝트 {#generated-xcode-project-flaky-tests}

> [!WARNING]
> **필수 조건**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode 테스트 인사이트</.localized_link>가 구성되어 있어야 합니다(자동 생성된 스킴에는 `tuist inspect test` 포스트 액션이 포함되며, 사용자 정의 스킴에는 이를 직접 추가해야 합니다).

불안정한 테스트는 동일한 코드로 여러 번 실행할 때마다 다른 결과(통과 또는 실패)를 내는 테스트입니다. 이러한 테스트는 테스트 스위트에 대한 신뢰를 떨어뜨리고, 잘못된 실패를 조사하는 데 개발자의 시간을 낭비하게 만듭니다. Tuist는 불안정한 테스트를 자동으로 감지하고 시간에 따라 추적할 수 있도록 도와줍니다.

![불안정한 테스트 페이지](/images/guides/features/test-insights/flaky-tests-page.png)

## 불안정성 감지 작동 방식 {#how-it-works}

Tuist는 다음 두 가지 방법으로 불안정한 테스트를 감지합니다:

### 테스트 재시도 {#test-retries}

재시도 기능을 사용하여 테스트를 실행하면 Tuist는 각 시도 결과를 분석합니다. 일부 시도에서는 실패하지만 다른 시도에서는 통과하는 테스트는 불안정한 것으로 표시됩니다.

`-retry-tests-on-failure` 또는 `-test-iterations`를 `tuist test`를 통해 전달하세요:

```sh
tuist test --scheme MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![불안정한 테스트 케이스 상세 정보](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 실행 간 교차 감지 {#cross-run-detection}

테스트 재시도가 없더라도 Tuist는 동일한 커밋과 동일한 스킴에 대한 서로 다른 CI 실행 간 결과를 비교하여 불안정한 테스트를 감지할 수 있습니다. 동일한 커밋과 스킴에서 한 CI 실행에서는 테스트가 통과하지만 다른 실행에서는 실패하면 두 실행 모두 불안정한 것으로 표시됩니다.

스킴은 비교 키의 일부입니다. 동일한 테스트라도 스킴에 따라 결정론적으로 다르게 동작할 수 있기 때문입니다. 예를 들어 특정 시뮬레이터 대상에서만 유효한 스냅샷 테스트나 다른 플래그로 컴파일된 테스트 타arget이 있을 수 있습니다. 서로 다른 스킴에서 동일한 커밋을 두 번 실행하면 별도의 실행 변형으로 취급되며 서로를 불안정한 것으로 표시하지 않습니다.

이는 재시도로 catch하기에 충분히 일관되게 실패하지는 않지만 여전히 간헐적인 CI 실패를 유발하는 불안정한 테스트를 잡는 데 특히 유용합니다.

## 불안정한 테스트 관리 {#managing-flaky-tests}

### 자동 해제

감지와 해제는 프로젝트의 **자동화 알림**을 통해 실행됩니다. 모든 프로젝트에는 기본 "불안정한 테스트 감지" 자동화가 제공되며, 이 자동화의 *트리거*는 테스트를 불안정한 것으로 표시하고 *복구*는 테스트가 구성된 복구 기간(기본값 **14일**) 동안 다시 트리거되지 않으면 플래그를 해제합니다. **설정 → 자동화**에서 편집하여 복구 기간을 변경하거나, 복구 액션(예: 격리 해제)을 교체하거나, 복구를 완전히 비활성화하여 테스트가 수동으로 해제될 때까지 불안정한 상태로 유지되도록 할 수 있습니다.

### 수동 관리

테스트 케이스 상세 페이지에서 테스트를 수동으로 불안정한 것으로 표시하거나 해제할 수도 있습니다. 이는 다음과 같은 경우에 유용합니다:
- 수정 작업을 진행하면서 알려진 불안정한 테스트를 인지하고 싶을 때
- 인프라 문제로 인해 테스트가 잘못 플래그되었을 때

## 불안정한 테스트 격리 {#quarantining}

격리는 불안정한 테스트를 격리시켜 수정 중인 동안 CI를 차단하지 않도록 합니다. 기본적으로 이는 **수동 액션**입니다. 대시보드의 테스트 케이스 상세 페이지에서 격리, 격리 해제 및 모드 전환을 수행할 수 있지만, **설정 → 자동화** 아래의 **자동화 알림**에 연결하여 테스트가 불안정성 임계값을 초과할 때 자동으로 음소거(또는 건너뛰기)되고 복구되면 격리 해제되도록 할 수도 있습니다. 수동이든 자동이든 모든 전환은 테스트 케이스의 감사 로그에 기록됩니다.

격리된 테스트는 다음 두 가지 모드 중 하나에 있습니다:

- **음소거됨**: 테스트는 여전히 실행되지만 `tuist test`가 실패를 마스킹합니다. 실패는 여전히 불안정한 테스트 감지기에 피드되므로 빌드를 중단하지 않고 테스트를 계속 모니터링할 수 있습니다. 적극적으로 조사 중인 테스트에 이 모드를 선택하세요.
- **건너뜀**: xcodebuild가 `-skip-testing <identifier>`를 수신하므로 테스트가 전혀 시작되지 않습니다. 새로운 결과가 생성되지 않으며 다시 활성화할 때까지 불안정한 테스트 대시보드에서 제외됩니다. 테스트가 손상되었거나 느리거나, 지속적으로 불안정하여 실행하는 것이 CI 시간만 낭비하는 경우에 이 모드를 선택하세요.

### 격리된 테스트가 통과로 표시될 수 있는 이유 {#quarantined-passing}

- **음소거된 테스트**는 여전히 실행됩니다. 실패한 음소거 테스트는 테스트 케이스 실행에서 **실패**로 기록되고 불안정한 것으로 플래그됩니다. 테스트별 상태는 재작성되지 않습니다. 재정의되는 것은 **전체 테스트 실행**입니다. 실행 내 모든 실패한 테스트 케이스가 음소거되면 실행 전체가 통과로 보고되므로 음소거된 실패는 CI를 중단시키지 않습니다.
- **건너뛴 테스트**는 전혀 실행되지 않으므로 대시보드는 테스트의 마지막 실제 실행 상태를 계속 표시합니다. 이 스냅샷은 몇 주 전 것일 수 있습니다.

### 테스트 실행 {#running-tests}

`tuist test`는 두 모드를 자동으로 준수합니다:

```sh
tuist test
```

건너뛴 테스트는 `-skip-testing`로 xcodebuild에 전달되어 전혀 시작되지 않습니다. 음소거된 테스트는 정상적으로 실행되며, 실패할 경우 결과 빌드 상태에서 실패가 마스킹됩니다.

격리를 완전히 우회하고 음소거된 테스트와 건너뛴 테스트를 포함하여 모든 것을 실행하려면:

```sh
tuist test --skip-quarantine
```

## 새로운 테스트 스트레스 테스트 {#stress-testing-new-tests}

스트레스 게이트는 브랜치가 추가한 테스트 케이스를 각각 여러 번 새 프로세스에서 재실행하고 불안정한 것으로 판명된 것을 보고합니다.几周 후에야 아니라 이를 도입한 풀 리퀘스트에서 새로운 불안정한 테스트를 확인할 수 있습니다.

테스트 케이스가 프로젝트의 기본 브랜치에서 지난 90일 동안 CI에서 실행되지 않았거나, 이후 해당 브랜치에 병합된 커밋에서 실행되지 않은 경우 새로운 것으로 간주됩니다. 병합 큐를 사용하는 경우 큐가 실행한 테스트 케이스는 큐의 커밋이 병합되면 알려지며, 큐가 이를 삭제하면 새로운 상태로 유지됩니다. 커밋은 Tuist가 CI에서 수집하는 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 히스토리</.localized_link>를 통해 매칭됩니다.

### 활성화하기

게이트는 기본적으로 비활성화되어 있습니다. 모드를 설정하세요:

- **`report`**: 각 불안정한 테스트 케이스에 대해 경고합니다. 실행은 여전히 자체 결과로 종료됩니다.
- **`enforce`**: 불안정한 테스트 케이스가 실행을 실패로 처리하며, 실패한 테스트와 동일한 종료 코드를 반환합니다.

두 모드 모두에서 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">선택적 테스팅</.localized_link>은 다음 실행 시 새로운 불안정한 테스트 케이스가 있는 테스트 대상을 건너뛰지 않습니다. 대상은 다시 실행되고 게이트는 해당 테스트 케이스를 모든 재실행을 통과할 때까지 다시 스트레스 테스트합니다.

`report` 모드로 몇 주 동안 시작하여 `enforce` 모드가 무엇을 차단했을지 확인하세요.

인수 전달 전에 이를 지정하거나, CI 레인별로 모드를 변경하려면 `TUIST_TEST_STRESS_NEW_TESTS`를 설정하세요:

```sh
tuist test --stress-new-tests report
```

### 각 테스트의 재실행 횟수

첫 번째 통과 시 테스트 케이스에 소요된 시간에 따라 달라집니다:

| 첫 번째 통과 | 재실행 |
| --- | --- |
| 최대 5초 | 10 |
| 최대 10초 | 5 |
| 최대 30초 | 3 |
| 최대 5분 | 2 |
| 5분 초과 | 재실행 안 함 |

재실행은 첫 번째 통과에서 빌드된 결과를 재사용합니다. 통과는 200개의 테스트 케이스 또는 10분 중 먼저 도달하는 지점에서 중단되며, 어떤 제한에 도달했는지 표시합니다.

### 게이트가 실행되지 않는 경우

- 첫 번째 통과가 이미 실패했습니다. 먼저 해당 테스트를 수정하세요.
- 프로젝트에 기본 브랜치가 없거나, 아직 해당 브랜치에서 CI가 실행된 적이 없습니다.
- 프로젝트 테스트 케이스의 30% 이상이 새로운 것으로 보입니다. 이만큼을 재실행하는 것은 가치보다 시간이 더 오래 걸립니다. Tuist 보고를 막 시작한 프로젝트나 한 번에 많은 테스트를 이동시키는 이름 변경 후에는 이러한 상황을 예상하세요.

## Slack 알림 {#slack-notifications}

Slack 통합에서 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">불안정한 테스트 알림</.localized_link>을 설정하여 테스트가 불안정해지면 즉시 알림을 받으세요.

## 불안정 및 격리 상태 조회 {#querying}

### CLI

`tuist test case` 명령어 트리는 Tuist가 테스트 케이스에 대해 추적하는 모든 정보를 노출합니다:

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

이들 모두 스크립팅을 위해 `--json`를 허용합니다.

### REST API

동일한 데이터를 HTTP를 통해 사용할 수 있습니다. 전체 경로, 필터 및 응답 필드 목록은 API 참조의 [테스트 케이스 엔드포인트](https://tuist.dev/api/docs#tag/test-cases)를 참조하세요. 테스트 케이스의 상태(불안정 표시/해제, 음소거, 건너뛰기)를 변경하려면 `is_flaky` 또는 `state`와 함께 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`를 보내세요. 동일한 변경은 `tuist test case update` 및 `update_test_case` 모델 컨텍스트 프로토콜 도구로도 사용할 수 있습니다.
