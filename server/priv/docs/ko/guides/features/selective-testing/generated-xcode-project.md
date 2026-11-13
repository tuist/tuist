---
{
  "title": "생성된 Xcode 프로젝트",
  "titleTemplate": ":title · 선택적 테스팅 · 기능 · 가이드 · Tuist",
  "description": "Tuist 선택적 테스팅을 사용해 최신 변경 사항의 영향을 받은 Xcode 및 생성된 프로젝트 테스트만 실행하여, 지속적 통합에서 몇 초 만에 피드백을 받아보세요."
}
---
# 생성된 Xcode 프로젝트 {#generated-xcode-project}

프로젝트가 커질수록 모든 푸시마다 모든 테스트를 실행하는 방식은 확장하기 어려워집니다. Tuist의 선택적 테스팅은 Tuist의 <.localized_link href="/guides/features/projects/hashing">해싱 알고리즘</.localized_link>을 기반으로, 마지막 성공적인 테스트 실행 이후 타겟이 변경된 테스트만 실행합니다.

<.localized_link href="/guides/features/projects">생성된 프로젝트</.localized_link>로 선택적으로 테스트를 실행하려면 `tuist test` 명령어를 사용하세요. 이 명령어는 <.localized_link href="/guides/features/cache/module-cache">모듈 캐시</.localized_link>와 동일한 방식으로 프로젝트를 <.localized_link href="/guides/features/projects/hashing">해싱</.localized_link>하며, 성공 시 해시를 저장하여 향후 실행에서 무엇이 변경되었는지 확인합니다. 이후 실행에서는 `tuist test`가 해시를 투명하게 사용하여 테스트를 필터링하고 마지막 성공적인 테스트 실행 이후 변경된 테스트만 실행합니다.

`tuist test`는 <.localized_link href="/guides/features/cache/module-cache">모듈 캐시</.localized_link>와 직접 통합되어 로컬 또는 원격 스토리지의 바이너리를 최대한 활용하여 테스트 스위트 실행 시 빌드 시간을 단축합니다. 선택적 테스팅과 모듈 캐싱을 결합하면 CI에서 테스트 실행에 소요되는 시간을 크게 줄일 수 있습니다.

테스트 실행이 시뮬레이터 타겟만 대상으로 한다면, `--destination simulator`를 전달하여 `tuist test`가 캐시된 바이너리의 시뮬레이터 슬라이스만 사용하고 다운로드하도록 하세요. <.localized_link href="/guides/features/cache/module-cache#destination-selection">대상 선택</.localized_link>을 참조하세요. 선택적 테스팅 해시는 모든 `--destination` 값에 대해 동일합니다.

## 빌드 및 테스트 작업 분리 {#separate-build-and-test-jobs}

선택적 테스팅은 별도의 빌드 및 테스트 작업을 지원합니다. 빌드 작업에서 `tuist test --build-only`를 실행하여 Tuist가 빌드가 생성하는 제품과 함께 `selective-testing-graph.json` 파일을 저장할 수 있도록 하세요. 해당 그래프에는 선택적 테스팅에 필요한 해시가 포함되어 있으므로, 테스트 작업에서 어떤 타겟을 실행할지 결정하기 위해 프로젝트를 다시 생성하거나 Swift Package 의존성을 해결할 필요가 없습니다.

Tuist는 `--build-only` 동안 그래프를 두 곳에 작성합니다:

- `-testProductsPath`를 전달할 때 `.xctestproducts` 번들 내부에 작성됩니다.
- 파생 데이터의 `Build/Products/` 디렉터리 아래에 있는 모든 `.xctestrun` 파일 옆에 작성됩니다.

두 출력 중 하나를 빌드된 제품과 함께 캐시하고, 테스트 작업에서 `--without-building`에 동일한 경로를 전달하세요. 두 형식 모두 작동합니다:

```sh
# Build job — writes an .xctestproducts bundle with the graph inside it.
tuist test MyScheme \
  --build-only \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'

# Test job — restores the same bundle.
tuist test MyScheme \
  --without-building \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'
```

