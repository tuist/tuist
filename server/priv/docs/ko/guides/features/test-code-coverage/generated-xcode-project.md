---
{
  "title": "생성된 Xcode 프로젝트",
  "titleTemplate": ":title · 코드 커버리지 · 기능 · 가이드 · Tuist",
  "description": "바이너리 캐시와 선택적 테스팅으로 건너뛴 코드를 포함하여, Tuist가 생성한 Xcode 프로젝트의 파일별 및 커밋별 코드 커버리지를 측정합니다."
}
---
# 생성된 Xcode 프로젝트 {#generated-xcode-project-code-coverage}

<!-- @snippet: ./_xcode-early-access -->

코드 커버리지는 테스트가 실행한 코드의 줄을 보여줍니다. Tuist는 모든 `tuist test` 실행의 줄 커버리지를 업로드하고, 커밋의 실행들을 프로젝트, 각 타겟 및 각 파일별로 하나의 수치로 합칩니다. 대시보드의 **코드 커버리지** 페이지에서는 이를 커밋별 및 각 브랜치의 추이로 표시합니다.

Tuist가 작업을 건너뛰어도 수치는 정확성을 유지합니다. <.localized_link href="/guides/features/cache/module-cache">바이너리 캐시</.localized_link>에서 가져온 타겟은 커버리지 카운터와 함께 빌드되므로, 소스에서 빌드된 코드와 동일하게 측정됩니다. 그리고 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">선택적 테스팅</.localized_link>이 테스트 타겟을 건너뛸 때, 해당 타겟은 이전 실행에서 가졌던 커버리지를 유지하며, 이는 Tuist가 모든 실행에서 기록하는 [타겟 수준 커버리지](#target-level-coverage)를 통해 이루어집니다.

## 설정 {#setup}

### 커버리지 켜기 {#turn-coverage-on}

`Tuist.swift`의 생성 옵션에서 커버리지를 켜고, 기본적으로 비활성화된 커버리지 업로드를 활성화하세요:

```swift
import ProjectDescription

let tuist = Tuist(
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .tuist(
        generationOptions: .options(
            coverage: .coverage(enabled: true)
        )
    )
)
```

생성 옵션이 켜져 있으면:

