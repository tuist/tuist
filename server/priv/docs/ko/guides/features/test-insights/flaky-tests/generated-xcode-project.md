---
{
  "title": "생성된 Xcode 프로젝트",
  "titleTemplate": ":title · 불안정한 테스트 · 테스트 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist가 생성한 Xcode 프로젝트에서 불안정한 테스트를 감지, 관리 및 격리합니다."
}
---
# 생성된 Xcode 프로젝트 {#generated-xcode-project-flaky-tests}

> [!IMPORTANT]
> **필수 조건**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode 테스트 인사이트</.localized_link>가 구성되어야 합니다(자동 생성 스킴에는 `tuist inspect test` 포스트 액션이 포함되며, 사용자 정의 스킴에는 이를 직접 추가해야 합니다).

<!-- @snippet: ./_intro -->

![불안정한 테스트 페이지](/images/guides/features/test-insights/flaky-tests-page.png)

## 불안정 감지 방식 {#how-it-works}

Tuist는 두 가지 방식으로 불안정한 테스트를 감지합니다:

### 테스트 재시도 {#test-retries}

재시도 기능을 사용해 테스트를 실행하면 Tuist는 각 시도 결과를 분석합니다. 일부 시도에서는 실패하지만 다른 시도에서는 통과하는 테스트는 불안정하다고 표시됩니다.

`tuist test`를 통해 `-retry-tests-on-failure` 또는 `-test-iterations`를 전달하세요:

```sh
tuist test MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![불안정한 테스트 케이스 상세](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## 불안정한 테스트 격리하기 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

격리된 테스트는 다음 두 모드 중 하나에 속합니다:

- **음소거**: 테스트는 계속 실행되지만 `tuist test`가 실패를 마스킹합니다. 실패 정보는 여전히 불안정 테스트 감지기에 제공되므로 빌드를 중단하지 않고 테스트를 계속 모니터링할 수 있습니다. 적극적으로 조사 중인 테스트에 이 모드를 선택하세요.
- **건너뛰기**: xcodebuild가 `-skip-testing <identifier>`를 수신하므로 테스트가 전혀 시작되지 않습니다. 새로운 결과가 생성되지 않으며 다시 활성화할 때까지 불안정 테스트 대시보드에서 제외됩니다. 테스트가 손상되었거나 느리거나 지나치게 지속적으로 불안정해서 실행 시 CI 시간만 낭비되는 경우에 이 모드를 선택하세요.

<!-- @snippet: ./_quarantined-passing -->

### 테스트 실행 {#running-tests}

`tuist test`는 두 모드를 자동으로 준수합니다:

```sh
tuist test
```

건너뛰기 테스트는 `-skip-testing`로 xcodebuild에 전달되어 전혀 시작되지 않습니다. 음소거 테스트는 정상적으로 실행되며, 실패할 경우 최종 빌드 상태에서 실패가 마스킹됩니다.

격리를 완전히 우회하고 음소거 및 건너뛰기 테스트를 포함해 모든 것을 실행하려면:

```sh
tuist test --skip-quarantine
```

## 새 테스트 부하 테스트 {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

프로젝트의 기본 브랜치 또는 해당 브랜치에 이미 병합된 커밋에서 지난 90일 동안 CI에서 실행된 적이 없는 테스트 케이스는 새 것으로 간주됩니다. 병합 큐를 사용하는 경우, 큐가 실행한 테스트 케이스는 큐의 커밋이 병합되면 식별되며, 큐가 해당 테스트를 제거하면 새 상태로 유지됩니다. 커밋 매칭은 Tuist가 CI에서 수집하는 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 히스토리</.localized_link>를 통해 이루어집니다.

<!-- @snippet: ./_stress-modes -->

두 모드 모두에서 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">선택적 테스팅</.localized_link>은 다음 실행에서 불안정한 새 테스트 케이스가 있는 테스트 타겟을 건너뛰지 않습니다. 타겟이 다시 실행되고 게이트가 테스트 케이스를 다시 부하 테스트하여 모든 재실행에서 통과할 때까지 반복합니다.

패스스루 인수 앞에 이를 전달하거나, CI 레인별로 모드를 다르게 설정하려면 `TUIST_TEST_STRESS_NEW_TESTS`를 설정하세요:

```sh
tuist test --stress-new-tests report
```

<!-- @snippet: ./_stress-reruns -->

재실행은 첫 번째 패스에서 빌드된 결과를 재사용합니다.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
