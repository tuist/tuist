---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# 디렉토리 {#directories}

Tuist는 [XDG 기본 디렉토리
사양](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)에
따라 시스템의 여러 디렉터리에 파일을 구성합니다. 이는 구성, 캐시 및 상태 파일을 관리하기 위한 깔끔하고 표준적인 방법을 제공합니다.

## 지원되는 환경 변수 {#supported-environment-variables}

투이스트는 표준 XDG 변수와 투이스트 전용 접두사가 붙은 변수를 모두 지원합니다. Tuist 전용 변형( `TUIST_`)이 우선적으로
적용되므로 다른 애플리케이션과 별도로 Tuist를 구성할 수 있습니다.

### 구성 디렉터리 {#configuration-directory}

**환경 변수:**
- `TUIST_XDG_CONFIG_HOME` (우선 적용)
- `xdg_config_home`

**기본값:** `~/.config/tuist`

**사용 용도:**
- 서버 자격 증명 (`credentials/{host}.json`)

**예시:**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### 캐시 디렉터리 {#cache-directory}

**환경 변수:**
- `TUIST_XDG_CACHE_HOME` (우선 순위)
- `XDG_CACHE_HOME`

**기본값:** `~/.cache/tuist`

**사용 용도:**
- **플러그인**: 플러그인 캐시 다운로드 및 컴파일
- **프로젝트 설명 헬퍼**: 컴파일된 프로젝트 설명 도우미
- **매니페스트**: 캐시된 적하목록 파일
- **프로젝트**: 생성된 자동화 프로젝트 캐시
- **편집 프로젝트**: 편집 명령 캐시
- **실행**: 실행 분석 데이터 테스트 및 구축
- **바이너리**: 아티팩트 바이너리 빌드(환경 간에 공유할 수 없음)
- **셀렉티브 테스트**: 선택적 테스트 캐시

**예시:**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### 상태 디렉토리 {#state-directory}

**환경 변수:**
- `TUIST_XDG_STATE_HOME` (우선 적용)
- `XDG_STATE_HOME`

**기본값:** `~/.local/state/tuist`

**사용 용도:**
- **로그**: 로그 파일 (`logs/{uuid}.log`)
- **잠금**: 인증 잠금 파일 (`{handle}.sock`)

**예시:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## 우선 순위 {#precedence-order}

사용할 디렉터리를 결정할 때 Tuist는 다음 순서로 환경 변수를 확인합니다:

1. **튜이스트 전용 변수** (예: `TUIST_XDG_CONFIG_HOME`)
2. **표준 XDG 변수** (예: `XDG_CONFIG_HOME`)
3. **기본 위치** (예: `~/.config/tuist`)

이를 통해 다음을 수행할 수 있습니다:
- 표준 XDG 변수를 사용하여 모든 애플리케이션을 일관되게 구성하세요
- 다른 위치가 필요한 경우 Tuist 전용 변수로 재정의하기
- 별도의 설정 없이 합리적인 기본값을 사용하세요

## 일반적인 사용 사례 {#common-use-cases}

### 프로젝트별로 Tuist 격리하기 {#isolating-tuist-per-project}

프로젝트별로 Tuist의 캐시와 상태를 분리하고 싶을 수도 있습니다:

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### CI/CD 환경 {#ci-cd-environments}

CI 환경에서는 임시 디렉터리를 사용할 수 있습니다:

```yaml
# GitHub Actions example
env:
  TUIST_XDG_CACHE_HOME: /tmp/tuist-cache
  TUIST_XDG_STATE_HOME: /tmp/tuist-state

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: tuist generate
      - name: Upload logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist-state/logs/*.log
```

### 격리된 디렉터리로 디버깅하기 {#debugging-with-isolated-directories}

문제를 디버깅할 때는 백지 상태가 필요할 수 있습니다:

```bash
# Create temporary directories for debugging
export TUIST_XDG_CACHE_HOME=$(mktemp -d)
export TUIST_XDG_STATE_HOME=$(mktemp -d)
export TUIST_XDG_CONFIG_HOME=$(mktemp -d)

# Run Tuist commands
tuist generate

# Clean up when done
rm -rf $TUIST_XDG_CACHE_HOME $TUIST_XDG_STATE_HOME $TUIST_XDG_CONFIG_HOME
```
