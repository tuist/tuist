---
title: 로깅
titleTemplate: :title · CLI · Tuist
description: Tuist의 로깅 활성화와 설정 방법 배우기.
---

# 로깅 {#logging}

CLI는 내부적으로 메세지를 기록하여 문제 확인에 도움을 줍니다.

## 로깅 사용하여 문제 진단하기 {#diagnose-issues-using-logs}

명령어 수행이 원하는 결과를 가져오지 못한다면, 로그를 살펴보면서 문제의 원인을 파악해 볼 수 있습니다. CLI가 로그를 [OSLog](https://developer.apple.com/documentation/os/oslog)와 파일 시스템으로 전달해줍니다.

실행 시 마다, `$XDG_STATE_HOME/tuist/logs/{uuid}.log`경로에 로그 파일을 생성합니다. 환경 변수가 설정되어 있지 않다면, `$XDG_STATE_HOME`는 `~/.local/state`로 되어 있습니다.

예기치 않게 실행이 종료되었을 때, 기본적으로 CLI는 로그 경로를 출력합니다. 만일 로그 경로가 출력되지 않았다면, 위에 명시된 경로에서 로그(가장 최근의 로그)를 확인할 수 있습니다.

> [!중요]
> 민감한 정보는 지워지지 않으니, 로그를 공유할 때 주의하세요.

### 지속적인 통합 {#diagnose-issues-using-logs-ci}

환경 설정이 일회용인 CI에서, Tuist 로그를 추출하기 위해서 CI 파이프라인 설정을 할 수 있습니다.
아티팩트(artifacts) 추출은 CI 서비스에서 일반적으로 사용되는 기능이고, 서비스맏 설정이 다릅니다.
예를 들어, 깃헙 액션(GitHub Actions)에서는 `actions/upload-artifact` 액션을 사용해서 로그를 아티팩트로 업로드할 수 있습니다:

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
