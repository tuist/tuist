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

Slack에 연결한 후 프로젝트 설정의 알림 탭에서 각 프로젝트에 대한 보고서를 구성합니다:

![Slack 보고서 구성의 알림 설정을 보여주는
이미지](/images/guides/integrations/slack/notifications-settings.png)

구성할 수 있습니다:
- **채널**: 보고서를 수신할 Slack 채널을 선택합니다.
- **스케줄**: 보고서를 받을 요일 선택
- **시간**: 하루 중 시간 설정

구성이 완료되면 Tuist는 선택한 Slack 채널로 자동화된 일일 보고서를 전송합니다:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### 알림 규칙 {#alert-rules}

주요 지표가 크게 후퇴할 때 Slack에서 알림 규칙을 통해 알림을 받으면 빌드 속도 저하, 캐시 성능 저하 또는 테스트 속도 저하를 최대한
빨리 파악하여 팀의 생산성에 미치는 영향을 최소화할 수 있습니다.

알림 규칙을 만들려면 프로젝트의 알림 설정으로 이동하여 **알림 규칙 추가** 를 클릭합니다:

구성할 수 있습니다:
- **이름**: 알림에 대한 설명적인 이름
- **카테고리**: 측정 대상(빌드 기간, 테스트 기간 또는 캐시 적중률)
- **메트릭**: 데이터 집계 방법(p50, p90, p99 또는 평균)
- **편차**: 경고를 트리거하는 변화 비율
- **롤링 창**: 비교할 최근 실행 횟수
- **Slack 채널**: 알림을 보낼 위치

예를 들어 p90 빌드 기간이 이전 100 빌드에 비해 20% 이상 증가하면 트리거되는 알림을 만들 수 있습니다.

알림이 트리거되면 Slack 채널에서 이와 같은 메시지를 받게 됩니다:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [참고] 쿨다운 기간 알림이 트리거된 후에는 24시간 동안 동일한 규칙에 대해 다시 알림이 트리거되지 않습니다. 이렇게 하면 지표가 계속
> 높아져도 알림 피로를 방지할 수 있습니다.

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
