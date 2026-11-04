---
{
  "title": "생성된 Xcode 프로젝트",
  "titleTemplate": ":title · 선택적 테스팅 · 기능 · 가이드 · Tuist",
  "description": "Tuist 선택적 테스팅을 사용하여 최신 변경 사항의 영향을 받는 Xcode 및 생성된 프로젝트 테스트만 실행하여, 지속적 통합에서 몇 초 만에 피드백을 받을 수 있습니다."
}
---
# 생성된 Xcode 프로젝트 {#generated-xcode-project}

프로젝트가 커짐에 따라 테스트 양도 늘어납니다. 오랫동안 모든 PR이나 `main`로의 푸시에서 모든 테스트를 실행하는 데 수십 초가 걸렸습니다. 하지만 이 방식은 팀이 보유한 수천 개의 테스트로 확장하기 어렵습니다.

CI의 각 테스트 실행에서는 변경 사항과 무관하게 대부분 모든 테스트를 다시 실행합니다. Tuist의 선택적 테스팅은 <.localized_link href="/guides/features/projects/hashing">해싱 알고리즘</.localized_link>을 기반으로 마지막 성공한 테스트 실행 이후 변경된 테스트만 실행하여 테스트 자체의 속도를 획기적으로 높여줍니다.

<.localized_link href="/guides/features/projects">생성된 프로젝트</.localized_link>에서 선택적으로 테스트를 실행하려면 `tuist test` 명령어를 사용하세요. 이 명령어는 <.localized_link href="/guides/features/cache/module-cache">모듈 캐시</.localized_link>와 동일한 방식으로 프로젝트를 <.localized_link href="/guides/features/projects/hashing">해싱</.localized_link>하며, 성공 시 해시를 저장하여 향후 실행에서 무엇이 변경되었는지 판단합니다. 이후 실행에서는 `tuist test`가 해시를 투명하게 사용하여 테스트를 필터링하고 마지막 성공한 테스트 실행 이후 변경된 항목만 실행합니다.

`tuist test`는 <.localized_link href="/guides/features/cache/module-cache">모듈 캐시</.localized_link>와 직접 통합되어 로컬 또는 원격 저장소의 바이너리를 최대한 활용함으로써 테스트 스위트 실행 시 빌드 시간을 단축합니다. 선택적 테스팅과 모듈 캐싱을 함께 사용하면 CI에서 테스트 실행에 소요되는 시간을 크게 줄일 수 있습니다.

테스트 실행이 시뮬레이터만 대상으로 한다면 `--destination simulator`를 전달하여 `tuist test`가 캐시된 바이너리의 시뮬레이터 슬라이스만 사용하고 다운로드하도록 하세요. <.localized_link href="/guides/features/cache/module-cache#destination-selection">대상 선택</.localized_link>을 참조하세요. 선택적 테스팅 해시는 모든 `--destination` 값에서 동일합니다.

## 빌드 작업과 테스트 작업 분리 {#separate-build-and-test-jobs}

선택적 테스팅은 별도의 빌드 작업과 테스트 작업을 지원합니다. 빌드 작업에서 `tuist test --build-only`를 실행하면 Tuist가 빌드가 생성하는 제품과 함께 `selective-testing-graph.json` 파일을 저장할 수 있습니다. 해당 그래프에는 선택적 테스팅에 필요한 해시가 포함되어 있으므로, 테스트 작업에서 어떤 대상을 실행해야 할지 파악하기 위해 프로젝트를 다시 생성하거나 Swift Package 의존성을 해결할 필요가 없습니다.

Tuist는 `--build-only` 중에 그래프를 두 곳에 작성합니다:

- `-testProductsPath`를 전달할 때 `.xctestproducts` 번들 내부에 작성됩니다.
- 파생 데이터의 `Build/Products/` 디렉터리 아래에 있는 각 `.xctestrun` 파일 옆에 작성됩니다.

두 출력 중 하나를 빌드된 제품과 함께 캐시하고 테스트 작업에서 `--without-building`에 동일한 경로를 전달하세요. 두 형식 모두 작동합니다:

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
  --derived-data-path artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  --derived-data-path artifacts/derived-data \
  -- \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

Tuist가 입력 옆에서 해당 그래프를 찾지 못하면(예를 들어, 빌드 작업이 `tuist test --build-only` 대신 일반 `xcodebuild build-for-testing`를 사용한 경우), 영향을 받는 대상을 여전히 계산할 수 있도록 프로젝트를 다시 생성하는 방식으로 대체됩니다. 이 대체 방식은 테스트 작업에서 Swift Package 의존성이 해결되어 있어야 하므로, 먼저 `tuist install`를 실행하거나 작업 간에 `Tuist/.build`를 캐시하세요.

그래프는 빌드 당시의 소스 트리를 반영합니다. 테스트 작업을 빌드 작업과 동일한 커밋으로 실행하세요. 두 작업 사이에 소스가 달라지면 해시가 최신 상태를 반영하지 못하게 되어, 선택적 테스팅이 새로운 소스에서는 실제로 실패할 테스트를 건너뛸 수 있습니다.

