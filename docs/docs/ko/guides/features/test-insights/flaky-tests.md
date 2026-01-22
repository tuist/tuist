---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# 불안정한 테스트 {#flaky-tests}

::: warning 요구 사항
<!-- -->
- <LocalizedLink href="/guides/features/test-insights">테스트 인사이트</LocalizedLink>은
  반드시 구성되어야 합니다
<!-- -->
:::

불안정한 테스트란 동일한 코드로 여러 번 실행했을 때 다른 결과(통과 또는 실패)를 내는 테스트를 말합니다. 이는 테스트 스위트에 대한 신뢰를
훼손하고, 개발자가 허위 실패를 조사하는 데 시간을 낭비하게 만듭니다. Tuist는 불안정한 테스트를 자동으로 감지하고 시간 경과에 따른 추적을
지원합니다.

![불안정한 테스트 페이지](/images/guides/features/test-insights/flaky-tests-page.png)

## 불안정성 감지 방식 {#how-it-works}

Tuist는 두 가지 방법으로 불안정한 테스트를 감지합니다:

### 테스트 재시도 {#test-retries}

Xcode의 재시도 기능( `-retry-tests-on-failure` 또는 `-test-iterations` 사용)으로 테스트를 실행할 때,
Tuist는 각 시도 결과를 분석합니다. 일부 시도에서는 실패하지만 다른 시도에서는 통과하는 테스트는 불안정(flaky)으로 표시됩니다.

예를 들어, 테스트가 첫 번째 시도에서는 실패하지만 재시도에서는 통과하는 경우, Tuist는 이를 불안정한 테스트(flaky test)로
기록합니다.

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![불안정한 테스트 케이스 세부
정보](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 크로스 런 감지 {#cross-run-detection}

테스트 재시도 없이도 Tuist는 동일한 커밋에 대한 서로 다른 CI 실행 간 결과를 비교하여 불안정한 테스트를 감지할 수 있습니다. 동일한
커밋에 대해 한 CI 실행에서는 테스트가 통과했지만 다른 실행에서는 실패한 경우, 두 실행 모두 불안정(flaky)으로 표시됩니다.

이는 재시도(retry)로 잡아내기에는 실패가 충분히 일관되지 않지만, 여전히 간헐적인 CI 실패를 유발하는 불안정한 테스트를 포착하는 데 특히
유용합니다.

## 불안정한 테스트 관리 {#managing-flaky-tests}

### 자동 지우기

Tuist는 14일 동안 불안정하지 않은 테스트에서 자동으로 불안정 플래그를 제거합니다. 이는 수정된 테스트가 무기한 불안정 상태로 남아 있지
않도록 보장합니다.

### 수동 관리

테스트 케이스 상세 페이지에서 수동으로 테스트를 불안정(flaky)으로 표시하거나 표시를 해제할 수도 있습니다. 다음 경우에 유용합니다:
- 알려진 불안정한 테스트를 수정 작업 중임을 알리고자 함
- 인프라 문제로 인해 테스트가 잘못된 플래그가 지정되었습니다

## Slack 알림 {#slack-notifications}

Slack 통합에서
<LocalizedLink href="/guides/integrations/slack#flaky-test-alerts">불안정한 테스트
알림</LocalizedLink>을 설정하면 테스트가 불안정해질 때 즉시 알림을 받습니다.
