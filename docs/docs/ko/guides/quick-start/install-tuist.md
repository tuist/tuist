---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Tuist 설치 {#install-tuist}

Tuist CLI는 실행 파일, 동적 프레임워크, 리소스 집합(예: 템플릿)으로 구성되어 있습니다. [소스
코드](https://github.com/tuist/tuist)에서 직접 Tuist를 빌드할 수도 있지만, **정상적인 설치를 위해 다음 중 한
가지 방법으로 설치하는 것을 권장합니다.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

::: info Mise란?
<!-- -->
Mise는 서로 다른 환경에서 도구의 버전을 동일하게 유지해야 하는 팀이나 조직에서 사용할 수 있는
[Homebrew](https://brew.sh)의 대안입니다.
<!-- -->
:::

다음 명령어를 통해 Tuist를 설치할 수 있습니다:

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

Homebrew처럼 도구의 단일 버전을 전역으로 설치하고 활성화하는 방식과 다르게 **Mise는 버전을 활성화해야 하며** 이것은 전역 또는
프로젝트 범위로 설정할 수 있습니다. 이 작업은 `mise use`를 통해 설정할 수 있습니다:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

[Homebrew](https://brew.sh)와 [Formula](https://github.com/tuist/homebrew-tuist)를
사용해 Tuist를 설치할 수 있습니다:

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: tip 바이너리의 출처 검증
<!-- -->
다음 명령어를 통해 설치된 바이너리가 Tuist에서 빌드된 것인지 확인할 수 있으며, 이것은 인증서의 팀이 `U6LC622NKF`인지
확인합니다:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
<!-- -->
:::
