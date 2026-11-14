---
{
  "title": "생성된 Xcode 프로젝트",
  "titleTemplate": ":title · 선택적 테스팅 · 기능 · 가이드 · Tuist",
  "description": "Tuist 선택적 테스팅으로 최신 변경 사항의 영향을 받은 Xcode 및 생성된 프로젝트 테스트만 실행하여, 지속적 통합에서 몇 초 만에 피드백을 받아보세요."
}
---
# 생성된 Xcode 프로젝트 {#generated-xcode-project}

프로젝트가 커질수록 모든 푸시마다 모든 테스트를 실행하는 방식은 확장하기 어려워집니다. Tuist의 선택적 테스팅은 Tuist의 <.localized_link href="/guides/features/projects/hashing">해싱 알고리즘</.localized_link>을 기반으로, 마지막 성공적인 테스트 실행 이후 대상이 변경된 테스트만 실행합니다.

<.localized_link href="/guides/features/projects">생성된 프로젝트</.localized_link>에서 선택적으로 테스트를 실행하려면 `tuist test` 명령어를 사용하세요. 이 명령어는 <.localized_link href="/guides/features/cache/module-cache">모듈 캐시</.localized_link>와 동일한 방식으로 프로젝트를 <.localized_link href="/guides/features/projects/hashing">해싱</.localized_link>하며, 성공 시 해시를 저장하여 향후 실행에서 무엇이 변경되었는지 판단합니다. 이후 실행에서는 `tuist test`가 해시를 투명하게 사용하여 테스트를 필터링하고, 마지막 성공적인 테스트 실행 이후 변경된 테스트만 실행합니다.

`tuist test`는 <.localized_link href="/guides/features/cache/module-cache">모듈 캐시</.localized_link>와 직접 통합되어 로컬 또는 원격 스토리지의 바이너리를 최대한 활용하여 테스트 스위트 실행 시 빌드 시간을 단축합니다. 선택적 테스팅과 모듈 캐싱을 조합하면 CI에서 테스트 실행에 소요되는 시간을 크게 줄일 수 있습니다.

테스트가 시뮬레이터 대상만 실행한다면, `--destination simulator`를 전달하여 `tuist test`가 캐시된 바이너리의 시뮬레이터 슬라이스만 사용하고 다운로드하도록 하세요. <.localized_link href="/guides/features/cache/module-cache#destination-selection">대상 선택</.localized_link>을 참조하세요. 선택적 테스팅 해시는 모든 `--destination` 값에 대해 동일합니다.

## 빌드 및 테스트 작업 분리 {#separate-build-and-test-jobs}

선택적 테스팅은 별도의 빌드 및 테스트 작업을 지원합니다. 빌드 작업에서 `tuist test --build-only`를 실행하면 Tuist가 빌드가 생성하는 제품과 함께 `selective-testing-graph.json` 파일을 저장할 수 있습니다. 이 그래프에는 선택적 테스팅에 필요한 해시가 포함되어 있으므로, 테스트 작업에서 어떤 대상을 실행할지 결정하기 위해 프로젝트를 다시 생성하거나 Swift Package 의존성을 해결할 필요가 없습니다.

Tuist는 `--build-only` 동안 그래프를 두 곳에 작성합니다:

- `-testProductsPath`를 전달할 때 `.xctestproducts` 번들 내부에 작성됩니다.
- 파생 데이터의 `Build/Products/` 디렉터리 아래에 있는 각 `.xctestrun` 파일 옆에 작성됩니다.

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

Tuist가 입력 옆에서 해당 그래프를 찾을 수 없는 경우(예: 빌드 작업이 `tuist test --build-only` 대신 일반 `xcodebuild build-for-testing`를 사용한 경우), 영향을 받은 대상을 여전히 계산할 수 있도록 프로젝트를 다시 생성하는 방식으로 대체됩니다. 이 대체 방식은 테스트 작업에서 Swift Package 의존성이 해결되어 있어야 하므로, 먼저 `tuist install`를 실행하거나 작업 간에 `Tuist/.build`를 캐시하세요.

그래프는 빌드 당시의 소스 트리를 반영합니다. 테스트 작업을 빌드 작업과 동일한 커밋으로 실행하세요. 두 작업 사이에 소스가 달라지면 해시가 소스와 일치하지 않게 되어, 선택적 테스팅이 새로운 소스에서는 실제로 실패할 테스트를 건너뛸 수 있습니다.

