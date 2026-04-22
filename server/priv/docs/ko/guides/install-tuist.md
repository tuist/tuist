---
{
  "title": "Tuist 설치",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "사용 중인 환경에 Tuist를 설치하는 방법을 알아보세요."
}
---
# Tuist 설치 {#install-tuist}

Tuist는 **macOS**와 **Linux**에서 실행됩니다. [소스 코드](https://github.com/tuist/tuist)에서 직접 Tuist를 빌드할 수도 있지만, **정상적으로 설치하려면 아래 설치 방법 중 하나를 사용하는 것을 권장합니다.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> [!NOTE]
> 아직 Mise를 설치하지 않았다면 먼저 [시작 가이드](https://mise.jdx.dev/getting-started.html)를 참고하세요. Mise는 여러 환경에서 도구 버전을 일관되게 유지해야 하는 팀이나 조직에 [Homebrew](https://brew.sh)의 권장 대안입니다.


Homebrew처럼 도구 한 버전만 전역으로 설치하고 활성화하는 방식과 달리 **Mise는 버전을 전역 또는 프로젝트 범위로 고정(pin)** 할 수 있습니다. Tuist를 설치하고 활성화하려면 `mise use`를 실행하세요:

```bash
mise use tuist@x.y.z          # 현재 프로젝트에 tuist-x.y.z를 설치하고 고정
mise use tuist@latest         # 현재 프로젝트에 최신 tuist를 설치하고 고정
mise use -g tuist@x.y.z       # tuist-x.y.z를 전역 기본값으로 설치하고 고정
mise use -g tuist@system      # 시스템에 설치된 tuist를 전역 기본값으로 사용
```

이미 `mise.toml`에 Tuist 버전이 고정된 프로젝트를 클론했다면 `mise install`을 실행해 해당 버전을 설치하세요.

<details>
<summary>Linux 지원</summary>

Linux에서는 Tuist를 Mise를 통해서만 사용할 수 있습니다. `tuist generate`처럼 Xcode에 의존하는 명령은 Linux에서 사용할 수 없지만, `tuist inspect bundle`처럼 플랫폼에 독립적인 명령은 정상적으로 동작합니다.

</details>


### <a href="https://brew.sh">Homebrew</a> (macOS 전용) {#recommended-homebrew}

[Homebrew](https://brew.sh)와 [Tuist formula](https://github.com/tuist/homebrew-tuist)를 사용해 Tuist를 설치할 수 있습니다:

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **바이너리 진위 확인**
>
> 아래 명령을 실행하면 인증서의 팀 ID가 `U6LC622NKF`인지 확인하여, 설치된 바이너리가 Tuist에서 빌드한 것인지 검증할 수 있습니다:
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP 프록시 {#http-proxy}

네트워크에서 외부 트래픽을 HTTP 프록시를 통해 라우팅한다면 <.localized_link href="/guides/integrations/http-proxy">HTTP 프록시 가이드</.localized_link>를 참고하세요.
