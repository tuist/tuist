---
{
  "title": "모범 사례",
  "titleTemplate": ":title · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Tuist가 생성한 프로젝트를 작업할 때의 모범 사례를 알아보세요."
}
---
# 모범 사례 {#best-practices}

다양한 팀과 프로젝트에서 작업하며 Tuist와 Xcode 프로젝트를 다룰 때 따르기를 권장하는 모범 사례들을 정리했습니다. 이러한 관행은 필수 사항이 아니지만, 유지보수와 확장이 용이하도록 프로젝트를 구조화하는 데 도움이 됩니다.

## Xcode {#xcode}

### 비권장 패턴 {#discouraged-patterns}

#### 원격 환경을 모델링하기 위한 구성 {#configurations-to-model-remote-environments}

많은 조직에서는 다양한 원격 환경을 모델링하기 위해 빌드 구성을 사용합니다(예: `Debug-Production` 또는 `Release-Canary`). 하지만 이 접근 방식에는 몇 가지 단점이 있습니다:

- **일관성 부족:** 그래프 전체에 구성 불일치가 있으면 빌드 시스템이 일부 타겟에 대해 잘못된 구성을 사용할 수 있습니다.
- **복잡성:** 프로젝트는 이해하고 유지보수하기 어려운 로컬 구성과 원격 환경의 긴 목록으로 끝날 수 있습니다.

빌드 구성은 서로 다른 빌드 설정을 표현하기 위해 설계되었으며, 프로젝트는 일반적으로 `Debug`와 `Release`만 필요합니다. 다양한 환경을 모델링해야 하는 필요성은 다음과 같은 방식으로 해결할 수 있습니다:

- **Debug 빌드에서:** 개발 중에 접근해야 하는 모든 구성(예: 엔드포인트)을 앱에 포함하고 런타임에 전환할 수 있습니다. 전환은 스키마 실행 환경 변수를 사용하거나 앱 내 UI를 통해 수행할 수 있습니다.
- **Release 빌드에서:** 릴리스 시에는 릴리스 빌드가 바인딩된 구성만 포함하고, 컴파일러 지시문을 사용하여 구성 전환을 위한 런타임 로직을 포함하지 않을 수 있습니다.

> [!NOTE]
> **비표준 구성**
>
> Tuist는 비표준 구성을 지원하며 일반 Xcode 프로젝트보다 관리하기 쉽지만, 의존성 그래프 전체에서 구성이 일관되지 않으면 경고가 표시됩니다. 이는 빌드 신뢰성을 보장하고 구성 관련 문제를 방지하는 데 도움이 됩니다.


## 생성된 프로젝트

### 빌드 가능 폴더

Tuist 4.62.0은 병합 충돌을 줄이기 위해 Xcode 16에서 도입된 기능인 **빌드 가능 폴더**(Xcode의 동기화된 그룹) 지원을 추가했습니다.

Tuist의 와일드카드 패턴(예: `Sources/**/*.swift`)은 생성된 프로젝트에서 이미 병합 충돌을 제거하지만, 빌드 가능 폴더는 추가적인 이점을 제공합니다:

- **자동 동기화**: 프로젝트 구조가 파일 시스템과 동기화 상태를 유지하므로 파일을 추가하거나 제거할 때 재생성이 필요하지 않습니다.
- **AI 친화적 워크플로**: 코딩 어시스턴트와 에이전트가 프로젝트 재생성을 트리거하지 않고 코드베이스를 수정할 수 있습니다.
- **간소화된 구성**: 명시적인 파일 목록을 관리하는 대신 폴더 경로를 정의합니다.

보다 간소화된 개발 경험을 위해 전통적인 `Target.sources` 및 `Target.resources` 속성 대신 빌드 가능 폴더를 채택하기를 권장합니다.

::: code-group

