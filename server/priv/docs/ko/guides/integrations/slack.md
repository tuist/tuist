---
{
  "title": "Slack",
  "titleTemplate": ":title | 통합 | 가이드 | Tuist",
  "description": "Tuist의 Slack 통합 사용 방법을 알아보세요."
}
---
# Slack용 Tuist 연동 {#slack}

Slack용 Tuist 연동은 빌드, 테스트, 번들 인사이트를 채널에 직접 표시합니다. 모니터링을 팀이 기억해야 하는 작업에서 자동으로 이루어지는 과정으로 바꿉니다. 예를 들어, 팀은 빌드 성능, 캐시 히트율 또는 번들 크기 추이에 대한 일일 요약과 핵심 지표가 악화되거나 테스트가 불안정해지는 순간 즉시 알림을 받을 수 있습니다.

이 페이지에서는 연동이 수행하는 작업, 채널별로 설치하는 방법, Tuist가 데이터를 처리하는 방식을 설명합니다. Tuist가 서드파티 데이터를 수집, 관리 및 저장하는 방법에 대한 자세한 내용은 [개인정보 보호정책](https://tuist.dev/privacy)을 참조하세요.

## 연동 작동 방식 {#how-it-works}

Tuist는 Slack의 [Incoming Webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks)를 통해 Slack으로 알림을 전송합니다. 이 연동은 `incoming-webhook` 범위만 요청합니다. 각 알림 대상(프로젝트 보고서, 알림 규칙, 불안정한 테스트 알림, 자동화 액션)은 설치 시 선택한 단일 Slack 채널에 해당합니다. Slack은 채널당 하나의 웹후크 URL을 생성하며, Tuist는 이를 저장하여 메시지를 전달합니다.

Tuist는 워크스페이스의 메시지, 멤버 목록 또는 기타 데이터를 읽지 않습니다. 이 연동은 명시적으로 승인한 채널에만 알림을 기록합니다.

## 설정 {#setup}

### 프로젝트 보고서 {#project-reports}

프로젝트 보고서는 프로젝트의 빌드, 테스트 및 캐시 지표에 대한 일일 요약을 원하는 Slack 채널로 전달합니다.

1. Tuist 대시보드에서 프로젝트의 알림 설정을 엽니다.
2. **Select Slack channel**을 클릭하고 Tuist가 게시할 워크스페이스와 채널을 선택하세요. Slack에서 `incoming-webhook` 범위를 승인하고 단일 채널을 선택하도록 요청합니다.
3. 일일 보고서를 받을 요일과 시간을 선택하세요.

![Slack 보고서 구성이 포함된 알림 설정을 보여주는 이미지](/images/guides/integrations/slack/notifications-settings.png)

설정이 완료되면 Tuist는 선택한 채널로 자동화된 일일 보고서를 전송합니다:

<img src="/images/guides/integrations/slack/report.png" alt="Slack 보고서 메시지를 보여주는 이미지" style="max-width: 500px;" />

> [!NOTE] PRIVATE CHANNELS
> <!-- -->
> 비공개 채널에 게시하려면 먼저 Slack 내에서 채널을 열고 인증 단계에서 연동에 표시되는 채널 목록에 추가하세요.
> <!-- -->

### 알림 규칙 {#alert-rules}

알림 규칙은 핵심 지표가 크게 악화될 때 Slack으로 알려주어 빌드 지연, 캐시 성능 저하 또는 테스트 속도 저하를 가능한 한 빨리 파악할 수 있도록 도와줍니다.

알림 규칙을 생성하려면 프로젝트의 알림 설정으로 이동하여 **Add alert rule**을 클릭하세요. 다음을 구성할 수 있습니다:

- **Name**: 알림에 대한 설명 이름
- **Category**: 측정 항목(빌드 지속 시간, 테스트 지속 시간, 캐시 히트율 또는 번들 크기)
- **Metric**: 데이터 집계 방식(p50, p90, p99 또는 평균)
- **Deviation**: 알림을 트리거하는 백분율 변화
- **Rolling window**: 비교할 최근 실행 횟수
- **Branch**: 캐시 히트율 알림의 경우 비교를 단일 브랜치의 실행으로 제한합니다. 모든 브랜치를 고려하려면 비워 두세요. 번들 크기 알림은 항상 단일 브랜치를 대상으로 합니다.
- **Slack channel**: 대상 채널입니다. 위에서 설명한 동일한 `incoming-webhook` 흐름을 통해 채널을 승인합니다.

예를 들어, 이전 100개 빌드와 비교하여 p90 빌드 지속 시간이 20% 이상 증가할 때 트리거되는 알림을 생성할 수 있습니다.

캐시를 채우는 브랜치가 기본 브랜치뿐인 경우 캐시 히트율 알림 범위를 기본 브랜치로 지정하는 것이 유용합니다. 하위 모듈을 변경하는 풀 리퀘스트 브랜치는 정당한 이유로 캐시를 미스하며, 이러한 브랜치를 포함하면 예상된 악화에 대해 알림이 발생하게 됩니다.

캐시 히트율 알림은 공정하게 비교할 수 있는 윈도우만 비교합니다. 두 윈도우 모두 롤링 윈도우 크기만큼의 실행을 포함해야 하며, 두 윈도우 중 하나에만 나타나는 캐시 데이터 소스는 둘 다에서 제외됩니다. 따라서 롤링 윈도우 크기의 두 배에 해당하는 실행을 아직 누적하지 않은 브랜치나 일치하는 항목이 없는 브랜치 이름은 규칙을 트리거하지 않습니다. 트래픽이 적은 브랜치로 규칙 범위를 지정하는 경우, 브랜치가 해당 범위를 채울 수 있을 만큼 롤링 윈도우를 작게 유지하세요.

알림이 트리거되면 Slack 채널에서 다음과 같은 메시지를 받게 됩니다:

<img src="/images/guides/integrations/slack/alert.png" alt="Slack 알림 메시지를 보여주는 이미지" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD
> <!-- -->
> 알림이 트리거된 후 동일한 규칙에 대해 24시간 동안 다시 발생하지 않습니다. 이는 지표가 높은 상태로 유지될 때 알림 피로를 방지합니다.
> <!-- -->

### 불안정한 테스트 알림 {#flaky-test-alerts}

불안정한 테스트 알림은 Tuist가 새로운 불안정한 테스트를 감지하는 순간 트리거되어 팀에 영향을 미치기 전에 테스트 불안정성을 파악할 수 있도록 도와줍니다.

불안정한 테스트 알림 규칙을 생성하려면 프로젝트의 알림 설정으로 이동하여 **Add flaky test alert rule**을 클릭하세요. 다음을 구성할 수 있습니다:

- **Name**: 알림에 대한 설명 이름
- **Trigger threshold**: 알림을 트리거하기 위해 지난 30일 동안 필요한 최소 불안정한 실행 횟수
- **Slack channel**: `incoming-webhook` 흐름을 통해 승인된 대상 채널입니다.

테스트가 불안정해지고 임계값을 충족하면 테스트 케이스를 조사할 수 있는 직접 링크가 포함된 알림을 받게 됩니다:

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="Slack 불안정한 테스트 알림 메시지를 보여주는 이미지" style="max-width: 500px;" />

## 통합 연결 해제 {#disconnect}

알림을 중지하려면 Tuist 대시보드에서 보고서, 알림 규칙 또는 자동화 작업에 구성된 Slack 채널을 제거하세요. Tuist의 액세스를 완전히 취소하려면 Slack 내부에서 **Settings & administration → Manage apps**을 통해 웹훅 통합을 제거하세요.
