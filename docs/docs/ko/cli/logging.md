---
title: 로깅
titleTemplate: :title · CLI · Tuist
description: Tuist의 로깅 활성화와 설정 방법 배우기.
---

# 로깅 {#logging}

CLI는 내부적으로 메세지를 기록하여 문제 확인에 도움을 줍니다.

## 로깅 사용하여 문제 진단하기 {#diagnose-issues-using-logs}

명령어 수행이 원하는 결과를 가져오지 못한다면, 로그를 살펴보면서 문제의 원인을 파악해 볼 수 있습니다. The CLI forwards the logs to [OSLog](https://developer.apple.com/documentation/os/oslog) and the file-system.

실행할 때 마다, `$XDG_STATE_HOME/tuist/logs/{uuid}.log`경로에 로그 파일을 생성합니다. 환경 변수가 설정되어 있지 않다면, `$XDG_STATE_HOME` 는 `~/.local/state` 로 되어 있습니다.

By default, the CLI outputs the logs path when the execution exits unexpectedly. If it doesn't, you can find the logs in the path mentioned above (i.e., the most recent log file).

> [!IMPORTANT]
> Sensitive information is not redacted, so be cautious when sharing logs.

### 지속적인 통합 {#diagnose-issues-using-logs-ci}

In CI, where environments are disposable, you might want to configure your CI pipeline to export Tuist logs.
Exporting artifacts is a common capability across CI services, and the configuration depends on the service you use.
For example, in GitHub Actions, you can use the `actions/upload-artifact` action to upload the logs as an artifact:

```yaml
name: Node CI

on: [push]

env:
  $XDG_STATE_HOME: /tmp/tuist

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
