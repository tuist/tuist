---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# 튜이스트 설치 {#install-tuist}

Tuist CLI는 실행 가능한 동적 프레임워크와 일련의 리소스(예: 템플릿)로 구성되어 있습니다.
소스](https://github.com/tuist/tuist)( **)에서 Tuist를 수동으로 빌드할 수도 있지만, 올바른 설치를 위해 다음
설치 방법 중 하나를 사용하는 것이 좋습니다.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

::: 정보 Mise는 다양한 환경에서 결정론적 버전의 도구를 보장해야 하는 팀이나 조직인 경우
[Homebrew](https://brew.sh)의 대안으로 권장됩니다.:::

다음 명령어 중 하나를 통해 Tuist를 설치할 수 있습니다:

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

단일 버전의 도구를 전역적으로 설치하고 활성화하는 Homebrew와 같은 도구와 달리 **Mise는 전역적으로 또는 프로젝트에 한정된** 버전을
활성화해야 합니다. 이 작업은 `mise 사용` 을 실행하여 수행합니다:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">홈브루</a> {#recommended-homebrew}

홈브라우저](https://brew.sh) 및 [공식](https://github.com/tuist/homebrew-tuist)를 사용하여
Tuist를 설치할 수 있습니다:

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: 팁 바이너리의 신뢰성 확인 다음 명령을 실행하여 인증서의 팀이 `U6LC622NKF` 인지 확인하여 설치 바이너리가 당사에 의해
빌드되었는지 확인할 수 있습니다:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
:::