- Tuist가 생성하는 모든 스킴의 테스트 액션은 커버리지를 수집하며, `coverage`를 설정하지 않고 정의한 모든 스킴의 테스트 액션도 마찬가지입니다. `.options(coverage: false)` 또는 `.options(coverage: true)`인 스킴은 해당 값을 유지합니다. 테스트 플랜은 자체적으로 커버리지를 결정합니다. Tuist가 생성하는 테스트 플랜의 경우, `.testPlans(_:coverage:)`에 `coverage: true`를 전달하세요.
- 프로젝트의 자체 타겟은 디버그 구성에서 커버리지 카운터와 함께 바이너리 캐시에서 읽히고 예열됩니다. [작동 방식](#instrumented-binaries)을 참조하세요.

`TUIST_COVERAGE_ENABLED` 및 `TUIST_COVERAGE_UPLOAD` 환경 변수(`1` 또는 `0`)는 `enabled` 및 `upload`보다 우선합니다. 캐시를 예열하는 명령과 읽는 명령이 일치하도록, 단일 명령이 아닌 CI 워크플로우와 같은 전체 환경에 대해 설정하세요.

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 생성 옵션은 프로젝트 타겟의 캐시 키와 테스트 타겟의 선택적 테스팅 해시를 변경합니다. 캐시를 공유하는 모든 머신에서 동일한 값을 사용하고, 환경(예: `Environment.isCI`)에서 파생하지 마세요. 커버리지가 꺼진 실행은 커버리가 켜진 실행의 바이너리나 선택적 테스팅 결과를 재사용하지 않습니다.

### 스킴 제외하기 {#leave-schemes-out}

일부 테스트 스위트는 커버리지에 포함되지 않아야 합니다. 예를 들어, 다른 프로세스에서 앱이나 CLI를 구동하는 인수 테스트나 엔드투엔드 테스트는 커버리지가 볼 수 없는 코드를 실행하며, 이를 수집하면 속도만 느려집니다. 해당 스킴의 테스트 액션에서 커버리지를 끄세요:

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

스킴은 `Tuist.swift` 옵션이나 `TUIST_COVERAGE_ENABLED` 설정과 상관없이 커버리지를 끈 상태로 유지되며, 해당 실행은 커밋의 커버리지에 포함되지 않습니다. 커버리지는 스킴별로 수집되므로, 특정 테스트 타겟을 제외하려면 이를 별도의 스킴으로 이동하세요.

### 테스트 실행하기 {#run-your-tests}

평소처럼 `tuist test`로 테스트를 실행하세요:

```sh
tuist test
```

Tuist는 실행이 수집한 커버리지를 테스트 결과와 함께 업로드합니다. 여기에는 <.localized_link href="/guides/features/test-sharding/generated-xcode-project">샤딩된 실행</.localized_link>과 `--without-building`로 다른 작업에서 빌드된 제품을 테스트하는 실행이 포함됩니다. 포크의 풀 리퀘스트를 실행하는 작업 등 Tuist에서 실행의 커버리지를 제외하려면 `TUIST_COVERAGE_UPLOAD=0`로 설정하세요.

### CI에서 각 커밋 완료하기 {#complete-each-commit}

커밋의 커버리지는 종종 여러 작업(스킴별, 샤드별 또는 플랫폼별)에서 옵니다. Tuist는 마지막 보고 시점을 알 수 없으므로 직접 알려줘야 합니다. 커밋의 모든 테스트 작업이 끝나면, 이들에 의존하는 작업에서 다음을 실행하세요:

```sh
tuist coverage complete
```

명령은 체크아웃 또는 CI 제공자로부터 커밋을 읽습니다. 다른 커밋을 지정하려면 `--commit <sha>`를 전달하세요. 커밋이 완료될 때까지 해당 커버리지는 **진행 중**으로 표시되며 브랜치 추이에 포함되지 않습니다.

### 기본 브랜치에서 전체 스위트 실행하기 {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 선택적 테스팅은 건너뛴 타겟을 이어받을 이전 실행이 있을 때만 커밋의 커버리지를 완전하게 유지합니다. 기본 브랜치에서 선택적 테스팅 없이 모든 테스트를 실행하도록 스케줄링하세요:
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> 매 병합 시 한 번씩 실행하는 것이 이상적입니다. 변경 사항이 적은 저장소의 경우 매일 또는 매주 실행해도 충분할 수 있습니다. 기록된 커버리지는 90일 후에 만료되므로 그보다 더 자주 실행하세요.

이어받은 커버리지는 전체 실행에 의존합니다. 전체 실행은 만료되기 전에 각 타겟의 기록된 커버리지를 새로 고치고, 선택적 실행이 빌드하지 않는 파일의 최근 상태를 Tuist에 제공합니다. 전체 실행 사이에 저장소가 많이 변경될수록, 선택적 실행은 이후 변경된 파일을 더 자주 발견하게 되며 해당 커밋의 커버리지는 **불완전**이 됩니다.

## 타겟 수준 커버리지 {#target-level-coverage}

실행의 커버리지는 전체 실행이 무엇을 실행했는지 보여주며, 각 테스트 타겟이 무엇을 실행했는지는 보여주지 않습니다. 선택적 테스팅이 타겟을 건너뛸 때, Tuist는 해당 타겟의 커버리지를 이어받기 위해 이전 실행에서 해당 타겟이 무엇을 실행했는지 알아야 합니다.

따라서 Tuist는 모든 실행에서 각 테스트 타겟이 실행한 파일과 줄을 기록합니다. 이는 Xcode가 각 테스트 프로세스에 대해 작성하는 커버리지에서 읽어오므로 추가 링크나 구성이 필요하지 않습니다. 이는 macOS 및 iOS 시뮬레이터에서 기록되며, 디바이스에서는 기록되지 않습니다. UI 테스트는 구동하는 앱에 대한 정보를 기록하지 않는데, 이는 앱의 코드가 자체 프로세스에서 실행되기 때문입니다.

## 작동 방식 {#how-it-works}

### 계측된 바이너리 {#instrumented-binaries}

바이너리 캐시의 타겟은 미리 빌드된 바이너리이며, 테스트 실행은 바이너리가 커버리지 카운터와 함께 빌드된 경우에만 코드를 측정할 수 있습니다. 커버리지가 켜져 있으면, 바이너리 캐시는 프로젝트 자체 타겟의 계측된 변형을 유지하며, 모든 명령은 해당 변형을 읽고 예열합니다:

- **디버그 구성**은 계측된 변형을 사용합니다. `tuist cache`가 이를 예열하고, `tuist generate` 및 `tuist test`가 이를 읽습니다.
- **릴리스 구성**은 항상 일반 변형을 사용하므로, 배포되는 제품에는 절대 커버리지 카운터가 포함되지 않습니다.
- **외부 패키지**는 항상 일반 변형을 사용합니다. Tuist는 저장소의 코드만 측정합니다.

테스트 작업과 동일한 환경에서 커버리지를 켜고 캐시를 예열하여 `tuist test`가 계측된 바이너리를 찾도록 하세요. 실행이 커버리지를 수집하지만 캐시에서 일반 바이너리로 타겟을 가져오는 경우, Tuist는 경고하며 해당 코드는 측정되지 않습니다. <.localized_link href="/guides/features/cache/module-cache#code-coverage">모듈 캐시</.localized_link>에서 변형에 대해 자세히 설명합니다.

### 머신 간 경로 {#paths-across-machines}

계측된 바이너리는 빌드된 체크아웃을 기준으로 소스 경로를 기록하므로, CI에서 예열된 바이너리는 모든 개발자의 머신에서 올바른 파일을 측정합니다.

<.localized_link href="/guides/features/cache/xcode-cache">Xcode 캐시</.localized_link>도 전위 매핑을 통해 동일하게 작동하며, Tuist는 커버리지를 수집하는 빌드에서 이를 기본적으로 비활성화합니다. 이는 Xcode 자체의 커버리지 보고서가 매핑된 경로를 해결할 수 없기 때문입니다. Xcode 27 이상에서는 `enableCaching`를 켜고 `prefixMapping: true`를 사용하여 이를 활성화할 수 있으므로, 커버리지 빌드는 체크아웃 간에 컴파일 결과를 공유합니다:

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist의 업로드는 매핑된 경로를 해결하지만, Xcode의 커버리지 보고서와 `xccov`는 해당 파일을 제외할 수 있습니다. <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">전위 매핑을 사용한 커버리지</.localized_link>를 참조하세요.

### 스킵된 테스트 {#skipped-tests}

선택적 테스팅은 이전의 성공적인 실행이 동일한 해시로 이미 테스트한 경우 테스트 타겟을 건너뜁니다. 해시는 타겟의 소스, 테스트 및 모든 의존성을 포함하므로, 동일한 해시는 동일한 코드에 대한 동일한 테스트를 의미합니다. Tuist는 이전 실행이 타겟에 대해 기록한 [타겟 수준 커버리지](#target-level-coverage)를 재사용합니다. 만약 아무것도 기록되지 않았다면(예: 당시 커버리지가 꺼져 있었거나 실행이 90일보다 오래된 경우), 이어갈 데이터가 없으며 커밋은 **불완전**으로 표시됩니다.

선택적 실행은 또한 모든 파일을 빌드하지 않습니다. 컴파일하지 않은 파일의 경우, Tuist는 파일이 이후로 변경되지 않은 한 가장 가까운 이전 전체 실행의 줄 정보를 가져옵니다. 이것이 기본 브랜치의 [전체 실행](#full-runs)이 중요한 이유입니다.

`--skip-test-targets` 또는 `-skip-testing`를 사용하여 직접 건너뛴 테스트는 이어지지 않습니다. 해당 테스트를 제외한 실행만 있는 커밋은 다른 실행이 이를 수행하지 않는 한 **불완전**으로 표시됩니다. 격리로 인해 건너뛴 테스트는 커버리지에 전혀 포함되지 않습니다. Tuist는 이를 이어가지도 않으며, 이로 인해 커밋을 **불완전**으로 표시하지도 않습니다.

### 완료 및 불완전 커밋 {#commit-status}

대시보드의 각 커밋에는 상태가 있습니다:

| 상태 | 의미 |
| --- | --- |
| 진행 중 | 실행이 커버리지를 보고했지만, `tuist coverage complete`가 아직 커밋에 대해 실행되지 않았습니다. |
| 완료 | 커밋의 스킴에 대한 모든 테스트가 실행되거나 이어졌습니다. |
| 불완전 | 일부 커버리지를 확인할 수 없어 수치가 하한선으로 표시됩니다. |
| 측정되지 않음 | 커밋에 대해 커버리지를 보고한 실행이 없습니다. |

브랜치의 추세에는 완료된 커밋만 포함됩니다. 커밋은 예를 들어 다음과 같은 경우 불완전합니다:

- 선택적 테스팅이 이어질 수 없는 타겟을 건너뛰었습니다. 이전 실행이 이에 대한 커버리지를 기록하지 않았거나, 선택적 실행이 빌드하지 않은 파일이 마지막 전체 실행 이후 변경되었거나, 커밋이 `Package.resolved`, `Project.swift` 또는 `.xcconfig`와 같이 모든 타겟에 영향을 미치는 파일을 변경했습니다.
- 실행이 `--skip-test-targets` 또는 `-skip-testing`를 사용하여 테스트를 건너뛰었고, 해당 커밋의 다른 실행이 이를 수행하지 않았습니다.
- 실행이 바이너리 캐시에서 일반 바이너리로 타겟을 가져왔습니다.
- 스킴의 모든 실행이 `-only-testing`로 제한되었습니다.
- 스킴의 커버리지가 커밋되지 않은 변경 사항이 있는 체크아웃에서의 CI 실행에서만 발생했습니다.

## 성능 영향 {#performance-impact}

커버리지 수집은 오버헤드를 추가하며, 주로 테스트가 끝난 후 Xcode가 커버리지 보고서를 작성하고 Tuist가 커버리지를 내보내는 동안 발생합니다. 테스트를 빌드하고 실행하는 데는 커버리지 없이 할 때와 비슷한 시간이 소요됩니다. 계측된 빌드는 DerivedData와 디버그 바이너리 캐시에서 더 많은 디스크 공간을 차지합니다. 릴리스 빌드와 아카이브는 영향을 받지 않습니다.

## 제한 사항 {#limitations}

### 커버리지를 수집하는 스킴의 릴리스 빌드 {#release-builds}

스킴의 테스트 액션이 커버리지를 수집하면, Xcode는 해당 스킴에 대해 `xcodebuild build`가 소스에서 컴파일하는 타겟을 모든 구성(릴리스 포함)에서 계측합니다. `xcodebuild archive`는 이 설정을 무시하므로 아카이브는 절대 계측되지 않습니다. 아카이브를 배포하거나, `.options(coverage: false)`가 있는 스킴에서 릴리스 제품을 빌드하세요.

### 다른 커버리지 도구 {#other-coverage-tools}

`-enableCodeCoverage YES`는 Xcode와 마찬가지로 실행이 커버리지를 수집할지 여부만 결정합니다. 이는 Tuist가 캐시에서 계측된 바이너리를 읽게 하지 않으므로, 대신 `Tuist.swift` 옵션이나 `TUIST_COVERAGE_ENABLED`를 사용하세요.

다른 커버리지 도구에 데이터를 제공하려면, `tuist test`가 각 실행의 커버리지를 LCOV로 작성하도록 하세요. 이는 Tuist가 업로드하는 것과 동일한 커버리지이며, 저장소 상대 경로와 바이너리 캐시의 코드가 포함됩니다:

```sh
tuist test --coverage-output-path coverage
```

각 실행은 `coverage/<result bundle name>.lcov`를 작성합니다. 샤딩된 실행의 파일은 `lcov -a`로 병합하세요. 이 옵션은 커버리지 업로드가 켜져 있어야 합니다.

Xcode 자체의 커버리지 보고서와 이를 읽는 도구는 해당 실행에서 Xcode가 빌드한 타겟만 포함하며, 바이너리 캐시에서 나온 코드는 절대 포함하지 않습니다. Tuist의 업로드는 둘 다 측정합니다. Xcode의 보고서에서 타겟의 커버리지를 확인하려면, 해당 타겟을 소스에서 빌드하도록 프로젝트를 생성하세요. `tuist generate MyTarget`는 `MyTarget`를 소스로 유지하고 나머지는 캐시에서 가져옵니다.

## 커버리지 조회 {#querying}

`tuist coverage` 명령은 대시보드에 표시되는 내용을 읽습니다. `--commit` 없이 사용하면, `--branch` 또는 기본 브랜치의 최신 완료된 커밋을 읽습니다:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

모든 명령은 스크립팅을 위해 `--json`를 허용합니다. 동일한 데이터는 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 서버</.localized_link>를 통해 에이전트가 사용할 수 있습니다.
