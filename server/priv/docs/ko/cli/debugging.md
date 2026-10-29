---
{
  "title": "디버깅",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "로그와 네트워크 기록을 사용하여 Tuist의 문제를 디버깅하는 방법을 알아보세요."
}
---
# 디버깅 {#debugging}

명령어가 예상대로 동작하지 않을 때 문제를 진단할 수 있도록 Tuist는 여러 도구를 제공합니다.

> [!WARNING]
> 세션 데이터에는 파일 경로, 프로젝트 이름, 요청/응답 본문과 같은 민감한 정보가 포함될 수 있습니다. 민감한 헤더(예: Authorization)는 가려지지만, 다른 사람과 세션 데이터를 공유할 때는 주의하세요.


## 세션 데이터 {#session-data}

명령어 실행이 의도한 결과를 내지 못한다면 세션 데이터를 검사하여 문제를 진단할 수 있습니다. CLI는 로그를 [OSLog](https://developer.apple.com/documentation/os/oslog)와 파일 시스템으로 전달합니다.

매번 실행 시 `$XDG_STATE_HOME/tuist/sessions/{uuid}/`에 세션 디렉터리를 생성하며, 환경 변수가 설정되지 않은 경우 `$XDG_STATE_HOME`는 `~/.local/state` 값을 사용합니다. 또한 `$TUIST_XDG_STATE_HOME`를 사용하여 Tuist 전용 상태 디렉터리를 설정할 수 있으며, 이는 `$XDG_STATE_HOME`보다 우선 적용됩니다.

각 세션 디렉터리에는 다음이 포함됩니다:
- **`logs.txt`** - CLI 세션의 텍스트 로그
- **`network.har`** - 세션 중 발생한 모든 네트워크 요청 및 응답을 포함하는 [HTTP Archive (HAR)](https://w3c.github.io/web-performance/specs/HAR/Overview.html) 파일

### HAR 파일 시각화 {#visualizing-har-files}

HAR 파일은 세션 중 발생한 모든 HTTP 요청과 응답을 기록하므로 서버 통신 문제를 디버깅하는 데 유용합니다. 여러 도구로 HAR 파일을 열 수 있습니다:

- **[Proxyman](https://proxyman.io/)**: HTTP 트래픽을 보고 분석하는 네이티브 macOS 앱입니다. File > Import를 통해 HAR 파일을 가져옵니다.
- **브라우저 개발자 도구**: Chrome, Firefox, Safari 모두 Network 탭에서 HAR 파일 가져오기를 지원합니다.
- **[HAR Viewer](http://www.softwareishard.com/har/viewer/)**: 웹 기반 HAR 파일 뷰어입니다.

> [!TIP]
> Tuist의 디렉터리 구조와 사용자 정의 디렉터리 구성 방법에 대해 더 알아보려면 <.localized_link href="/cli/directories">디렉터리 문서</.localized_link>를 참조하세요.


기본적으로 CLI는 실행이 예기치 않게 종료될 때 세션 경로를 출력합니다. 그렇지 않은 경우 위에서 언급한 경로(즉, 가장 최근 세션 디렉터리)에서 세션 데이터를 찾을 수 있습니다.

5일 이상 된 세션 디렉터리는 자동으로 정리됩니다. Tuist는 기본적으로 최대 50개의 비활성 세션 디렉터리를 유지하며, 현재 실행 중인 Tuist 프로세스가 소유한 세션은 보존합니다. 동일한 상태 디렉터리를 사용하여 많은 Tuist 명령어를 실행하는 CI 환경에서는 `TUIST_SESSION_MAX_SESSIONS`을 통해 비활성 세션 상한을 높일 수 있습니다(예: `TUIST_SESSION_MAX_SESSIONS=200`). 잘못된 값, 0, 음수 값은 무시되며 Tuist는 기본값인 50으로 되돌아갑니다.

### 지속적 통합 {#diagnose-issues-using-logs-ci}

환경이 일회용인 CI에서는 CI 파이프라인을 구성하여 Tuist 세션 데이터를 내보내도록 할 수 있습니다. 아티팩트 내보내기는 CI 서비스 전반에서 일반적으로 지원되는 기능이며, 구성은 사용하는 서비스에 따라 다릅니다. 예를 들어 GitHub Actions에서는 `actions/upload-artifact` 액션을 사용하여 세션 데이터를 아티팩트로 업로드할 수 있습니다:

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
      - name: Export Tuist session data
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-sessions
          path: /tmp/tuist/sessions/
```

### Xcode 캐시 디버깅 {#cache-daemon-debugging}

Xcode 캐시 문제를 디버깅하려면 `tuist setup cache` 실행 시와 빌드 시 모두 `TUIST_CAS_LOG`을 파일 경로로 설정하세요. Tuist는 해당 파일에 캐시 통계와 오류를 추가합니다:

```bash
export TUIST_CAS_LOG=$HOME/.local/state/tuist/cas.log
tuist setup cache
xcodebuild build -scheme YourScheme
```

CI에서는 Tuist가 별도 구성 없이 이 로그를 `~/.local/state/tuist/cas.log`에 기록합니다.

## 네트워크 타임아웃 및 재시도 조정 {#tuning-network-timeouts}

서버 호출, 레지스트리, 프리뷰, 캐시 아티팩트 전송을 포함한 Tuist의 모든 [Hypertext Transfer Protocol (HTTP)](https://developer.mozilla.org/en-US/docs/Web/HTTP) 트래픽은 합리적인 기본값을 가진 공유 `URLSession`를 통해 처리됩니다. 느리거나 혼잡한 네트워크 경로(예: 기업 프록시를 통해 오브젝트 스토리지에 접근하는 자체 호스팅 설정)에서는 개별 요청이 리소스 타임아웃에 도달하여 완료 전에 중단될 수 있습니다. 특히 캐시 다운로드의 경우 타임아웃에 도달하면 Tuist는 모듈을 소스에서 빌드하는 방식으로 fallback하는데, 이는 캐시된 바이너리를 조금 더 기다리는 것보다 훨씬 비용이 큽니다. 환경 변수를 통해 기본 설정을 조정할 수 있으며, 설정되지 않았거나 잘못된 값으로 설정된 경우 기본값이 적용됩니다:

```bash
# Maximum time (in seconds) a single resource transfer can take before it's cancelled
# (default: 90, or 600 for whole-file transfers such as test-product shard artifacts)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE=600

# Maximum time (in seconds) to wait for new data on an existing request (default: 120)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST=300

# Maximum number of simultaneous connections per host (default: 20)
export TUIST_HTTP_MAXIMUM_CONNECTIONS_PER_HOST=40

# Maximum retries after the initial attempt (default: 3, maximum: 10)
export TUIST_HTTP_MAXIMUM_RETRY_COUNT=1

# Initial exponential backoff delay in milliseconds (default: 100, maximum: 30000)
export TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS=250
```

리소스 타임아웃은 전체 전송에 대한 벽시계 기준 상한이며, 정지 방지 장치가 아니므로 이동하는 가장 큰 아티팩트에 충분히 큰 값이어야 합니다. 따라서 샤드가 다운로드하는 테스트 제품과 같은 전체 파일 전송은 90초 대신 기본적으로 10분으로 설정되며, 새로운 데이터 없이 `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST` 이후에는 정지된 전송도 실패합니다. 이러한 전송은 `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE`를 읽어 상한을 높이기만 하며, 10분 미만으로 낮추지는 않으므로 캐시 요청을 빠르게 실패시키기 위해 선택한 값이 샤드의 테스트 제품 다운로드까지 취소하지는 않습니다. `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE`을 높이면 타임아웃 대신 복구 가능하지만 느린 다운로드가 완료될 수 있습니다. 캐시 다운로드의 경우 이는 소스 빌드로 fallback하는 대신 캐시 히트를 달성한다는 의미이므로 의도적으로 높여야 합니다. 느린 캐시 다운로드를 유지하는 동일한 값은 소스 빌드로의 fallback도 지연시킵니다. `TUIST_HTTP_MAXIMUM_RETRY_COUNT`를 낮추면 더 긴 타임아웃이 여러 시도 동안 최악의 대기 시간을 증폭시키는 것을 방지할 수 있습니다. 재시도 지연은 각 실패 후 두 배가 되며, 최대 하나의 기본 지연 시간에 무작위 지터를 포함하고 30초를 초과하지 않습니다.

## 사용자 정의 CA 인증서 신뢰 {#trusting-a-custom-ca-certificate}

기본적으로 Tuist는 운영 체제의 루트 저장소를 기준으로 TLS 인증서를 검증합니다. 개인 인증 기관을 사용하는 자체 호스팅 Tuist 또는 Kura 서버를 실행하는 경우, Tuist도 해당 CA를 신뢰해야 합니다. 시스템 키체인에 루트를 설치하고(SSL에 대해 신뢰됨으로 표시) 하는 것이 표준 접근 방식이지만, GUI 세션이나 모바일 장치 관리(MDM)가 없어 신뢰 비트를 설정할 수 없는 헤드리스 CI 호스트에서는 종종 실용적이지 않습니다.

이러한 경우 Tuist를 CA 인증서 번들로 직접 지정할 수 있습니다. 번들은 PEM(연결된 `-----BEGIN CERTIFICATE-----` 블록 하나 이상) 또는 단일 DER 파일일 수 있습니다. 시스템 루트 저장소는 이와 함께 계속 신뢰되므로 공개 인증서는 정상적으로 검증되며 인증서 평가는 우회되지 않습니다.

```bash
# Path to a PEM/DER CA bundle to trust on top of the system root store (default: unset)
export TUIST_CA_CERTIFICATE=/etc/ssl/certs/self-hosted-ca.pem
```

<.localized_link href="/references/tuist-toml">구성 파일</.localized_link>에도 선언할 수 있습니다:

```toml
[network]
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

`TUIST_CA_CERTIFICATE` 환경 변수는 구성 파일보다 우선 적용되므로, 커밋된 매니페스트를 변경하지 않고 CI 비밀로 제공하기 편리합니다.
