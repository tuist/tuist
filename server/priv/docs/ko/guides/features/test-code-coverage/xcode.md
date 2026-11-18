---
{
  "title": "Xcode 코드 커버리지",
  "titleTemplate": ":title · 코드 커버리지 · 기능 · 가이드 · Tuist",
  "description": "Xcode 프로젝트의 코드 커버리지를 Tuist에 업로드하고 파일별, 커밋별로 추적하세요."
}
---
# Xcode 코드 커버리지 {#xcode-code-coverage}

코드 커버리지는 테스트가 코드의 어떤 줄을 실행했는지 보여줍니다. Tuist는 각 테스트 실행의 라인 커버리지를 업로드하고, 프로젝트, 각 타겟 및 각 파일에 대해 커밋의 실행들을 하나의 수치로 집계합니다. 대시보드의 **코드 커버리지** 페이지에서는 이를 커밋별 및 각 브랜치의 추이로 표시합니다.

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> Tuist로 프로젝트를 생성하는 경우, 대신 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">생성된 프로젝트 가이드</.localized_link>를 따르세요. 이 가이드는 바이너리 캐시에서 오는 코드를 측정하며 선택적 테스팅이 건너뛴 테스트 타겟의 커버리지를 이어갑니다.

## 설정 {#setup}

### 커버리지 수집 {#collect-coverage}

`Tuist.swift`에서 커버리지 업로드를 활성화하세요. 기본적으로 비활성화되어 있습니다:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` 환경 변수(`1` 또는 `0`)는 옵션보다 우선 적용됩니다. 예를 들어 포크에서 온 풀 리퀘스트를 실행하는 작업에서 업로드를 비활성화할 때 사용할 수 있습니다.

그런 다음 스키마의 테스트 액션(**Edit Scheme › Test › Options**)에서 **코드 커버리지**를 켜거나, 실행 시 `-enableCodeCoverage YES`를 전달하고 `tuist xcodebuild test`를 통해 테스트를 실행하세요:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist는 실행이 수집한 커버리지를 테스트 결과와 함께 업로드합니다.

### CI에서 각 커밋 완료하기 {#complete-each-commit}

커밋의 커버리지는 종종 여러 작업에서 나옵니다: 스키마별, 샤드별 또는 플랫폼별 하나씩입니다. Tuist는 마지막 보고가 언제 이루어졌는지 알 수 없으므로 직접 알려줘야 합니다. 커밋의 모든 테스트 작업이 끝나면, 이들에 모두 의존하는 작업에서 다음을 실행하세요:

```sh
tuist coverage complete
```

커밋이 완료될 때까지 해당 커버리지는 **진행 중**으로 표시되며 브랜치 추이에 포함되지 않습니다. <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">생성된 프로젝트 가이드</.localized_link>에서 각 상태를 설명합니다.

## 건너뛴 테스트 {#skipped-tests}

실행이 `-skip-testing`로 테스트를 건너뛰면, 커밋의 테스트가 커버하는 범위보다 적게 측정되며 Tuist는 이전 실행에서 해당 테스트를 이어갈 수 없습니다. 해당 커밋의 다른 실행에서 이를 실행하지 않는 한, 커밋의 커버리지는 **불완전**으로 표시됩니다. 커밋을 완전하게 유지하려면 커밋당 최소 한 번의 실행에서 모든 테스트를 실행하세요.

격리가 건너뛴 테스트는 커버리지에 전혀 포함되지 않으므로, 커밋을 **불완전**으로 만들지 않습니다.

## 성능 영향 {#performance-impact}

커버리지 수집은 오버헤드를 추가하며, 주로 Xcode가 커버리지 리포트를 작성하고 Tuist가 커버리지를 내보내는 동안 테스트가 끝난 후에 발생합니다. 테스트를 빌드하고 실행하는 시간은 커버리지 없이 실행할 때와 비슷합니다.

## 커버리지 조회 {#querying}

`tuist coverage` 명령어는 대시보드에 표시되는 내용을 읽습니다. `--commit` 없이 실행하면 `--branch` 또는 기본 브랜치의 최신 완료된 커밋을 읽습니다:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

테스트 실행 자체의 커버리지는 `tuist test show <test-run-id>`에서 확인할 수 있습니다.

모든 명령어는 스크립팅을 위해 `--json`를 지원합니다.
