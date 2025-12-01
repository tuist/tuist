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

In every run, it creates a log file at `$XDG_STATE_HOME/tuist/logs/{uuid}.log`
where `$XDG_STATE_HOME` takes the value `~/.local/state` if the environment
variable is not set. You can also use `$TUIST_XDG_STATE_HOME` to set a
Tuist-specific state directory, which takes precedence over `$XDG_STATE_HOME`.

::: tip
<!-- -->
Learn more about Tuist's directory organization and how to configure custom
directories in the <LocalizedLink href="/cli/directories">Directories
documentation</LocalizedLink>.
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

### Cache daemon debugging {#cache-daemon-debugging}

For debugging cache-related issues, Tuist logs cache daemon operations using
`os_log` with the subsystem `dev.tuist.cache`. You can stream these logs in
real-time using:

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

These logs are also visible in Console.app by filtering for the
`dev.tuist.cache` subsystem. This provides detailed information about cache
operations, which can help diagnose cache upload, download, and communication
issues.
