---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# 로그 {#logging}

CLI는 문제를 진단하는데 도움이 되는 메세지를 내부적으로 기록합니다.

## 로그를 사용해 문제 진단 {#diagnose-issues-using-logs}

명령어 실행이 원하지 않는 결과가 나오면 로그를 확인해 문제를 진단할 수 있습니다. CLI는 로그를
[OSLog](https://developer.apple.com/documentation/os/oslog)와 파일 시스템으로 전달합니다.

실행할 때마다 `$XDG_STATE_HOME/tuist/logs/{uuid}.log`에 로그 파일을 생성하는데, `$XDG_STATE_HOME`
환경 변수가 설정되지 않은 경우 `~/.local/state` 경로를 사용합니다. Tuist 전용 상태 디렉터리를 설정하기 위해
`$XDG_STATE_HOME` 보다 우선하는 `$TUIST_XDG_STATE_HOME`를 사용할 수도 있습니다.

::: tip
<!-- -->
<LocalizedLink href="/cli/directories">디렉토리 설명서</LocalizedLink>에서 Tuist의 디렉토리 구성
및 사용자 지정 디렉토리를 설정하는 방법에 대해 자세히 알아보세요.
<!-- -->
:::

기본적으로 CLI는 실행이 예기치 않게 종료되면 로그 경로를 출력합니다. 그렇지 않으면, 위에서 언급한 경로에서 로그를 확인할 수 있습니다.

::: warning
<!-- -->
민감한 정보는 수정되지 않으므로 로그를 공유할 때 주의해야 합니다.
<!-- -->
:::

### 지속적 통합(CI) {#diagnose-issues-using-logs-ci}

환경이 일회성인 CI에서 CI 파이프라인이 Tuist 로그를 내보내도록 구성할 수 있습니다. 아티팩트(Artifact)를 내보내는 것은 대부분의
CI 서비스에서 공통적으로 지원하는 기능이며, 구성 방법은 서비스에 따라 다릅니다. 예를 들어 GitHub Actions에서는
`actions/upload-artifact` 액션으로 로그를 아티팩트로 업로드할 수 있습니다.

```yaml
name: Node CI

on: [push]

env:
  TUIST_XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```

### 캐시 데몬 디버깅 {#cache-daemon-debugging}

캐시 관련 문제를 디버깅하기 위해, Tuist는 하위 시스템 `dev.tuist.cache`를 가지고 `os_log` 를 사용하여 캐시 데몬
작업을 기록합니다. 아래 명령 사용하여 이 로그를 실시간으로 스트리밍할 수 있습니다:

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

이 로그는 `dev.tuist.cache`으로 하위 시스템을 필터링하여 콘솔 앱에서도 볼 수 있습니다. 이는 캐시 작업에 대한 자세한 정보를
제공하여, 캐시 업로드, 다운로드 및 통신 문제를 진단하는 데 도움이 될 수 있습니다.
