---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Xcode 캐시 {#xcode-cache}

Tuist는 빌드 시스템의 캐싱 기능을 활용하여 팀이 컴파일 아티팩트를 공유할 수 있도록 Xcode 컴파일 캐시를 지원합니다.

## 설정 {#setup}

::: warning 요구 사항
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 계정 및
  프로젝트</LocalizedLink>
- Xcode 26.0 이상
<!-- -->
:::

아직 Tuist 계정과 프로젝트가 없는 경우, 다음을 실행하여 만들 수 있습니다:

```bash
tuist init
```

`fullHandle` 을 참조하는 `Tuist.swift` 파일이 있으면 다음을 실행하여 프로젝트의 캐싱을 설정할 수 있습니다:

```bash
tuist setup cache
```

이 명령은 시작 시 로컬 캐시 서비스를 실행하여 Swift [빌드
시스템](https://github.com/swiftlang/swift-build)이 컴파일 아티팩트를 공유하는 데 사용하는
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)을
생성합니다. 이 명령은 로컬 환경과 CI 환경 모두에서 한 번은 실행되어야 합니다.

CI에서 캐시를 설정하려면
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">인증된</LocalizedLink>
상태인지 확인하세요.

### Xcode 빌드 설정 구성 {#configure-xcode-build-settings}

Xcode 프로젝트에 다음 빌드 설정을 추가하세요:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

`COMPILATION_CACHE_REMOTE_SERVICE_PATH` 및 `COMPILATION_CACHE_ENABLE_PLUGIN` 은
Xcode의 Build Settings UI에 직접 노출되지 않으므로 **사용자 정의 빌드 설정**으로 추가해야 합니다:

::: info SOCKET PATH
<!-- -->
소켓 경로는 `tuist setup cache` 를 실행할 때 표시됩니다. 프로젝트의 fullHandle을 기반으로 하며 '/'가 밑줄로
대체됩니다.
<!-- -->
:::

`xcodebuild` 을 실행할 때 다음과 같은 플래그를 추가하여 이러한 설정을 지정할 수도 있습니다:

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info 동적 생성된 프로젝트
<!-- -->
Tuist로 프로젝트를 생성한 경우 수동으로 설정을 지정할 필요가 없습니다.

이 경우 `Tuist.swift` 파일에 `enableCaching: true` 을 추가하기만 하면 됩니다:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```
<!-- -->
:::

### 지속적 통합 #{continuous-integration}

CI 환경에서 캐싱을 활성화하려면, 로컬 환경과 동일한 명령을 실행해야 합니다: `tuist setup cache`.

인증의 경우 <LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC
인증</LocalizedLink>(지원되는 CI 제공자에게 권장됨) 또는 `TUIST_TOKEN` 환경 변수를 통해
<LocalizedLink href="/guides/server/authentication#account-tokens">계정
Token</LocalizedLink>을 사용할 수 있습니다.

OIDC 인증을 사용하는 GitHub Actions Workflow 예시입니다:
```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
      - # Your build steps
```

토큰 기반 인증 및 Xcode Cloud, CircleCI, Bitrise, Codemagic과 같은 기타 CI 플랫폼을 포함한, 더 많은
예제는 <LocalizedLink href="/guides/integrations/continuous-integration">지속 통합
가이드</LocalizedLink>를 참조하세요.
