---
{
  "title": "Rust 코드 커버리지",
  "titleTemplate": ":title · 코드 커버리지 · 기능 · 가이드 · Tuist",
  "description": "Rust 프로젝트의 Cargo 테스트 라인 커버리지를 업로드하고 파일, 패키지 및 커밋별로 추적하세요."
}
---
# Rust 코드 커버리지 {#rust-code-coverage}

코드 커버리지는 테스트가 코드의 어떤 줄을 실행했는지 보여줍니다. Tuist는 LLVM의 소스 기반 커버리지를 사용하여 모든 `cargo test` 실행의 라인 커버리지를 측정하고, 커밋의 실행 결과를 프로젝트, 각 패키지 및 각 파일별로 하나의 수치로 통합합니다. 대시보드의 **코드 커버리지** 페이지에서는 이를 커밋별 및 각 브랜치의 추이로 확인할 수 있습니다.

> [!IMPORTANT]
> **필수 조건**
>
> - <.localized_link href="/guides/get-started/rust-project">Rust 프로젝트 설정</.localized_link> 가이드를 따르세요
> - Rust 툴체인의 LLVM 도구(`llvm-tools`). Tuist는 rustup이 관리하는 툴체인에 이들을 설치합니다.
> - Git 리포지토리에 있는 여러분의 프로젝트

## 설정 {#setup}

### 커버리지 활성화 {#turn-coverage-on}

리포지토리 루트의 `tuist.toml`에 다음을 추가하세요:

```toml
[test_insights.coverage]
upload = true
```

그런 다음 평소와 같이 테스트를 실행하세요:

```sh
tuist cargo test --workspace
```

Tuist는 리포지토리의 크레이트를 `-C instrument-coverage` 옵션으로 빌드하고, 테스트를 실행한 후 실행 결과와 함께 커버리지를 업로드합니다. 테스트의 출력과 종료 코드는 변경되지 않습니다. 단일 실행에 대한 설정을 재정의하려면 `TUIST_COVERAGE_UPLOAD=1` 또는 `TUIST_COVERAGE_UPLOAD=0`를 설정하세요.

커버리지는 Tuist가 각 실행 시 업로드하는 Git 히스토리에 의존하며, 이를 통해 커밋이 해당 브랜치에 배치됩니다. Git 리포지토리 외부에서 실행된 경우 테스트 결과는 업로드되지만 커버리지는 업로드되지 않습니다.

### 샤딩된 실행 {#sharded-runs}

<.localized_link href="/guides/features/test-sharding/rust">테스트를 샤딩</.localized_link>할 때, 커버리지가 활성화된 상태로 실행되는 각 샤드는 자체 타겟의 커버리지를 보고하며, Tuist는 한 실행의 샤드들을 하나의 수치로 병합합니다. 샤드는 의도적으로 스위트의 일부만 실행하므로 커밋의 커버리지가 불완전해지지 않습니다.

### CI에서 각 커밋 완료하기 {#complete-each-commit}

커밋의 커버리지는 종종 여러 작업(샤드별 또는 기능 세트별)에서 나옵니다. Tuist는 마지막 보고가 언제 이루어졌는지 알 수 없으므로 직접 알려주어야 합니다. 커밋의 모든 테스트 작업이 완료되면, 이들에 의존하는 작업에서 다음을 실행하세요:

```sh
tuist cargo coverage-complete
```

이 명령은 체크아웃에서 커밋을 읽거나, CI 제공자가 풀 리퀘스트에서 보고한 커밋을 사용합니다. 다른 커밋을 지정하려면 `--commit <sha>`를 전달하세요. 커밋이 완료될 때까지 해당 커버리지는 **진행 중**으로 표시되며 브랜치 추이에 포함되지 않습니다.

## 작동 방식 {#how-it-works}

### Tuist가 측정하는 항목 {#what-tuist-measures}

- **패키지.** 각 Cargo 패키지는 대시보드에서 고유한 커버리지를 가진 타겟으로 표시됩니다.
- **프로덕션 코드만.** 통합 테스트, 벤치마크 및 예제(`tests/`, `benches/` 및 `examples/` 디렉터리와 이러한 종류의 타겟)는 테스트 코드입니다. Tuist는 이를 저장하지만 모든 수치에서는 제외합니다. `#[cfg(test)]` 모듈의 유닛 테스트는 소스 파일의 일부이므로, `cargo llvm-cov`와 마찬가지로 해당 줄이 함께 계산됩니다.
- **함수.** 각 줄은 바로 위에 시작되는 함수에 속합니다. 제네릭 함수는 인스턴스화된 타입 수와 관계없이 한 번만 계산됩니다.
- **Doctests**는 평소와 같이 실행되지만 측정되지 않습니다.