```swift [With buildable folders]
let target = Target(
  name: "App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target = Target(
  name: "App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
<!-- -->
:::

### 의존성

#### CI에서 버전 고정 강제

CI에서 Swift Package Manager 의존성을 설치할 때 결정론적 빌드를 보장하기 위해 `--force-resolved-versions` 플래그 사용을 권장합니다:

```bash
tuist install --force-resolved-versions
```

이 플래그는 `Package.resolved`에 고정된 정확한 버전을 사용하여 의존성이 해결되도록 보장하며, 의존성 해결의 비결정성으로 인한 문제를 제거합니다. 재현 가능한 빌드가 중요한 CI 환경에서 특히 중요합니다.

#### GitHub Actions에서의 캐시된 의존성 설치 {#dependency-cache-volumes}

생성된 프로젝트의 경우 [tuist/install](https://github.com/tuist/install)을 사용하여 `Package.resolved`에 고정된 의존성을 설치하고 실행 간에 캐시하세요. Tuist Runner에서는 <.localized_link href="/guides/features/runners/cache-volumes">캐시 볼륨</.localized_link>을 자동으로 사용하고, 다른 러너에서는 GitHub의 캐시를 사용합니다.

```yaml
name: Generate project
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  generate:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v4
      - uses: tuist/install@v1
      - run: tuist generate --no-open
```

하위 디렉터리에 있는 프로젝트의 경우 체크아웃 상대 경로를 전달하세요:

```yaml
- uses: tuist/install@v1
  with:
    path: apps/ios
```

추가 옵션은 [액션 참조](https://github.com/tuist/install#usage)를 확인하세요.

### 에이전트 코딩과 작업 트리 {#agentic-coding-and-worktrees}

코딩 에이전트와 인간 기여자가 점점 더 병렬로 작업합니다: 개발자는 검토 중인 기능을 위해 작업 트리를 열어두고, 하나 이상의 에이전트는 형제 작업 트리에서 자체 브랜치로 반복 작업을 수행합니다. 몇 가지 프로젝트 선택으로 이를 훨씬 원활하게 만들 수 있습니다.

#### 에이전트 주도 편집에 빌드 가능 폴더 사용 {#worktrees-buildable-folders}

에이전트가 파일을 추가하거나 제거할 때 `Project.swift`의 파일 목록에 의존하는 모든 항목은 프로젝트가 다시 빌드되기 전에 `tuist generate`가 필요합니다. [빌드 가능 폴더](#buildable-folders)는 해당 책임을 Xcode의 동기화된 그룹으로 이관하므로 파일 트리 편집이 더 이상 재생성을 트리거하지 않습니다.

이를 `generated-projects` <.localized_link href="/guides/features/agentic-coding/skills">스킬</.localized_link>과 함께 사용하면 에이전트에게 Tuist 프로젝트의 일상 워크플로를 가르칠 수 있습니다.

#### 작업 트리별 캐시 격리 금지 {#worktrees-shared-cache}

Tuist는 <.localized_link href="/cli/directories">XDG 기본 디렉터리 사양</.localized_link>을 따르므로 기본적으로 동일한 머신의 모든 작업 트리가 `~/.cache/tuist`와 `~/.local/state/tuist`를 공유합니다. 이는 원하는 동작입니다: 한 작업 트리에서 컴파일된 헬퍼, 다른 작업 트리에서 다운로드된 플러그인, 세 번째 작업 트리에서 가져온 모듈 캐시 바이너리는 모두 재사용 가능합니다.

작업 트리 간의 동시 `tuist` 호출은 병렬로 실행해도 안전합니다. 특별히 격리가 필요한 경우가 아니면 `TUIST_XDG_CACHE_HOME`를 작업 트리 로컬 경로로 지정하지 마세요. 그렇게 하면 모든 작업 트리가 헬퍼, 플러그인 및 바이너리를 다시 워밍업해야 합니다.

#### 작업 트리별 SwiftPM 임시 공간 유지 {#worktrees-swiftpm-scratch}

Swift Package Manager에는 자체 경로 제어가 있습니다. `--scratch-path`는 변경 가능한 작업 상태이며 기본값은 `.build`이고, `--cache-path`는 공유 캐시 디렉터리입니다. 여러 작업 트리가 활성화되어 있을 때 이 두 경로는 동일하게 취급해서는 안 됩니다.

Tuist의 기본 `tuist install` 동작은 이미 SwiftPM 임시 공간을 패키지 디렉터리 아래에 유지하므로 각 작업 트리가 자체 `.build`를 갖게 됩니다. 이러한 격리를 유지하세요. 단일 공유 SwiftPM 임시 공간 디렉터리는 관련 없는 브랜치의 체크아웃, 빌드 중간 파일, 플러그인, 매크로 및 잠금 파일을 혼합할 수 있습니다.

SwiftPM 인수를 `tuist install -- ...`를 통해 또는 `Tuist.swift`의 `installOptions`를 통해 전달하는 경우, 의존성 가져오기를 더 빠르게 하려면 `--cache-path`를 공유하지만 `--scratch-path`는 설정하지 않거나 작업 트리 로컬 디렉터리를 지정하세요:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        installOptions: .options(
            passthroughSwiftPackageManagerArguments: [
                "--cache-path",
                "/Users/Shared/swiftpm/cache/xcode-16-macos",
            ]
        )
    )
)
```