### 어떤 플래그를 사용해야 할까요? {#which-flag-should-i-use}

`.xctestrun`와 `.xctestproducts`는 서로 다른 두 가지 Xcode 출력 형식으로, 휴대성과 파이프라인 편의성 사이의 절충안이 다릅니다:

- **`-testProductsPath` (`.xctestproducts`) — 새 파이프라인에 권장됩니다.** 자체 완비형 디렉터리입니다: 빌드된 `.xctest` 바이너리와 해당 `.xctestrun` 파일이 번들 루트에 상대적인 경로로 내부에 저장되므로, 어디로 이동하더라도 유효성을 유지합니다.
- **`-xctestrun` (raw `.xctestrun`) — 이미 파생 데이터를 중심으로 구축된 파이프라인이 있다면 사용하세요.** `xcodebuild build-for-testing`는 기본적으로 `<derivedData>/Build/Products/` 최상위에 `.xctestrun`를 작성하고, 해당 트리 내 다른 위치에 있는 테스트 번들을 가리킵니다. 다른 작업에서 재사용하려면 `Build/Products/`의 경로를 그대로 유지해야 합니다.

새롭게 시작한다면 `-testProductsPath`를 선호하세요. 이미 파생 데이터를 캐시하는 기존 파이프라인에 Tuist를 연결하는 경우, 빌드 작업이 `tuist test --build-only`를 통해 실행되는 한 `-xctestrun`도 동일한 빠른 경로를 사용합니다.

두 입력 모드 모두 `-workspace`/`-project`/`-scheme`와 상호 배타적이므로, 전달 인수에 `-xctestrun` 또는 `-testProductsPath`가 포함되면 Tuist는 해당 플래그를 건너뛰고 선택된 대상을 `-only-testing`를 통해 전달합니다.

