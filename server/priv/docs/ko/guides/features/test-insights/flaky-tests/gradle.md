---
{
  "title": "Gradle 불안정한 테스트",
  "titleTemplate": ":title · 불안정한 테스트 · 테스트 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist로 Gradle 프로젝트의 불안정한 테스트를 감지, 관리 및 격리하세요."
}
---
# Gradle 불안정한 테스트 {#gradle-flaky-tests}

> [!IMPORTANT]
> **필수 조건**
>
> - <.localized_link href="/guides/features/test-insights/gradle">Gradle 테스트 인사이트</.localized_link>가 구성되어 있어야 합니다.

<!-- @snippet: ./_intro -->

![불안정한 테스트 페이지](/images/guides/features/test-insights/flaky-tests-page.png)

## 불안정성 감지 방식 {#how-it-works}

Tuist는 두 가지 방식으로 불안정한 테스트를 감지합니다:

### 테스트 재시도 {#test-retries}

재시도 기능을 사용해 테스트를 실행하면 Tuist는 각 시도의 결과를 분석합니다. 일부 시도에서는 실패하고 다른 시도에서는 성공하는 테스트는 불안정한 것으로 표시됩니다.

실패한 테스트를 다시 실행하려면 [Test Retry 플러그인](https://github.com/gradle/test-retry-gradle-plugin)이나 유사한 메커니즘을 사용할 수 있습니다. Tuist는 일부 시도에서는 성공하고 다른 시도에서는 실패하는 테스트를 감지합니다.

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

### 실행 간 교차 감지 {#cross-run-detection}

테스트 재시도가 없어도 Tuist는 동일한 커밋과 동일한 Gradle 프로젝트에서 수행된 서로 다른 CI 실행 간 결과를 비교해 불안정한 테스트를 감지할 수 있습니다. 동일한 커밋과 프로젝트에서 한 CI 실행에서는 통과했지만 다른 실행에서는 실패한 경우, 해당 실패 실행은 불안정한 것으로 표시됩니다.

동일한 테스트라도 프로젝트마다 결정론적으로 다르게 동작할 수 있기 때문에(예: 다른 의존성으로 컴파일된 공유 테스트 클래스나 다른 모듈 픽스처에서 실행) Gradle 프로젝트가 비교 키의 일부로 포함됩니다. 서로 다른 Gradle 프로젝트에서 동일한 커밋을 두 번 실행하면 별개의 실행 변형으로 취급되며 서로를 불안정하다고 표시하지 않습니다.

이는 재시도로 포착될 만큼 일관되게 실패하지는 않지만 여전히 간헐적인 CI 실패를 유발하는 불안정한 테스트를 잡아내는 데 특히 유용합니다.

<!-- @snippet: ./_managing -->

## 불안정한 테스트 격리 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

격리된 테스트는 다음 두 모드 중 하나에 속합니다:

- **Muted**: 테스트는 계속 실행되지만 플러그인이 `ignoreFailures = true`로 설정하고 격리되지 않은 실패에서만 빌드를 다시 실패시킵니다. 실패 정보는 여전히 불안정 테스트 감지기에 전달되므로 빌드를 중단하지 않고 테스트를 계속 모니터링할 수 있습니다. 적극적으로 조사 중인 테스트에 이 모드를 선택하세요.
- **Skipped**: 플러그인이 Gradle의 `excludeTestsMatching`를 통해 테스트를 필터링하므로 테스트가 전혀 시작되지 않습니다. 새로운 결과가 생성되지 않으며 다시 활성화하기 전까지 불안정 테스트 대시보드에서 제외됩니다. 테스트가 손상되었거나 느리거나, 지나치게 지속적으로 불안정해서 실행하면 CI 시간만 낭비되는 경우에 이 모드를 선택하세요.

<!-- @snippet: ./_quarantined-passing -->

### 격리 활성화 {#enabling-quarantine}

격리는 **CI에서 자동으로 활성화**되며(`CI` 환경 변수가 설정된 경우), 로컬 빌드에서는 비활성화됩니다. 플러그인은 각 테스트 작업 전에 Tuist 서버에서 격리된 테스트 목록을 가져옵니다. muted 테스트는 정상적으로 실행되고 실패가 마스킹되며, skipped 테스트는 필터링되어 제외됩니다.

이를 `settings.gradle.kts`에서 명시적으로 제어할 수 있습니다:

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

`enabled`가 설정되지 않으면 자동 감지가 기본값으로 적용됩니다. CI에서는 활성화되고 로컬에서는 비활성화됩니다.

## 새 테스트 부하 테스트 {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

프로젝트의 기본 브랜치 또는 해당 브랜치에 병합된 커밋에서 지난 90일 동안 CI에서 실행된 적이 없는 테스트 케이스는 새 것으로 간주됩니다. 머지 큐를 사용하는 경우, 큐가 실행한 테스트 케이스는 큐의 커밋이 병합되면 인식되며, 큐가 해당 테스트를 제거하면 새 상태로 유지됩니다. 커밋 매칭은 Tuist가 CI에서 수집하는 <.localized_link href="/guides/features/test-insights/gradle#git-history">Git 히스토리</.localized_link>를 통해 이루어집니다.

<!-- @snippet: ./_stress-modes -->

`settings.gradle.kts`에 선언하거나, CI 레인별로 모드를 다르게 설정하려면 `TUIST_TEST_STRESS_NEW_TESTS`를 설정하세요:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

격리와 달리 이 게이트에는 CI 인식 기본값이 없습니다. `mode`가 설정되지 않으면 어디에서도 실행되지 않습니다.

<!-- @snippet: ./_stress-reruns -->

각 재실행은 해당 테스트 케이스 하나로 필터링된 중첩 Gradle 빌드로 수행되므로, 모든 재실행에서 새로운 테스트 JVM을 사용합니다.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
