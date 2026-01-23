---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slack 통합 {#slack}

조직에서 Slack을 사용한다면 Tuist를 통합하여 채널 내에서 직접 인사이트를 확인할 수 있습니다. 이를 통해 모니터링이 팀이 기억해야 하는
작업에서 자동으로 이루어지는 과정으로 바뀝니다. 예를 들어, 팀은 빌드 성능, 캐시 적중률 또는 번들 크기 추세에 대한 일일 요약 정보를 수신할
수 있습니다.

## 설정 {#setup}

### Slack 워크스페이스를 연결하세요 {#connect-workspace}

먼저, `통합 설정` 탭에서 Slack 작업 공간을 Tuist 계정에 연결하세요:

![Slack 연결이 설정된 통합 탭을 보여주는
이미지](/images/guides/integrations/slack/integrations.png)

**를 클릭하세요. Slack** 에 연결하여 Tuist가 귀하의 작업 공간에 메시지를 게시할 수 있도록 권한을 부여하세요. 이 작업은
Slack의 인증 페이지로 이동하여 연결을 승인할 수 있게 합니다.

> [!NOTE] SLACK 관리자 승인
> <!-- -->
> Slack 작업 공간에서 앱 설치를 제한하는 경우, Slack 관리자에게 승인을 요청해야 할 수 있습니다. Slack은 인증 과정에서 승인
> 요청 절차를 안내해 드립니다.
> <!-- -->

### 프로젝트 보고서 {#project-reports}

Slack 연결 후, 프로젝트 설정의 알림 탭에서 각 프로젝트별 보고서를 구성하세요:

![Slack 보고서 설정이 적용된 알림 설정 화면
이미지](/images/guides/integrations/slack/notifications-settings.png)

다음과 같이 설정할 수 있습니다:
- **채널**: 보고서를 수신할 Slack 채널을 선택하세요
- ****: 보고서를 받을 요일을 선택하세요
- **시간 설정:**

> [!경고] 비공개 채널
> <!-- -->
> Tuist Slack 앱이 비공개 채널에 메시지를 게시하려면 먼저 해당 채널에 Tuist 봇을 추가해야 합니다. Slack에서 비공개 채널을
> 열고, 채널 이름을 클릭하여 설정을 연 후 "통합"을 선택하세요. 그런 다음 "앱 추가"를 클릭하고 Tuist를 검색하세요.
> <!-- -->

설정이 완료되면 Tuist는 선택한 Slack 채널로 자동화된 일일 보고서를 전송합니다:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### 경고 규칙 {#alert-rules}

핵심 지표가 크게 악화될 때 Slack 알림 규칙으로 즉시 알려주어 빌드 지연, 캐시 성능 저하, 테스트 속도 감소를 최대한 빨리 파악하고 팀
생산성에 미치는 영향을 최소화하세요.

**경고 규칙을 생성하려면 프로젝트의 알림 설정으로 이동하여 '경고 규칙 추가'를 클릭하세요.**:

다음과 같이 설정할 수 있습니다:
- **경고 이름**: 경고를 설명하는 이름
- **카테고리**: 측정 대상(빌드 소요 시간, 테스트 소요 시간 또는 캐시 적중률)
- **메트릭**: 데이터 집계 방법(p50, p90, p99 또는 평균)
- **편차**: 경보를 유발하는 백분율 변화
- **롤링 윈도우**: 비교할 최근 실행 횟수
- **Slack 채널**: 알림을 보낼 곳

예를 들어, p90 빌드 소요 시간이 이전 100회 빌드 대비 20% 이상 증가할 때 트리거되는 알림을 생성할 수 있습니다.

경고가 발생하면 Slack 채널에 다음과 같은 메시지가 표시됩니다:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!NOTE] 쿨다운 기간
> <!-- -->
> 경고가 발생하면 동일한 규칙에 대해 24시간 동안 다시 발동되지 않습니다. 이는 지표가 지속적으로 높은 상태를 유지할 때 발생하는 알림
> 피로를 방지합니다.
> <!-- -->

### 불안정한 테스트 경고 {#flaky-test-alerts}

테스트가 불안정해지면 즉시 알림을 받으세요. 이동 창을 비교하는 지표 기반 경고 규칙과 달리, 불안정 테스트 경고는 Tuist가 새로운 불안정
테스트를 감지하는 즉시 트리거되어 팀에 영향을 미치기 전에 테스트 불안정성을 포착할 수 있도록 도와줍니다.

**불안정한 테스트 경고 규칙을 생성하려면 프로젝트의 알림 설정으로 이동하여 '불안정한 테스트 경고 규칙 추가'를 클릭하세요.**:

다음과 같이 설정할 수 있습니다:
- **경고 이름**: 경고를 설명하는 이름
- **트리거 임계값**: 경고를 트리거하기 위해 지난 30일 동안 필요한 최소 불안정 실행 횟수
- **Slack 채널**: 알림을 보낼 곳

테스트가 불안정해져 설정된 임계값을 충족하면, 해당 테스트 케이스를 조사할 수 있는 직접 링크가 포함된 알림을 받게 됩니다:

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="An image that shows a Slack flaky test alert message" style="max-width: 500px;" />

## 온프레미스 설치 {#on-premise}

온프레미스 Tuist 설치의 경우, 자체 Slack 앱을 생성하고 필요한 환경 변수를 구성해야 합니다.

### Slack 앱 생성 {#create-slack-app}

1. [Slack API Apps 페이지](https://api.slack.com/apps)로 이동하여 ' **'를 클릭하고 새 앱을
   생성하세요.**
2. 앱 매니페스트(** )에서 ' **'를 선택하고 앱을 설치할 작업 공간을 선택하세요.
3. 다음 매니페스트를 붙여넣고, 리다이렉트 URL을 귀하의 Tuist 서버 URL로 대체하십시오:

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

4. 앱을 검토하고 생성하세요

### 환경 변수 설정 {#configure-environment}

Tuist 서버에서 다음 환경 변수를 설정하십시오:

- `SLACK_CLIENT_ID` - Slack 앱의 기본 정보 페이지에서 확인 가능한 클라이언트 ID
- `SLACK_CLIENT_SECRET` - Slack 앱의 기본 정보 페이지에서 확인 가능한 클라이언트 시크릿