```sh
# Build job — writes the graph as a sibling of each xctestrun in derived data.
tuist test MyScheme \
  --build-only \
  -- \
  -derivedDataPath artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  -- \
  -derivedDataPath artifacts/derived-data \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

Tuist가 입력 рядом에서 해당 그래프를 찾지 못하면(예: 빌드 작업이 `tuist test --build-only` 대신 일반 `xcodebuild build-for-testing`를 사용한 경우), 영향을 받은 타겟을 여전히 계산할 수 있도록 프로젝트를 다시 생성하는 방식으로 대체합니다. 이 대체 방식은 테스트 작업에서 Swift Package 의존성이 해결되어야 하므로, 먼저 `tuist install`를 실행하거나 작업 간에 `Tuist/.build`를 캐시하세요.

그래프는 빌드 당시의 소스 트리를 반영합니다. 테스트 작업을 빌드 작업과 동일한 커밋에서 실행하세요. 두 작업 사이에 소스가 달라지면 해시가 소스와 일치하지 않게 되어 선택적 테스팅이 새로운 소스에서는 실제로 실패할 테스트를 건너뛸 수 있습니다.

### 어떤 플래그를 사용해야 할까요? {#which-flag-should-i-use}

`.xctestrun`와 `.xctestproducts`는 두 가지 다른 Xcode 출력 형식으로, 이식성과 파이프라인 편의성 간의 트레이드오프가 있습니다:

- **`-testProductsPath` (`.xctestproducts`) — 새로운 파이프라인에 권장됩니다.** 자체 포함 디렉터리입니다: 빌드된 `.xctest` 바이너리와 해당 `.xctestrun` 파일이 번들 루트에 상대적인 경로로 내부에 저장되므로, 어디로 이동하더라도 유효하게 유지됩니다.
- **`-xctestrun` (원본 `.xctestrun`) — 이미 파생 데이터를 중심으로 구축된 파이프라인이 있는 경우 사용하세요.** `xcodebuild build-for-testing`는 기본적으로 `<derivedData>/Build/Products/` 최상단에 `.xctestrun`를 작성하고 해당 트리 내 다른 위치에 있는 테스트 번들을 가리킵니다. 다른 작업에서 재사용하려면 `Build/Products/`의 경로를 그대로 유지해야 합니다.

새롭게 시작한다면 `-testProductsPath`를 선호하세요. 이미 파생 데이터를 캐시하는 기존 파이프라인에 Tuist를 연결하는 경우, 빌드 작업이 `tuist test --build-only`를 통해 실행되는 한 `-xctestrun`도 동일한 빠른 경로를 제공합니다.

두 입력 모드 모두 `-workspace`/`-project`/`-scheme`와 상호 배타적이므로, 전달 인수에 `-xctestrun` 또는 `-testProductsPath`가 포함되면 Tuist는 해당 플래그를 건너뛰고 선택된 타겟을 `-only-testing`를 통해 전달합니다.

> [!WARNING]
> **모듈 대 파일 수준 세분화**
>
> 테스트와 소스 간의 코드 내 의존성을 감지할 수 없기 때문에, 기본 선택적 테스팅의 최대 세분화 수준은 타겟 수준입니다. [커버리지 전략](#coverage-based-test-selection)은 이를 단일 XCTest 테스트 수준으로 좁힙니다. 따라서 선택적 테스팅의 이점을 극대화하기 위해 타겟을 작고 집중적으로 유지하는 것을 권장합니다.


## 커버리지 기반 테스트 선택 {#coverage-based-test-selection}

> [!NOTE]
> **얼리 액세스**
>
> 커버리지 기반 테스트 선택은 얼리 액세스 단계입니다. 계정에서 활성화하려면 저희에게 연락하세요. 활성화되기 전까지 이 전략은 기본 선택적 테스팅처럼 동작합니다.

기본적으로 선택적 테스팅은 해시가 이미 통과된 전체 테스트 타겟을 건너뜁니다. `.coverage()` 전략은 여기서 더 나아가며, 남은 테스트 타겟 중에서 이전 실행의 코드 커버리지가 변경 사항이触及한 파일을 하나도 포함하지 않는 XCTest 및 XCUITest 테스트도 건너뜁니다. `Tuist.swift`에서 이를 활성화하세요:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage())
    ),
    project: .tuist()
)
```

이 전략에는 다음이 필요합니다:

