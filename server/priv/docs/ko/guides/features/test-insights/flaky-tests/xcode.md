---
{
  "title": "Xcode Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in Xcode projects with Tuist."
}
---
# Xcode 불안정한 테스트 {#xcode-flaky-tests}

> [!WARNING]
> **필수 조건**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode 테스트 인사이트</.localized_link>가 구성되어 있어야 합니다. Tuist는 각 테스트 실행에서 업로드된 테스트 인사이트 이벤트를 기반으로 불안정한 테스트를 감지합니다.

불안정한 테스트는 동일한 코드로 여러 번 실행했을 때 서로 다른 결과(통과 또는 실패)를 내는 테스트입니다. 이는 테스트 스위트에 대한 신뢰를 떨어뜨리고, 잘못된 실패를 조사하는 데 개발자의 시간을 낭비하게 만듭니다. Tuist는 불안정한 테스트를 자동으로 감지하고 시간이 지남에 따라 추적할 수 있도록 도와줍니다.

![불안정한 테스트 페이지](/images/guides/features/test-insights/flaky-tests-page.png)

## 불안정성 감지 방식 {#how-it-works}

Tuist는 두 가지 방식으로 불안정한 테스트를 감지합니다:

### 테스트 재시도 {#test-retries}

재시도 기능을 사용하여 테스트를 실행하면 Tuist는 각 시도 결과를 분석합니다. 일부 시도에서는 실패하지만 다른 시도에서는 통과하는 테스트는 불안정한 것으로 표시됩니다.