> [!WARNING]
> **모듈 수준 vs 파일 수준 세분화**
>
> 테스트와 소스 간의 코드 내 의존성을 감지할 수 없기 때문에, 기본 선택적 테스팅의 최대 세분화 수준은 대상(target) 수준입니다. [커버리지 전략](#coverage-based-test-selection)은 이를 개별 테스트 수준으로 좁힙니다. 따라서 선택적 테스팅의 이점을 극대화하려면 대상을 작고 집중적으로 유지하는 것을 권장합니다.


## 커버리지 기반 테스트 선택 {#coverage-based-test-selection}

> [!NOTE]
> **얼리 액세스**
>
> 커버리지 기반 테스트 선택은 얼리 액세스 단계입니다. 계정에서 활성화하려면 문의하세요. 활성화되기 전까지 이 전략은 기본 선택적 테스팅처럼 동작합니다.

기본적으로 선택적 테스팅은 해시가 이미 통과된 전체 테스트 대상을 건너뜁니다. `.coverage()` 전략은 더 나아가서: 남은 테스트 대상 중에서 이전 실행의 코드 커버리지가 변경 사항이触及한 파일을 하나도 포함하지 않는 테스트도 건너뜁니다. 이는 XCTest 및 XCUITest 테스트와, 이를 위해 설정된 스위트의 [Swift Testing](#swift-testing) 테스트에서 작동합니다. `Tuist.swift`에서 활성화하세요:

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
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1 이상**이 [테스트 대상에 링크](#linking-testcoverageattribution)되어 있어야 합니다. 이는 각 테스트가 실행하는 파일을 기록하고 Tuist가 선택하지 않은 테스트를 건너뜁니다. 이것이 없는 대상은 기본값과 마찬가지로 전체만 건너뜁니다.
- **충분히 자주 실행되는 전체 테스트 실행.** `tuist test --no-selective-testing`를 사용한 실행은 모든 테스트를 실행하여 기준선이 됩니다. 선택적 실행은 동일한 플랫폼에서 커밋 히스토리의 최근 실행과 비교하며, 기준선이 없으면 커버리지를 적용하지 않습니다. 어디서 얼마나 자주 실행할지는 팀의 작업 방식에 따라 다르며, 예를 들어 기본 브랜치의 모든 커밋마다, 야간 배치, 또는 릴리스 브랜치에서 실행할 수 있습니다. 우리는 기본 브랜치를 권장합니다:那里的 전체 실행은 변경 사항이 배포되기 전에 커버리지가 포착하지 못하는 부분(예: 테스트가 의존하는 픽스처나 서비스)도 잡아냅니다.

전략이 활성화되면 `tuist test`는 해시가 이미 통과된 대상을 건너뛰고, 나머지 대상 중 변경 사항이 영향을 미칠 수 있는 테스트를 Tuist에 문의합니다. 영향받는 테스트가 없는 대상은 빌드되지 않습니다. 새 테스트, 마지막으로 실패한 테스트, 변경된 테스트 파일의 테스트, 그리고 기록된 커버리지가 없는 테스트는 항상 실행됩니다.

때로는 커버리지가 적용되지 않으며, 출력 결과에 그 이유가 표시됩니다: 해시가 통과되지 않은 대상의 모든 테스트는 기본 선택적 테스팅과 마찬가지로 실행됩니다. 이는 동일한 플랫폼에서 최근 기준선이 없을 때, 변경 사항이 5,000개 이상의 파일에 영향을 미칠 때, 또는 `Package.resolved`, `Project.swift` 또는 `.xcconfig`와 같이 테스트에 영향을 줄 수 있는 파일이 변경되었을 때 발생합니다. 모든 테스트를 실행하려면 `--no-selective-testing`를 전달하세요.

> [!NOTE]
> **테스트 커버리지**
>
> 단일 실행 보고서를 읽는 커버리지 도구(Xcode 포함)는 전체 테스트 스위트가 실행되었다고 가정하므로, 선택적 실행의 보고서에는 건너뛴 테스트가 제외됩니다. Tuist의 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">코드 커버리지</.localized_link>는 대신 각 실행에서 기록하는 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">대상 수준 커버리지</.localized_link>를 사용하여 건너뛴 테스트 대상의 커버리지를 이전 실행에서 가져옵니다.

### TestCoverageAttribution 링크하기 {#linking-testcoverageattribution}

패키지를 `Tuist/Package.swift`에 추가하고 마이너 버전에 고정하세요. 0.x 마이너 릴리스는 기록되는 내용을 변경할 수 있기 때문입니다:

```swift
import PackageDescription

let package = Package(
    name: "MyApp",
    dependencies: [
        .package(
            url: "https://github.com/tuist/TestCoverageAttribution",
            .upToNextMinor(from: "0.5.1")
        ),
    ]
)
```

그런 다음 테스트 대상에 추가하고 앱 대상에는 절대 추가하지 마세요:

```swift
.target(
    name: "CheckoutTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "dev.tuist.CheckoutTests",
    sources: ["CheckoutTests/**"],
    dependencies: [
        .target(name: "Checkout"),
        .external(name: "TestCoverageAttribution"),
    ]
)
```

Tuist는 기본적으로 패키지를 정적 프레임워크로 링크합니다. XCTest 전용 대상은 패키지 내의 아무 것도 참조하지 않으므로 링커가 이를 제거하며, 이에 따라 기록 및 건너뛰기 기능도 함께 제거됩니다. 테스트 대상의 `OTHER_LDFLAGS`에 `-ObjC`를 추가하거나 `Tuist/Package.swift`에서 패키지를 동적으로 링크하세요:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testing에는 라이브러리가 참여할 수 있는 관찰 API가 없으므로, 해당 테스트는 스위트에 TestCoverageAttribution의 `.coverageAttribution` 트레잇이 필요합니다. 이 트레잇은 이를 가진 스위트 내에 중첩된 스위트에도 적용됩니다. 이 트레잇이 없는 스위트의 테스트는 테스트별 커버리지를 기록하지 않으므로 대상이 실행될 때마다 함께 실행됩니다.

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **테스트가 중복되지 않아야 합니다.** Swift Testing은 기본적으로 프로세스의 테스트를 병렬로 실행하며, 커버리지 카운터는 동시에 실행되는 테스트를 구별할 수 없으므로 이러한 테스트는 자체 커버리지를 기록하지 않고 항상 실행됩니다. `.serialized`는 스위트 내부의 테스트 순서만 지정하므로, 대상에 단일 스위트만 있을 때만 충분합니다. XCTest는 추가 설정이 필요하지 않습니다. 병렬 테스팅은 각 테스트 복제본을 별도의 프로세스에서 실행합니다.
- **테스트 대상별로 병렬화 비활성화.** Xcode는 이 설정을 각 테스트 대상에 적용하므로, 테스트별로 선택하려는 대상에만 비활성화하고 스킴의 다른 대상은 병렬로 계속 실행되도록 할 수 있습니다. 별도의 스킴이 필요하지 않습니다. 테스트 가능 대상에 `.testableTarget(target: "CheckoutTests", parallelization: .disabled)`를 설정하면 해당 대상의 XCTest 테스트도 복제본 없이 실행됩니다. Tuist가 생성한 스킴은 프로젝트의 `testingOptions`에서 이 설정을 가져오며, `.parallelizable` 또는 `.swiftTestingOnlyParallelizable`를 포함하지 않는 한 비활성화됩니다. `tuist test`에 `-parallel-testing-enabled YES` 또는 `NO`를 전달하면 해당 실행에서 모든 대상의 설정을 재정의합니다.
- **건너뛰기 기능에는 Swift 6.3 (Xcode 26.4) 이상이 필요합니다.** 이 트레잇은 Tuist가 선택하지 않은 테스트를 취소하고 건너뜬 것으로 보고합니다. 이전 버전에서는 테스트가 여전히 커버리지를 기록하지만, Tuist가 선택하지 않은 테스트도 anyway 실행됩니다.

### 항상 실행되는 테스트 {#tests-that-always-run}

커버리지는 테스트가 실행하는 코드만 인식합니다. 실제 입력이 픽스처, 리소스, 네트워크 또는 환경인 테스트는 커버된 코드가 변경되지 않아도 실패할 수 있습니다. 이를 건너뛰기 불가로 표시하면 Tuist가 선택하지 않더라도 실행됩니다:

```swift
// Swift Testing: on a test or a suite.
// `.skippable` opts a nested test or suite back in.
@Suite(.coverageAttribution, .unskippable)
struct FixtureTests {
    @Test func parsesTheFixtures() { … }
}

// XCTest: list the class's tests, or set `isUnskippable` for all of them.
final class NetworkTests: XCTestCase {
    @objc static let unskippableTests = ["testParsesTheFixtures"]
}
```

이는 실행되는 테스트 대상에만 적용됩니다. 해시가 이미 통과되었거나 Tuist가 선택한 테스트가 없는 대상은 전체가 건너뛰어지며 시작되지 않으므로, 해당 대상의 건너뛰기 불가 테스트도 실행되지 않습니다.

모든 옵션에 대해서는 [TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests)를 참조하세요.


## Pull/Merge 요청 댓글 {#pullmerge-request-comments}

> [!WARNING]
> **Git 포지 통합 필요**
>
> 자동 Pull/Merge 요청 댓글을 받으려면 <.localized_link href="/guides/server/accounts-and-projects">Tuist 프로젝트</.localized_link>를 Git 포지와 통합하세요: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> 또는 <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


Tuist 프로젝트가 [GitHub](https://github.com)와 같은 Git 플랫폼에 연결되고 CI 워크플로의 일부로 `tuist test` 사용을 시작하면, Tuist는 Pull/Merge 요청에 직접 댓글을 게시하며, 어떤 테스트가 실행되었고 어떤 테스트가 건너뛰었는지 포함합니다: ![GitHub 앱 댓글 with Tuist Preview 링크](/images/guides/features/selective-testing/github-app-comment.png)


## 대시보드에서 누락 조사하기 {#investigating-misses-on-the-dashboard}

이전에 캐시된 테스트 대상이 누락으로 표시되면, 테스트 실행 페이지의 **선택적 테스팅** 탭에서 해시를 생성한 입력을 자세히 살펴볼 수 있습니다. 행을 확장하면 소스, 의존성, 환경 변수, 프로젝트 및 대상 설정, Info.plist, 권한, 헤더 등 구성 요소별 부분 해시가 표시되어 실행 간에 변경된 입력을 정확히 찾아낼 수 있습니다.

선택적 테스팅 카드 상단의 **JSON으로 복사** 버튼을 사용하여 모든 선택적 테스팅 대상과 해당 해시 및 부분 해시를 내보내세요. 두 실행 간의 JSON을 비교하는 것은 테스트 대상의 해시가 변경되었을 때 어떤 입력이 변경되었는지 확인하는 가장 빠른 방법입니다.