- **커버리지 업로드.** Tuist는 이전 실행에서 업로드된 커버리지를 기준으로 테스트를 선택하므로, `tuist test`는 `upload: false`로 설정된 `.coverage()` 매니페스트를 로드하지 못해 실패합니다.
- 테스트 타겟이 링크한 **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 이상**. 이는 각 테스트가 실행하는 파일을 기록하고 Tuist가 선택하지 않은 테스트를 건너뜁니다. 이것이 없는 타겟은 기본값과 마찬가지로 전체가 건너뛰어집니다.
- **선택 없이 기본 브랜치에서 테스트 실행.** 해당 브랜치와 테스트를 건너뛰지 않아야 하는 다른 모든 브랜치에서 `tuist test --no-selective-testing`를 실행하세요. 이러한 실행은 모든 테스트를 실행하며 이후 실행이 비교하는 기준선이 됩니다.

전략이 활성화되면 `tuist test`는 해시가 이미 통과된 타겟을 건너뛰고, 나머지 타겟 중 변경 사항이 영향을 미칠 수 있는 테스트를 Tuist에 문의합니다. 영향을 받는 테스트가 없는 타겟은 빌드되지 않습니다. 새로운 테스트, 이전에 실패한 테스트, 변경된 테스트 파일의 테스트, 기록된 커버리지가 없는 테스트는 항상 실행됩니다. Swift Testing 테스트는 해당 타겟이 실행될 때마다 실행됩니다.

때로는 커버리지가 적용되지 않으며, 출력 결과에 그 이유가 표시됩니다: 해시가 통과되지 않은 타겟의 모든 테스트는 기본 선택적 테스팅과 마찬가지로 실행됩니다. 이는 동일한 플랫폼에 최근 기준선이 없을 때, 변경 사항이 5,000개 이상의 파일에 영향을 줄 때, 또는 `Package.resolved`, `Project.swift`, `.xcconfig`와 같이 모든 테스트에 영향을 줄 수 있는 파일이 변경되었을 때 발생합니다. 모든 테스트를 실행하려면 `--no-selective-testing`를 전달하세요.

> [!NOTE]
> **테스트 커버리지**
>
> 단일 실행의 보고서를 읽는 커버리지 도구(Xcode 포함)는 전체 테스트 스위트가 실행되었다고 가정하므로, 선택적 실행의 보고서에서는 건너뛴 테스트가 누락됩니다. 대신 Tuist의 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">코드 커버리지</.localized_link>는 각 실행에서 기록하는 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">타겟 수준 커버리지</.localized_link>를 사용하여 건너뛴 테스트 타겟의 커버리지를 이전 실행에서 이어받아 적용합니다.


## 풀/머지 요청 댓글 {#pullmerge-request-comments}

> [!WARNING]
> **Git 포지 통합 필요**
>
> 자동 풀/머지 요청 댓글을 받으려면 <.localized_link href="/guides/server/accounts-and-projects">Tuist 프로젝트</.localized_link>를 Git 포지와 통합하세요: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> 또는 <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


Tuist 프로젝트가 [GitHub](https://github.com)와 같은 Git 플랫폼과 연결되고 CI 워크플로의 일부로 `tuist test` 사용을 시작하면, Tuist는 풀/머지 요청에 직접 댓글을 게시하며 어떤 테스트가 실행되었고 어떤 테스트가 건너뛰어졌는지 표시합니다: ![Tuist 미리보기 링크가 포함된 GitHub 앱 댓글](/images/guides/features/selective-testing/github-app-comment.png)


## 대시보드에서 미스 조사하기 {#investigating-misses-on-the-dashboard}

이전에 캐시된 테스트 타겟이 미스로 표시되면, 테스트 실행 페이지의 **선택적 테스팅** 탭에서 해시를 생성한 입력을 자세히 살펴볼 수 있습니다. 행을 확장하면 소스, 의존성, 환경 변수, 프로젝트 및 타겟 설정, Info.plist, 권한, 헤더 등 구성 요소별 서브해시가 표시되어 실행 간에 변경된 입력을 정확히 찾아낼 수 있습니다.

선택적 테스팅 카드 상단의 **JSON으로 복사** 버튼을 사용하여 모든 선택적 테스팅 타겟과 해당 해시 및 서브해시를 내보내세요. 두 실행 간의 JSON을 비교하는 것이 테스트 타겟의 해시가 변경되었을 때 어떤 입력이 바뀌었는지 확인하는 가장 빠른 방법입니다.