`-retry-tests-on-failure` 또는 `-test-iterations`를 `tuist xcodebuild test`을 통해 전달하세요:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![불안정한 테스트 케이스 상세 정보](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 교차 실행 감지 {#cross-run-detection}

테스트 재시도가 없더라도 Tuist는 동일한 커밋, 스킴 및 보고된 대상(기기 이름, 플랫폼 및 OS 버전)에 대한 다양한 CI 실행 간 결과를 비교하여 불안정한 테스트를 감지할 수 있습니다. 일치하는 한 CI 실행에서는 테스트가 통과하지만 다른 실행에서는 실패하면 해당 실패한 실행은 불안정한 것으로 표시됩니다. 이는 어떤 결과가 먼저 도착하든 관계없이 작동합니다.

동일한 테스트라도 스킴이나 대상에 따라 일관되게 다르게 동작할 수 있습니다. 예를 들어 iOS 26에서는 통과하지만 iOS 27에서는 실패하는 경우 불안정성이 입증된 것은 아닙니다. 서로 다른 스킴, 기기, 플랫폼 또는 OS 버전의 결과는 서로를 불안정한 것으로 표시하지 않습니다.

귀속 가능한 대상이 없는 결과는 알려진 대상이 있는 결과와 별도로 다른 귀속되지 않은 결과와 비교됩니다. 여기에는 누락되거나 불완전한 대상 메타데이터가 포함된 보고서와 여러 개의 서로 다른 대상이 포함된 보고서가 포함되며, 개별 테스트 결과를 아직 대상에 귀속시킬 수 없기 때문입니다. 이 그룹 내 환경 간 차이는 여전히 잘못된 불안정성 분류를 유발할 수 있습니다. 재시도 기반 감지는 계속 적용됩니다. 기존 과거 불안정성 분류는 변경되지 않습니다.

이는 재시도로 포착될 만큼 일관되게 실패하지는 않지만 여전히 간헐적인 CI 실패를 유발하는 불안정한 테스트를 포착하는 데 특히 유용합니다.

## 불안정한 테스트 관리 {#managing-flaky-tests}

### 자동 초기화

감지 및 초기화는 프로젝트의 **자동화 알림**을 통해 실행됩니다. 모든 프로젝트에는 기본 "불안정한 테스트 감지" 자동화가 제공되며, 여기서 *트리거*는 테스트를 불안정한 것으로 표시하고 *복구*는 테스트가 구성된 복구 기간(기본 **14일**) 동안 다시 트리거되지 않으면 플래그를 해제합니다. **설정 → 자동화**에서 이를 편집하여 복구 기간을 변경하거나 복구 작업을 교체(예: 격리 해제 포함)하거나 복구를 완전히 비활성화하여 테스트를 직접 해제할 때까지 불안정한 상태로 유지되도록 할 수 있습니다.

### 수동 관리

테스트 케이스 상세 페이지에서 테스트를 수동으로 불안정한 것으로 표시하거나 해제할 수도 있습니다. 이는 다음과 같은 경우에 유용합니다:
- 수정 작업을 진행하면서 알려진 불안정한 테스트를 인지하고 싶을 때
- 인프라 문제로 인해 테스트가 잘못 플래그 지정되었을 때

## 불안정한 테스트 격리 {#quarantining}

격리는 불안정한 테스트를 분리하여 수정하는 동안 CI를 차단하지 않도록 합니다. 기본적으로 이는 **수동 작업**입니다 — 대시보드의 테스트 케이스 상세 페이지에서 격리, 격리 해제 및 모드 전환을 수행합니다 — 하지만 **설정 → 자동화** 아래의 **자동화 알림**에 연결하여 테스트가 불안정성 임계값을 초과할 때 자동으로 음소거(또는 건너뛰기)되고 복구되면 격리 해제되도록 할 수도 있습니다. 수동이든 자동이든 모든 전환은 테스트 케이스의 감사 로그에 기록됩니다.

격리된 테스트는 다음 두 가지 모드 중 하나에 있습니다:

- **음소거됨**: 테스트는 여전히 실행되지만 `tuist xcodebuild test`가 실패를 마스킹합니다. 실패는 여전히 불안정한 테스트 감지기에 피드되므로 빌드를 중단하지 않고 테스트를 계속 모니터링할 수 있습니다. 적극적으로 조사 중인 테스트에 이 옵션을 선택하세요.
- **건너뜀**: xcodebuild가 `-skip-testing <identifier>`를 수신하므로 테스트가 전혀 시작되지 않습니다. 새 결과를 생성하지 않으며 다시 활성화할 때까지 불안정한 테스트 대시보드에서 제외됩니다. 테스트가 손상되었거나 느리거나 지나치게 지속적으로 불안정하여 실행하는 것이 CI 시간을 낭비하는 경우에 이 옵션을 선택하세요.

### 격리된 테스트가 통과로 표시될 수 있는 이유 {#quarantined-passing}

- **음소거된 테스트**는 여전히 실행됩니다. 실패한 음소거 테스트는 테스트 케이스 실행에서 **실패**로 기록되고 불안정한 것으로 플래그 지정됩니다 — 테스트별 상태는 재작성되지 않습니다. 재정의되는 것은 **전체 테스트 실행**입니다: 실행 중인 모든 실패 테스트 케이스가 음소거되면 실행 전체가 통과로 보고되므로 음소거된 실패는 CI를 중단시키지 않습니다.
- **건너뛴 테스트**는 전혀 실행되지 않으므로 대시보드는 테스트의 마지막 실제 실행 상태를 계속 표시합니다 — 해당 스냅샷은 몇 주 전 것일 수 있습니다.

### 테스트 실행 {#running-tests}

`tuist xcodebuild test`는 두 모드를 자동으로 준수하는 패스스루 래퍼입니다. xcodebuild를 호출하는 것과 동일한 방식으로 사용하세요:

```sh
tuist xcodebuild test -scheme MyScheme
```

건너뛴 테스트는 xcodebuild 호출에 `-skip-testing <identifier>`로 추가되어 결코 시작되지 않습니다. 음소거된 테스트는 정상적으로 실행되며 실패하면 결과 빌드 상태에서 실패가 마스킹됩니다.

#### 격리 우회

`tuist xcodebuild test`는 음소거된 테스트와 건너뛴 테스트를 포함하여 모든 것을 실행하기 위해 `--skip-quarantine`를 허용합니다:

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### xcodebuild 직접 호출

`tuist xcodebuild test`를 사용할 수 없는 경우 `tuist test case list`를 사용하여 격리된 테스트를 직접 `-skip-testing` 인수로 확장하세요:

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

이는 `tuist xcodebuild test` 외부에서의 안전한 기본값입니다: 음소거된 테스트에 대한 실패 마스킹은 해당 명령을 통해서만 발생하므로 두 모드를 모두 건너뛰면 허위 CI 실패를 방지할 수 있습니다. 더 세밀한 제어가 필요하면 대신 `tuist xcodebuild test`를 사용하세요.

## 새 테스트 스트레스 테스트 {#stress-testing-new-tests}

스트레스 게이트는 브랜치가 추가한 테스트 케이스를 각각 새 프로세스에서 여러 번 다시 실행하고, 불안정한 것으로 판명된 것을 보고합니다. 몇 주 후가 아니라 이를 도입한 풀 리퀘스트에서 새로운 불안정한 테스트를 확인할 수 있습니다.

테스트 케이스는 프로젝트의 기본 브랜치에서 지난 90일 동안 CI에서 실행되지 않았거나, 이후 해당 브랜치에 병합된 커밋에서 실행되지 않은 경우 새로 간주됩니다. 병합 큐를 사용하는 경우, 큐가 실행한 테스트 케이스는 큐의 커밋이 병합되면 알려지며, 큐가 이를 제거하면 새로 유지됩니다. 커밋은 Tuist가 CI에서 수집하는 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 기록</.localized_link>을 통해 일치됩니다.

### 활성화하기

게이트는 기본적으로 비활성화되어 있습니다. 모드를 설정하세요:

- **`report`**: 각 불안정한 테스트 케이스에 대해 경고합니다. 실행은 여전히 자체 결과로 종료됩니다.
- **`enforce`**: 불안정한 테스트 케이스가 실행을 실패시키며, 실패한 테스트와 동일한 종료 코드를 반환합니다.

`enforce`가 무엇을 차단했을지 확인하기 위해 몇 주 동안 `report`로 시작하세요.

패스스루 인수 앞에 전달하거나, CI 레인별로 모드를 변경하려면 `TUIST_TEST_STRESS_NEW_TESTS`를 설정하세요:

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

### 각 테스트가 다시 실행되는 횟수

첫 번째 통과에서 테스트 케이스가 걸린 시간에 따라 달라집니다:

| 첫 번째 통과 | 재실행 횟수 |
| --- | --- |
| 최대 5초 | 10 |
| 최대 10초 | 5 |
| 최대 30초 | 3 |
| 최대 5분 | 2 |
| 5분 초과 | 재실행 안 함 |

재실행은 첫 번째 통과에서 빌드된 내용을 재사용합니다. 통과는 200개의 테스트 케이스 또는 10분 중 먼저 도달하는 지점에서 중단되며, 어떤 제한에 도달했는지 표시합니다.

### 게이트가 실행되지 않는 경우

- 첫 번째 통과가 이미 실패했습니다. 해당 테스트를 먼저 수정하세요.
- 프로젝트에 기본 브랜치가 없거나, 아직 CI에서 아무것도 실행되지 않았습니다.
- 프로젝트 테스트 케이스의 30% 이상이 새로 보입니다. 그만큼 많이 재실행하는 것은 가치 있는 시간보다 더 오래 걸립니다. Tuist에 보고를 막 시작한 프로젝트나 한 번에 많은 테스트를 이동시키는 이름 변경 후에는 이러한 상황을 예상하세요.

## Slack 알림 {#slack-notifications}

Slack 통합에서 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">불안정한 테스트 알림</.localized_link>을 설정하여 테스트가 불안정해지면 즉시 알림을 받으세요.

## 불안정 및 격리 상태 조회 {#querying}

### CLI

`tuist test case` 명령 트리는 Tuist가 테스트 케이스에 대해 추적하는 모든 정보를 노출합니다:

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

이들 모두는 스크립팅을 위해 `--json`를 허용합니다.

### REST API

동일한 데이터는 HTTP를 통해 사용할 수 있습니다 — 전체 경로, 필터 및 응답 필드 목록은 API 참조의 [테스트 케이스 엔드포인트](https://tuist.dev/api/docs#tag/test-cases)를 참조하세요. 테스트 케이스의 상태(불안정 표시/해제, 음소거, 건너뛰기)를 변경하려면 `is_flaky` 또는 `state`와 함께 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`를 보내세요. 동일한 변경은 `tuist test case update` 및 `update_test_case` Model Context Protocol 도구를 통해서도 가능합니다.
