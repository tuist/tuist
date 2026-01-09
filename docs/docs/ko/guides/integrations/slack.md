---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slack 통합 {#slack}

조직에서 Slack을 사용하는 경우, Tuist를 통합하여 채널에서 바로 인사이트를 표시할 수 있습니다. 이렇게 하면 팀이 기억해야 하는
모니터링이 자동으로 수행되는 모니터링으로 바뀝니다. 예를 들어, 팀은 빌드 성능, 캐시 적중률 또는 번들 크기 추세에 대한 일일 요약을 받을 수
있습니다.

## 설정 {#setup}

### Slack 워크스페이스 연결 {#connect-workspace}

먼저, `통합` 탭에서 Slack 워크스페이스를 Tuist 계정에 연결합니다:

![Slack 연결이 있는 통합 탭을 보여주는
이미지](/images/guides/integrations/slack/integrations.png)

**Slack 연결** 을 클릭하여 Tuist가 워크스페이스에 메시지를 게시할 수 있도록 승인합니다. 그러면 연결을 승인할 수 있는 Slack의
승인 페이지로 리디렉션됩니다.

> [참고] 슬랙 관리자 승인 슬랙 워크스페이스에서 앱 설치를 제한하는 경우 슬랙 관리자에게 승인을 요청해야 할 수 있습니다. Slack은 승인
> 과정에서 승인 요청 프로세스를 안내합니다.

### 프로젝트 보고서 {#project-reports}

After connecting Slack, configure reports for each project in the project
settings' notifications tab:

![An image that shows the notifications settings with Slack report
configuration](/images/guides/integrations/slack/notifications-settings.png)

구성할 수 있습니다:
- **채널**: 보고서를 수신할 Slack 채널을 선택합니다.
- **스케줄**: 보고서를 받을 요일 선택
- **시간**: 하루 중 시간 설정

구성이 완료되면 Tuist는 선택한 Slack 채널로 자동화된 일일 보고서를 전송합니다:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### Alert rules {#alert-rules}

Get notified in Slack with alert rules when key metrics significantly regress to
help you catch slower builds, cache degradation, or test slowdowns as soon as
possible, minimizing the impact on your team's productivity.

To create an alert rule, go to your project's notification settings and click
**Add alert rule**:

구성할 수 있습니다:
- **Name**: A descriptive name for the alert
- **Category**: What to measure (build duration, test duration, or cache hit
  rate)
- **Metric**: How to aggregate the data (p50, p90, p99, or average)
- **Deviation**: The percentage change that triggers an alert
- **Rolling window**: How many recent runs to compare against
- **Slack channel**: Where to send the alert

For example, you might create an alert that triggers when the p90 build duration
increases by more than 20% compared to the previous 100 builds.

When an alert triggers, you'll receive a message like this in your Slack
channel:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD After an alert triggers, it won't fire again for the
> same rule for 24 hours. This prevents notification fatigue when a metric stays
> elevated.

## 온프레미스 설치 {#on-premise}

온프레미스 Tuist 설치의 경우, 자체 Slack 앱을 만들고 필요한 환경 변수를 구성해야 합니다.

### Slack 앱 만들기 {#create-slack-app}

1. Slack API 앱 페이지](https://api.slack.com/apps)로 이동하여 **새 앱 만들기를 클릭합니다.**
2. **앱 매니페스트** 에서 앱을 설치할 작업 공간을 선택합니다.
3. 다음 매니페스트를 붙여넣고 리디렉션 URL을 Tuist 서버 URL로 바꿉니다:

```json
{
    "display_information": {
        "name": "Tuist",
        "description": "Get regular updates and alerts for your builds, tests, and caching.",
        "background_color": "#6f2cff"
    },
    "features": {
        "bot_user": {
            "display_name": "Tuist",
            "always_online": false
        }
    },
    "oauth_config": {
        "redirect_urls": [
            "https://your-tuist-server.com/integrations/slack/callback"
        ],
        "scopes": {
            "bot": [
                "chat:write",
                "chat:write.public"
            ]
        }
    },
    "settings": {
        "org_deploy_enabled": false,
        "socket_mode_enabled": false,
        "token_rotation_enabled": false
    }
}
```

4. 앱 검토 및 생성

### 환경 변수 구성 {#configure-environment}

Tuist 서버에서 다음 환경 변수를 설정합니다:

- `SLACK_CLIENT_ID` - Slack 앱의 기본 정보 페이지에 있는 클라이언트 ID입니다.
- `SLACK_CLIENT_SECRET` - Slack 앱의 기본 정보 페이지에 있는 클라이언트 비밀입니다.
