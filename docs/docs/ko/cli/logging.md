---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# 로깅 {#로깅}

CLI는 내부적으로 메시지를 기록하여 문제를 진단하는 데 도움을 줍니다.

## 로그를 사용하여 문제 진단 {#diagnose-issues-using-log}

명령을 호출해도 의도한 결과가 나오지 않으면 로그를 검사하여 문제를 진단할 수 있습니다. CLI는 로그를
[OSLog](https://developer.apple.com/documentation/os/oslog) 및 파일 시스템으로 전달합니다.

실행할 때마다 `$XDG_STATE_HOME/tuist/logs/{uuid}.log에 로그 파일을 생성합니다.` 여기서
`$XDG_STATE_HOME` 환경 변수가 설정되지 않은 경우 `~/.local/state` 값을 가져옵니다.

기본적으로 CLI는 실행이 예기치 않게 종료될 때 로그 경로를 출력합니다. 그렇지 않은 경우 위에서 언급한 경로(즉, 가장 최근 로그 파일)에서
로그를 찾을 수 있습니다.

> [중요] 민감한 정보는 삭제되지 않으므로 로그를 공유할 때는 주의하세요.

### 지속적 통합 {#diagnose-issues-using-logs-ci}

환경이 일회용인 CI에서는 튜이스트 로그를 내보내도록 CI 파이프라인을 구성할 수 있습니다. 아티팩트 내보내기는 모든 CI 서비스에서 공통적으로
사용할 수 있는 기능이며, 구성은 사용하는 서비스에 따라 다릅니다. 예를 들어 GitHub 액션에서는
`actions/upload-artifact` 액션을 사용하여 로그를 아티팩트로 업로드할 수 있습니다:

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
