---
{
  "title": "Xcode 불안정한 테스트",
  "titleTemplate": ":title · 불안정한 테스트 · 테스트 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist로 Xcode 프로젝트에서 불안정한 테스트를 감지, 관리 및 격리하세요."
}
---
# Xcode 불안정한 테스트 {#xcode-flaky-tests}

> [!IMPORTANT]
> **필수 조건**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode 테스트 인사이트</.localized_link>가 구성되어 있어야 합니다. Tuist는 각 테스트 실행에서 업로드된 테스트 인사이트 이벤트를 기반으로 불안정한 테스트를 감지합니다.

<!-- @snippet: ./_intro -->

![불안정한 테스트 페이지](/images/guides/features/test-insights/flaky-tests-page.png)

## 불안정성 감지 방식 {#how-it-works}

Tuist는 두 가지 방식으로 불안정한 테스트를 감지합니다:

### 테스트 재시도 {#test-retries}

재시도 기능을 사용해 테스트를 실행하면, Tuist는 각 시도 결과를 분석합니다. 일부 시도에서는 실패하고 다른 시도에서는 성공하는 테스트는 불안정한 것으로 표시됩니다.

`-retry-tests-on-failure` 또는 `-test-iterations`를 `tuist xcodebuild test`에 전달하세요:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![불안정한 테스트 케이스 상세](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## 불안정한 테스트 격리 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

격리된 테스트는 다음 두 모드 중 하나입니다:

- **음소거됨**: 테스트는 여전히 실행되지만 `tuist xcodebuild test`가 실패를 마스킹합니다. 실패는 여전히 불안정한 테스트 감지기에 반영되므로, 빌드를 중단하지 않고 테스트를 계속 모니터링할 수 있습니다. 적극적으로 조사 중인 테스트에 이 모드를 선택하세요.
- **건너뜀**: xcodebuild가 `-skip-testing <identifier>`를 받아 테스트가 전혀 시작되지 않습니다. 새로운 결과가 생성되지 않으며 다시 활성화하기 전까지 불안정한 테스트 대시보드에서 제외됩니다. 테스트가 손상되었거나 느리거나, 지속적으로 불안정해서 실행하는 것이 CI 시간을 낭비하는 경우 이 모드를 선택하세요.

<!-- @snippet: ./_quarantined-passing -->

### 테스트 실행 {#running-tests}

`tuist xcodebuild test`는 두 모드를 자동으로 존중하는 패스스루 래퍼입니다. xcodebuild를 호출하는 것과 동일한 방식으로 사용하세요:

```sh
tuist xcodebuild test -scheme MyScheme
```

건너뛴 테스트는 xcodebuild 호출에 `-skip-testing <identifier>`로 추가되어 전혀 시작되지 않습니다. 음소거된 테스트는 정상적으로 실행되며, 실패할 경우 결과 빌드 상태에서 실패가 마스킹됩니다.

#### 격리 우회 {#bypassing-quarantine}

`tuist xcodebuild test`는 음소거된 테스트와 건너뛴 테스트를 포함해 모든 것을 실행하기 위해 `--skip-quarantine`를 허용합니다:

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### xcodebuild 직접 호출 {#calling-xcodebuild-directly}

`tuist xcodebuild test`를 통과할 수 없는 경우, `tuist test case list`를 사용해 격리된 테스트를 직접 `-skip-testing` 인수로 확장하세요:

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

이는 `tuist xcodebuild test` 외부에서의 안전한 기본값입니다. 음소거된 테스트의 실패 마스킹은 해당 명령을 통과할 때만 발생하므로, 두 모드를 모두 건너뛰면 잘못된 CI 실패를 방지할 수 있습니다. 더 세밀한 제어가 필요하다면 대신 `tuist xcodebuild test`를 사용하세요.

## 새로운 테스트 스트레스 테스트 {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

테스트 케이스는 프로젝트의 기본 브랜치에서 지난 90일 동안 CI에서 실행되지 않았거나, 이후 해당 브랜치에 병합된 커밋에서 실행되지 않은 경우 새로운 것으로 간주됩니다. 머지 큐를 사용하는 경우, 큐가 실행한 테스트 케이스는 큐의 커밋이 병합되면 인식되며, 큐가 이를 제거하면 새로운 상태로 유지됩니다. 커밋은 Tuist가 CI에서 수집하는 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 히스토리</.localized_link>를 통해 매칭됩니다.

<!-- @snippet: ./_stress-modes -->

패스스루 인수 앞에 전달하거나, `TUIST_TEST_STRESS_NEW_TESTS`를 설정하여 CI 레인별로 모드를 변경하세요:

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

<!-- @snippet: ./_stress-reruns -->

재실행은 첫 번째 패스에서 빌드된 내용을 재사용합니다.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
