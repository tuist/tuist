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
variable is not set.

By default, the CLI outputs the logs path when the execution exits unexpectedly.
If it doesn't, you can find the logs in the path mentioned above (i.e., the most
recent log file).

::: warning
<!-- -->
Sensitive information is not redacted, so be cautious when sharing logs.
<!-- -->
:::

### Continuous integration {#diagnose-issues-using-logs-ci}

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
