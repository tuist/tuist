---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Install the Tuist command-line interface on macOS or Linux with mise or Homebrew, and pin a version for teams and continuous integration."
}
---
# Tuist 설치 {#install-tuist}

Tuist 명령줄 인터페이스는 **macOS** 및 **Linux**에서 실행되며, Xcode, 생성된 프로젝트, Gradle 및 Bazel 프로젝트를 Tuist의 캐시, 인사이트 및 러너 인프라에 연결합니다. Tuist를 [소스](https://github.com/tuist/tuist)에서 빌드할 수 있지만, 유효하고 검증 가능한 설치를 보장하기 위해 아래 설치 방법 중 하나를 권장합니다.

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> \[\!NOTE\]
> Mise가 설치되어 있지 않다면, 먼저 [시작하기 가이드](https://mise.jdx.dev/getting-started.html)를 따르세요. Mise는 다양한 환경에서 도구의 결정론적 버전을 보장해야 하는 팀이나 조직을 위해 [Homebrew](https://brew.sh)의 권장 대안입니다.

Homebrew와 같이 도구의 단일 버전을 전역적으로 설치하고 활성화하는 도구와 달리, **Mise는 버전 고정**을 전역적으로 또는 프로젝트 범위로 수행합니다. Tuist를 설치하고 활성화하려면 `mise use`를 실행하세요:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

이미 `mise.toml`에 Tuist 버전이 고정된 프로젝트를 클론한 경우, `mise install`을 실행하여 설치하세요.

> \[\!TIP\]
> `tuist@latest`는 최신 **안정** 릴리스로 해결됩니다. Tuist는 프리릴리스 카나리 및 릴리스 후보 빌드도 배포하지만, 이는 옵트인 방식이며 `latest`로 절대 해결되지 않습니다. 신뢰할 수 있는 안정 라인을 고정하는 방법과 프리릴리스에 옵트인하는 방법은 \<.localized\_link href="/cli/release-channels"\>릴리스 채널\</.localized\_link\>을 참조하세요.

<details>
<summary>Linux support</summary>

Linux에서는 Tuist가 Mise를 통해서만 제공됩니다. Xcode에 의존하는 명령(예: `tuist generate`)은 Linux에서 사용할 수 없지만, `tuist inspect bundle`과 같은 플랫폼 독립적인 명령은 예상대로 작동합니다.

</details>

### <a href="https://brew.sh">Homebrew</a> (macOS 전용) {#recommended-homebrew}

Tuist는 [Homebrew](https://brew.sh) 및 [우리의 포뮬러](https://github.com/tuist/homebrew-tuist)를 사용하여 설치할 수 있습니다:

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> \[\!TIP\]
> **바이너리의 진위성 검증**
> 
> 다음 명령을 실행하여 설치된 바이너리가 저희에 의해 빌드되었는지 확인할 수 있으며, 이 명령은 인증서의 팀이 `U6LC622NKF`인지 확인합니다:
> 
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP 프록시 {#http-proxy}

네트워크가 HTTP 프록시를 통해 아웃바운드 트래픽을 라우팅하는 경우, \<.localized\_link href="/guides/integrations/http-proxy"\>HTTP 프록시 가이드\</.localized\_link\>를 참조하세요.