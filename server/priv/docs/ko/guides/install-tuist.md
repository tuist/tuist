---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Install the Tuist command-line interface on macOS or Linux with mise or Homebrew, and pin a version for teams and continuous integration."
}
---
# Tuist 설치 {#install-tuist}

Tuist 명령줄 인터페이스는 **macOS** 및 **Linux** 에서 실행되며 Xcode, 생성된 프로젝트, Gradle 및 Bazel 프로젝트를 Tuist의 캐시, 인사이트 및 러너 인프라에 연결합니다. Tuist를 [소스](https://github.com/tuist/tuist)에서 빌드할 수 있지만, 유효하고 검증 가능한 설치를 보장하기 위해 아래 설치 방법 중 하나를 사용하는 것을 권장합니다.

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> \[\!NOTE\]
> Mise가 설치되어 있지 않다면, 다음을 참고하세요. [시작하기 가이드](https://mise.jdx.dev/getting-started.html) 첫째. Mise는 다음에 대한 권장 대안입니다. [Homebrew](https://brew.sh) 여러분이 팀이나 조직으로서 다양한 환경에서 도구의 결정적 버전을 보장해야 하는 경우.

Homebrew와 같은 도구는 전역적으로 단일 버전의 도구를 설치하고 활성화하는 반면, **Mise는 버전을 고정합니다** 전역적으로 또는 프로젝트 범위로 설정할 수 있습니다. 실행 `mise use` Tuist를 설치하고 활성화하는 방법:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

Tuist 버전이 이미 고정된 프로젝트를 클론한 경우 `mise.toml`실행 `mise install` 설치하려면

> \[\!TIP\]
> `tuist@latest` 최신 **안정** 버전으로 해결됩니다. Tuist는 프리릴리스 카나리와 릴리스 후보 빌드도 배포합니다. 이러한 버전은 옵트인 전용이며, `latest`에 의해 자동으로 해결되지 않습니다. 신뢰할 수 있는 안정적인 버전을 고정하는 방법과 프리릴리스를 옵트인하는 방법은 \<.localized\_link href="/cli/release-channels"\>릴리스 채널\</.localized\_link\>을 참조하세요.

<details>
<summary>Linux support</summary>

Linux에서는 Tuist를 Mise를 통해서만 사용할 수 있습니다. Xcode에 의존하는 명령어(예: `tuist generate`)는 Linux에서 사용할 수 없지만, 플랫폼 독립적인 명령어인 `tuist inspect bundle` 는 예상대로 작동합니다.

</details>

### <a href="https://brew.sh">Homebrew</a> (macOS 전용) {#recommended-homebrew}

Homebrew와 Tuist 포뮬러를 사용하여 Tuist를 설치할 수 있습니다. [Homebrew](https://brew.sh) 그리고 [Tuist 포뮬러](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> \[\!TIP\]
> **바이너리의 진위 확인**
> 
> 다음 명령어를 실행하여 설치된 바이너리가 저희에 의해 빌드되었는지 확인할 수 있습니다. 이 명령어는 인증서의 팀이 다음인지 확인합니다. `U6LC622NKF`:
> 
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP 프록시 {#http-proxy}

네트워크에서 아웃바운드 트래픽을 HTTP 프록시를 통해 라우팅하는 경우 \<.localized\_link href="/guides/integrations/http-proxy"\>HTTP 프록시 가이드\</.localized\_link\>를 참조하세요.