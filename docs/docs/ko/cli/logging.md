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

각 실행마다 `$XDG_STATE_HOME/tuist/logs/{uuid}.log` 위치에 로그 파일을 생성하고,
`$XDG_STATE_HOME`은 환경 변수가 설정되어 있지 않으면 `~/.local/state`입니다.

기본적으로 CLI는 실행이 예기치 않게 종료되면 로그 경로를 출력합니다. 그렇지 않으면, 위에서 언급한 경로에서 로그를 확인할 수 있습니다.

::: warning
<!-- -->
민감한 정보는 수정되지 않으므로 로그를 공유할 때 주의해야 합니다.
<!-- -->
:::

### 지속적 통합(CI) {#diagnose-issues-using-logs-ci}

In CI, where environments are disposable, you might want to configure your CI
pipeline to export Tuist logs. Exporting artifacts is a common capability across
CI services, and the configuration depends on the service you use. For example,
in GitHub Actions, you can use the `actions/upload-artifact` action to upload
the logs as an artifact:

```yaml
name: Node CI

on: [push]

env:
  XDG_STATE_HOME: /tmp

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
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```
