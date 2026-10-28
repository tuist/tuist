---
{
  "title": "Rust Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Cargo test results, including Rust doctests, in the Tuist dashboard."
}
---
# Rust 테스트 인사이트 {#rust-test-insights}

Tuist는 `cargo test`에서 단위 테스트, 통합 테스트 및 문서화 테스트를 포함한 개별 테스트 결과를 보고합니다. 별도의 Rust 종속성이나 추가 테스트 러너가 필요하지 않습니다.

> [!IMPORTANT] Requirements
> - <.localized_link href="/guides/get-started/rust-project">Rust 프로젝트 설정</.localized_link>을 따르세요.

## 테스트 실행 보고하기 {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

mise Cargo 래퍼가 구성된 상태에서는 계속 `cargo test`를 입력할 수 있습니다. Cargo는 여전히 일반적인 인수, 출력 및 종료 코드와 함께 테스트를 컴파일하고 실행합니다. 보고 실패가 테스트 결과에 영향을 주지 않습니다.

평소와 같이 패키지를 선택하거나 테스트를 필터링할 수 있습니다:

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuist가 추적하는 항목 {#what-is-tracked}

- 완료된 테스트 스위트에서 통과, 실패 및 무시된 테스트.
- 단위 테스트, 통합 테스트 및 문서화 테스트.
- 전체 스위트 실행 시간.
- 사용 가능한 브랜치, 커밋, CI 및 러너 메타데이터.

필터링된 테스트와 실패 후 실행되지 않은 테스트는 통과로 보고되지 않습니다. 결과는 대시보드의 **테스트** 아래에 표시됩니다.

## 패키지, 모듈 및 테스트 케이스 {#test-hierarchy}

Tuist는 Cargo 패키지 및 타겟별로 결과를 그룹화합니다. Rust 모듈 경로는 타겟 내의 개별 테스트를 그룹화합니다:

| 대시보드 라벨 | Rust 의미 | 예시 |
| --- | --- | --- |
| 모듈 | Cargo 패키지 및 타겟 | `store::api` |
| 테스트 스위트 | Rust 모듈 경로 | `api::authentication` |
| 테스트 케이스 | 개별 테스트 | `rejects_invalid_token` |

문서화 테스트는 `store::doctest/store`와 같은 별도의 모듈을 사용합니다. 이름에 소스 위치가 포함되므로 예시를 이동하면 식별자가 변경될 수 있습니다.

## 문서화 테스트 및 실행 시간 {#cargo-test}

문서화 테스트는 `compile_fail`, `should_panic` 및 `no_run` 예시를 포함한 일반적인 테스트 명령으로 실행됩니다. 문서화 테스트만 실행하려면:

```sh
tuist cargo test --doc
```

안정적인 libtest는 전체 스위트 시간을 보고하지만 개별 테스트 실행 시간은 보고하지 않습니다. 사용할 수 없는 타이밍은 사례별 실행 시간 기록 및 실행 시간 분석에서 제외되지만, 테스트 결과는 신뢰성 및 실행 횟수 계산에 여전히 기여합니다.

## 보고 제한 사항 {#reporting-limits}

개별 결과는 Cargo/libtest의 기본 출력에서 수집됩니다. `--no-run`, `--list`, quiet 또는 Cargo-verbose 출력, 대체 형식 또는 캡처되지 않은 테스트 출력을 사용하는 명령은 개별 테스트 보고 없이 정상적으로 실행됩니다. custom harnesses, 불완전한 요약, 모호한 타겟 할당 및 과도하게 큰 보고서는 업로드되지 않습니다.

워크스페이스 패키지에 동일한 이름의 통합 타겟이 있는 경우 `-p <package>`를 사용하여 하나를 선택하세요. 보고는 정확한 워크스페이스 패키지 이름을 지원합니다. 종속성 패키지, 버전 한정 선택기 및 글롭은 정상적으로 실행되지만 보고되지 않습니다. 절대 문서화 테스트 경로는 체크아웃 경로가 테스트 식별자에 포함되지 않도록 생략됩니다.

Tuist는 결과를 수집하면서 출력을 스트리밍합니다. 이는 자동 색상 감지에 영향을 줄 수 있습니다. Cargo 종료 후 출력 파이프를 열어 둔 백그라운드 프로세스는 보고서가 생략되게 할 수 있지만 Cargo의 종료 상태는 변경하지 않습니다.

## 신뢰성 및 선택 {#reliability-and-selection}

불안정한 테스트를 조사하려면 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">flaky test detection</.localized_link>을 사용하세요. 대시보드 격리는 현재 Cargo 테스트를 음소거하거나 건너뛰지 않습니다. 커버리지 수집, 커버리지 기반 테스트 선택 및 한 번 빌드 샤딩은 일반 Cargo 테스트 실행에서는 사용할 수 없습니다.

## 문제 해결 {#troubleshooting}

테스트 실행이 대시보드에 표시되지 않으면 디버그 출력을 활성화하여 보고서가 전송되지 않은 이유를 확인하세요:

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
