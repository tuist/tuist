---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Install the Tuist command-line interface on macOS or Linux with mise or Homebrew, and pin a version for teams and continuous integration."
}
---
# Tuist 설치 {#install-tuist}

Tuist 명령줄 인터페이스는 **macOS** 및 **Linux**에서 실행되며 Xcode, 생성된 프로젝트, Gradle 및 Bazel 프로젝트를 Tuist의 캐시, 인사이트 및 러너 인프라에 연결합니다. [소스](https://github.com/tuist/tuist)에서 Tuist를 빌드할 수 있지만, 유효하고 검증 가능한 설치를 보장하기 위해 아래 설치 방법 중 하나를 권장합니다.

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> [!NOTE]
> Mise가 설치되어 있지 않다면 먼저 [시작 가이드](https://mise.jdx.dev/getting-started.html)를 따르세요. 다양한 환경에서 도구의 결정론적 버전을 보장해야 하는 팀이나 조직인 경우 [Homebrew](https://brew.sh) 대신 Mise를 사용하는 것이 권장됩니다.


전역적으로 단일 버전의 도구를 설치하고 활성화하는 Homebrew와 같은 도구와 달리, **Mise는 버전을 고정**하며 전역적으로 또는 프로젝트 범위로 지정할 수 있습니다. Tuist를 설치하고 활성화하려면 `mise use`를 실행하세요:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

이미 `mise.toml`에 Tuist 버전이 고정된 프로젝트를 클론한 경우, 이를 설치하려면 `mise install`를 실행하세요.

> [!TIP]
> `tuist@latest`은 최신 **안정** 릴리스로 해결됩니다. Tuist는 프리릴리스 카나리 및 릴리스 후보 빌드도 게시하지만, 이러한 버전은 명시적으로 선택해야 하며 `latest`로는 절대 해결되지 않습니다. 신뢰할 수 있는 안정 라인을 고정하는 방법과 프리릴리스에 참여하는 방법은 <.localized_link href="/cli/release-channels">릴리스 채널</.localized_link>을 참조하세요.

<details>
<summary>Linux 지원</summary>

Linux에서는 Tuist를 exclusively via Mise를 통해서만 사용할 수 있습니다. Xcode에 의존하는 명령(`tuist generate` 등)은 Linux에서 사용할 수 없지만, `tuist inspect bundle`와 같은 플랫폼 독립적인 명령은 예상대로 작동합니다.

</details>


### <a href="https://brew.sh">Homebrew</a> (macOS 전용) {#recommended-homebrew}

[Homebrew](https://brew.sh) 및 [우리의 포뮬러](https://github.com/tuist/homebrew-tuist)를 사용하여 Tuist를 설치할 수 있습니다:

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **바이너리의 진위성 검증**
>
> 다음 명령을 실행하여 설치된 바이너리가 우리가 빌드했는지 검증할 수 있으며, 이 명령은 인증서의 팀이 `U6LC622NKF`인지 확인합니다:
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP 프록시 {#http-proxy}

네트워크가 HTTP 프록시를 통해 아웃바운드 트래픽을 라우팅하는 경우, <.localized_link href="/guides/integrations/http-proxy">HTTP 프록시 가이드</.localized_link>를 참조하세요.
