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

::: warning REQUIREMENTS
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 계정 및 프로젝트</LocalizedLink>
- Xcode 26.0 이상
<!-- -->
:::

아직 Tuist 계정과 프로젝트가 없는 경우, 실행하여 만들 수 있습니다:

```bash
tuist init
```

`fullHandle` 을 참조하는 `Tuist.swift` 파일이 있으면 이를 실행하여 프로젝트의 캐싱을 설정할 수 있습니다:

```bash
tuist setup cache
```

이 명령은 시작 시 로컬 캐시 서비스를 실행하여 Swift [빌드
시스템](https://github.com/swiftlang/swift-build)이 컴파일 아티팩트를 공유하는 데 사용하는
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)을
생성합니다. 이 명령은 로컬 환경과 CI 환경 모두에서 한 번씩 실행해야 합니다.

CI에서 캐시를 설정하려면
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">인증</LocalizedLink>
상태인지 확인하세요.

### Xcode 빌드 설정 구성 {#configure-xcode-build-settings}

Xcode 프로젝트에 다음 빌드 설정을 추가합니다:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

`컴파일 캐시 원격 서비스 경로` 및 `컴파일 캐시 활성화 플러그인` 은 Xcode의 빌드 설정 UI에 직접 노출되지 않으므로 **사용자 정의
빌드 설정** 으로 추가해야 합니다:

::: info SOCKET PATH
<!-- -->
소켓 경로는 `tuist 설정 캐시` 를 실행할 때 표시됩니다. 프로젝트의 전체 핸들을 기반으로 하며 슬래시가 밑줄로 대체됩니다.
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

::: info GENERATED PROJECTS
<!-- -->
Tuist에서 프로젝트를 생성한 경우 수동으로 설정을 지정할 필요가 없습니다.

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

### 지속적 통합 {#continuous-integration}

CI 환경에서 캐싱을 활성화하려면 로컬 환경과 동일한 명령을 실행해야 합니다: `tuist setup cache`.

또한 `TUIST_TOKEN` 환경 변수가 설정되어 있는지 확인해야 합니다. 환경 변수는
<LocalizedLink href="/guides/server/authentication#as-a-project">here</LocalizedLink>
문서를 참조하여 생성할 수 있습니다. ` TUIST_TOKEN` 환경 변수 _는 빌드 단계에 반드시_ 존재해야 하지만 전체 CI 워크플로에
설정하는 것이 좋습니다.

그러면 GitHub 액션의 워크플로 예시는 다음과 같습니다:
```yaml
name: Build

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Set up Tuist Cache
        run: tuist setup cache
      - # Your build steps
```