### 어떤 플래그를 사용해야 할까요? {#which-flag-should-i-use}

`.xctestrun`와 `.xctestproducts`는 서로 다른 두 가지 Xcode 출력 형식으로, 이동성과 파이프라인 편의성 사이의 균형을 다르게 맞춥니다:

- **`-testProductsPath` (`.xctestproducts`) — 새로운 파이프라인에 권장됩니다.** 자체 포함된 디렉터리입니다. 빌드된 `.xctest` 바이너리와 해당 `.xctestrun` 파일이 번들 루트에 상대적인 경로로 내부에 저장되므로, 어디로 이동하더라도 유효하게 유지됩니다. 또한 선택적 테스팅 고속 경로가 가장 오래 적용된 형식이므로 가장 많이 검증된 경로입니다.
- **`-xctestrun` (원본 `.xctestrun`) — 이미 파생 데이터를 중심으로 구축된 파이프라인이 있다면 사용하세요.** `xcodebuild build-for-testing`는 기본적으로 `<derivedData>/Build/Products/` 최상단에 `.xctestrun`를 작성하고 해당 트리 내 다른 위치에 있는 테스트 번들을 가리킵니다. 다른 작업에서 이를 재사용하려면 `Build/Products/`의 경로를 그대로 유지해야 합니다.

새롭게 시작한다면 `-testProductsPath`를 선호하세요. 이미 파생 데이터를 캐시하는 기존 파이프라인에 Tuist를 연결하는 경우, 빌드 작업이 `tuist test --build-only`를 통해 실행되는 한 `-xctestrun`도 동일한 고속 경로를 사용할 수 있습니다.

두 입력 모드 모두 `-workspace`/`-project`/`-scheme`와 상호 배타적이므로, 전달 인수에 `-xctestrun` 또는 `-testProductsPath`가 포함되면 Tuist는 해당 플래그를 건너뛰고 선택된 대상을 `-only-testing`를 통해 전달합니다.

> [!WARNING]
> **모듈 수준 대 파일 수준 세분성**
>
> 테스트와 소스 간의 코드 내 의존성을 감지할 수 없기 때문에 선택적 테스팅의 최대 세분성은 대상(target) 수준입니다. 따라서 선택적 테스팅의 이점을 극대화하기 위해 대상을 작고 집중적으로 유지하는 것을 권장합니다.


> [!NOTE]
> **테스트 커버리지**
>
> 단일 실행의 보고서를 읽는 커버리지 도구(Xcode 포함)는 전체 테스트 스위트가 실행되었다고 가정하므로, 선택적 실행의 보고서에서는 건너뛴 테스트가 제외됩니다. Tuist의 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">코드 커버리지</.localized_link>는 매 실행마다 기록하는 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">대상 수준 커버리지</.localized_link>를 사용하여 건너뛴 테스트 대상의 커버리지를 이전 실행에서 이어받습니다.


## Pull/Merge 요청 댓글 {#pullmerge-request-comments}

> [!WARNING]
> **Git 플랫폼 연동 필요**
>
> 자동 Pull/Merge 요청 댓글을 받으려면 <.localized_link href="/guides/server/accounts-and-projects">Tuist 프로젝트</.localized_link>를 <.localized_link href="/guides/server/authentication">Git 플랫폼</.localized_link>과 연동하세요.


Tuist 프로젝트가 [GitHub](https://github.com)와 같은 Git 플랫폼에 연결되고 CI 워크플로의 일부로 `tuist test` 사용을 시작하면, Tuist는 Pull/Merge 요청에 직접 댓글을 게시하며 어떤 테스트가 실행되었고 어떤 테스트가 건너뛰었는지 포함합니다: ![Tuist 미리보기 링크가 포함된 GitHub 앱 댓글](/images/guides/features/selective-testing/github-app-comment.png)


## 대시보드에서 미스(miss) 조사하기 {#investigating-misses-on-the-dashboard}

이전에 캐시된 테스트 대상이 미스로 표시될 때, 테스트 실행 페이지의 **선택적 테스팅** 탭에서 해시를 생성한 입력을 세부적으로 확인할 수 있습니다. 행을 확장하면 소스, 의존성, 환경 변수, 프로젝트 및 대상 설정, Info.plist, 권한(entitlements), 헤더 등 구성 요소별 서브해시가 드러나므로, 실행 간에 변동된 입력을 정확히 찾아낼 수 있습니다.

선택적 테스팅 카드 상단의 **JSON으로 복사** 버튼을 사용하여 각 선택적 테스팅 대상의 해시와 서브해시를 내보내세요. 두 실행 간 JSON을 비교하면 테스트 대상의 해시가 변동되었을 때 어떤 입력이 변경되었는지 가장 빠르게 확인할 수 있습니다.