Tuist는 나중에 커버리지 기반 테스트 선택을 위해 각 테스트 바이너리가 실행한 코드도 기록합니다. `cargo test`는 바이너리의 테스트를 하나의 프로세스에서 실행하므로, 해당 기록은 개별 테스트가 아닌 바이너리 전체에 속합니다.

### 스킵된 테스트 {#skipped-tests}

실행 인수가 테스트를 제외하는 경우(예: 테스트 이름 필터, `--skip`, `--ignored`, `-p`, `--exclude`, `--lib` 또는 `--test`), 아무것도 제외하지 않은 다른 커밋 실행이 함께 수행되지 않으면 해당 커밋의 커버리지는 **불완전**으로 표시됩니다. 모든 테스트 바이너리가 실행되기 전에 `cargo test`를 중단시키는 실패도 동일한 영향을 미칩니다. 나머지 바이너리를 계속 실행하려면 `--no-fail-fast`를 추가하세요.

일부 테스트는 의도적으로 제외되며 커밋을 불완전하게 만들지 않습니다:

- **<.localized_link href="/guides/features/test-insights/flaky-tests/rust">격리</.localized_link>되어 스킵된 테스트.** 이들은 제거된 것처럼 제외되므로, 이들만 커버했던 줄은 커버되지 않은 것으로 간주됩니다.
- **다른 샤드의 타겟**(테스트를 샤딩할 경우)
- **무시된 테스트**(`#[ignore]`), 기본적으로 실행되지 않음

### 완료 및 불완전 커밋 {#commit-status}

대시보드의 각 커밋에는 상태가 있습니다:

| 상태 | 의미 |
| --- | --- |
| 진행 중 | 실행에서 커버리지가 보고되었지만, 아직 해당 커밋에 대해 `tuist cargo coverage-complete`가 실행되지 않았습니다. |
| 완료 | 커밋 실행의 모든 테스트가 실행되었거나 의도적으로 제외되었습니다. |
| 불완전 | 일부 커버리지를 확인할 수 없어 수치가 하한선으로 표시됩니다. |
| 측정되지 않음 | 커밋에 대해 커버리지를 보고한 실행이 없습니다. |

브랜치의 추세에는 완료된 커밋만 포함됩니다.

## 성능 영향 {#performance-impact}

인스트루먼트된 코드는 약간 더 느리게 실행됩니다. Tuist는 여러분의 리포지토리 크레이트만 인스트루먼트합니다: 의존성은 일반 빌드와 동일하게 빌드되며 캐시에서 계속 제공됩니다. Tuist는 자체 크레이트의 두 변형을 타겟 디렉터리에 유지하므로, 코드가 변경되지 않는 한 커버리지 유무에 따른 실행 간 전환 시 다시 빌드되지 않습니다.

## 제한 사항 {#limitations}

- **타겟별 `rustflags`을 사용하는 custom `rustc-wrapper`.** 프로젝트가 자체 `rustc-wrapper`를 설정하면, Tuist는 대신 Cargo의 `build.rustflags`에 `-C instrument-coverage`를 추가합니다. Cargo 구성 파일의 `target.<triple>.rustflags` 항목이 이를 대체하므로, 해당 위치에 플래그를 직접 추가하세요. 테스트가 커버리지를 기록하지 않은 실행은 이를 명시합니다.
- **구성된 타겟 러너.** Tuist는 자체 러너를 통해 테스트 바이너리를 시작합니다. Cargo 구성 파일의 `target.<triple>.runner`가 이를 대체합니다: 실행의 커버리지는 여전히 업로드되지만, Tuist는 어떤 테스트 바이너리가 무엇을 실행했는지 확인할 수 없습니다. `CARGO_TARGET_<TRIPLE>_RUNNER` 환경 변수를 통해 설정된 러너는 계속 작동합니다.
- **포크에서 열린 풀 리퀘스트의 커버리지 없음.** 커버리지는 Tuist로 인증된 실행에서만 업로드되며, CI는 일반적으로 포크에서 열린 풀 리퀘스트에서 시크릿과 identity 토큰을 보유합니다.

## 커버리지 조회 {#querying}

대시보드의 **코드 커버리지** 페이지는 각 커밋의 수치, 패키지 및 파일과 각 파일이 포함하는 함수를 보여줍니다. 동일한 데이터는 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 서버</.localized_link>를 통해 에이전트에서도 사용할 수 있습니다.