캐시 경로가 Xcode, Swift 툴체인 또는 플랫폼에 따라 달라져야 하는 경우 래퍼나 CI 환경 변수를 사용하세요. 공유된 `--scratch-path`를 리포지토리에 커밋하지 마세요.

단 하나의 작업 트리에서만 의존성 상태가 손상된 것으로 보이면 해당 작업 트리의 `.build` 디렉터리를 삭제하고 `tuist install`를 다시 실행하세요. 작업 트리 간에 공유 SwiftPM 캐시 자체가 의심스러운 경우 의존성을 다시 설치하기 전에 `swift package purge-cache`를 사용하세요.

#### 모듈 캐시 활용 {#worktrees-module-cache}

<.localized_link href="/guides/features/cache/module-cache">모듈 캐시</.localized_link>는 병렬 작업 트리를 관리 가능하게 만듭니다. Tuist는 각 타겟에 대해 결정론적인 <.localized_link href="/guides/features/projects/hashing">해시</.localized_link>를 계산하므로, 대부분의 히스토리를 공유하는 브랜치를 가리키는 두 작업 트리는 동일한 바이너리를 히트합니다. CI에서 `main`에 대한 모든 커밋마다 `tuist cache`를 실행하세요. 로컬에서는 각 작업 트리의 `tuist generate`가 캐시에서 가능한 모든 것을 가져오고 브랜치가 실제로 변경한 부분만 빌드합니다.

캐시 히트를 예상했는데 작업 트리가 소스 빌드로 대체되는 경우 <.localized_link href="/guides/features/projects/hashing#debugging">해싱 디버깅 단계</.localized_link>를 따르세요. 비결정론적 해시(일반적으로 프로젝트의 절대 경로로 인해 발생)가 가장 흔한 원인이며, 두 작업 트리를 비교할 때 뚜렷하게 나타납니다.

#### 레지스트리로 Swift Package 해결 속도 향상 {#worktrees-registry}

각 작업 트리는 Swift 패키지를 독립적으로 해결합니다. 큰 의존성 그래프를 가진 프로젝트에서는 이 시간이 빠르게 누적됩니다. <.localized_link href="/guides/features/package-registries/swift">Tuist 레지스트리</.localized_link>로 전환하면 git 히스토리를 다시 복제하지 않아도 되며 해결 시간을 분에서 초로 단축합니다.

#### 에이전트에 프로젝트 인사이트 제공 {#worktrees-mcp}

빌드와 테스트가 많은 작업 트리에서 실행되면 에이전트가 수행할 수 있는 가장 유용한 작업은 *어떤* 실행이 회귀되었는지, 어떤 테스트가 불안정한지, 또는 번들 크기가 어떻게 변경되었는지 추론하는 것입니다. Tuist는 해당 데이터를 <.localized_link href="/guides/features/agentic-coding/mcp">MCP 서버</.localized_link>와 <.localized_link href="/guides/features/agentic-coding/skills">Skills</.localized_link> 패키지를 통해 노출합니다. 워크플로당 하나를 선택하고 일관되게 사용하세요. 동일한 작업에 둘을 혼합하면 에이전트 동작이 일관되지 않게 되는 경향이 있습니다.
