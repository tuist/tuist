---
{
  "title": "Rust 빌드 인사이트",
  "titleTemplate": ":title · 빌드 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist에서 느린 크레이트를 찾고, 빌드 성능을 비교하며, Rust 컴파일러 경고와 오류를 확인하세요."
}
---
# Rust 빌드 인사이트 {#rust-build-insights}

빌드 인사이트는 Cargo 빌드를 느리게 하는 요소를 찾고 팀 전체에 영향을 미치기 전에 회귀 문제를 포착하는 데 도움을 줍니다. 로컬 빌드와 CI를 비교하고, 빌드 시간 변화를 확인하며, 각 빌드에서 컴파일된 크레이트를 검사할 수 있습니다.

> [!IMPORTANT] Requirements
> - 프로젝트를 연결하고 인증하려면 <.localized_link href="/guides/get-started/rust-project">Rust 프로젝트 설정</.localized_link> 가이드를 따르세요.

## 빌드 보고하기 {#report-your-builds}

Tuist를 통해 일반적인 Cargo 명령어를 실행하세요:

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

mise를 사용한다면, 일반적인 `cargo` 명령어를 계속 사용할 수 있도록 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">Cargo 래퍼 구성</.localized_link>을 하세요. 인수, 툴체인 선택, 출력 및 종료 코드는 동일하게 유지됩니다.

## 빌드를 느리게 하는 요소 찾기 {#explore-your-builds}

대시보드의 **Builds → Build Runs**에서 빌드를 엽니다. 날짜, 환경 및 Rust 버전 필터를 사용하여 유사한 빌드를 비교하세요. 빌드와 캐시 카운터는 `tuist build cargo list`, `tuist build cargo show`, `GET /api/projects/{account_handle}/{project_handle}/cargo/builds` 및 `list_cargo_builds`, `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 도구</.localized_link>를 통해서도 확인할 수 있습니다.

**Overview**에서 **Compiler jobs**를 사용하여 느린 크레이트를 찾습니다. **Duration** 또는 **Started after**(Cargo 명령어 시작 이후 경과 시간)로 정렬하거나, 크레이트 이름 또는 루트 소스 파일로 검색합니다.

각 행은 하나의 크레이트에 대한 `rustc` 호출을 나타내며, 이는 여러 소스 파일을 포함할 수 있습니다. **Crate root**는 루트 소스 파일을 식별하며, 지속 시간은 해당 파일 하나가 아닌 전체 컴파일러 작업에 대한 것입니다. 크레이트는 서로 다른 타겟이나 구성으로 인해 여러 번 나타날 수 있습니다. 컴파일러 메시지는 **Warnings**과 **Errors**로 그룹화됩니다.

## 타이밍 읽기 {#timing-boundaries}

빌드 지속 시간은 전체 Cargo 명령어가 걸린 시간을 의미합니다. 컴파일러 작업은 병렬로 실행될 수 있으므로, 그 지속 시간을 합산해도 빌드 지속 시간이 되지 않습니다.

Cargo는 재빌드가 필요한 크레이트만 컴파일합니다. 이미 최신 상태인 크레이트는 컴파일러 목록에 나타나지 않습니다. Tuist의 컴파일레이션 캐시를 사용하면, 복원된 작업은 컴파일러 실행이 아닌 캐시 측정치에 표시됩니다.

Tuist는 빌드 스크립트를 별도로 측정하지 않으며 빌드 타임라인을 표시하지 않습니다. 대규모 빌드의 경우 처음 500개의 컴파일러 작업만 표시되며, 더 많은 작업이 기록된 경우 알림이 표시됩니다.

## 캐시 측정치 읽기 {#cache-measurements}

`tuist cargo`에는 Tuist CLI에 구현된 실험용 컴파일레이션 캐시가 포함되어 있습니다. 설정, Kura를 통한 원격 읽기 및 쓰기, 지원되는 컴파일 및 문제 해결 방법은 <.localized_link href="/guides/features/cache/rust">Rust 캐시 가이드</.localized_link>를 참조하세요.

프로젝트 사이드바에서 **Cargo Cache**를 열어 빌드 전반에 걸쳐 캐시 히트율과 기록된 전송, 지연 시간 및 처리량 측정치를 추적하세요. 날짜 또는 환경으로 필터링하거나, 일일 추세와 개별 빌드 히트율 간을 전환하거나, 최근 빌드를 열어 캐시 활동을 검사할 수 있습니다. 캐시 측정치가 없는 빌드는 0으로 계산되지 않고 사용 불가 상태로 남습니다.

빌드의 **Cache** 탭을 열어 작업 히트, 작업 미스, 히트율, 다운로드 및 업로드된 바이트를 확인하세요. 빌드가 캐시 데이터를 보고할 때 이 탭이 표시됩니다.

- **Cacheable Tasks**는 캐시된 출력을 재사용한 컴파일러 및 빌드 스크립트 작업을 보여줍니다. 작업을 검색하거나 필터링하고, 캐시 읽기/쓰기 지연 시간을 검사하며, 행을 확장하여 출력을 확인할 수 있습니다.
- **CAS Outputs**는 아티팩트 다운로드 및 업로드와 해당 크기, 지속 시간, 처리량을 보여줍니다. 차트는 완료된 전송만 계산하며, 이미 존재하는 아티팩트와 실패한 시도는 테이블에 남아 있습니다.

**Hit**은 캐시된 출력이 재사용되었음을 의미합니다. **Missed**는 작업이 대신 컴파일되었음을 의미합니다. 히트는 로컬과 원격으로 구분되지 않으며, CAS Outputs는 기록된 아티팩트 작업을 보여줍니다.

상세 기록이 누락되거나 불완전한 경우 페이지에 알림이 표시됩니다. 요약은 여전히 전체 빌드를 다룹니다. 추정된 컴파일러 작업 절감량은 **절약된 경과 빌드 시간이 아닙니다**.

> [!WARNING] Experimental compilation cache
> 첫 번째 버전은 입력과 출력이 검증된 레지스트리 리프 라이브러리만 캐시합니다. 워크스페이스 크레이트, 빌드 스크립트, 프로시저럴 매크로, 다른 크레이트에 대한 의존성, 증분 컴파일, 네이티브 링크 및 실행 파일은 정상적으로 빌드됩니다. 캐시 키는 절대 경로를 유지하므로, 서로 다른 체크아웃 경로 간의 재사용은 아직 지원되지 않습니다.

### 테스트를 실행하는 빌드 {#builds-that-run-tests}

`tuist cargo test`는 테스트를 포함한 전체 명령어의 지속 시간을 보고합니다. 또한 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>를 통해 doctests를 포함한 개별 테스트 결과를 보고합니다. 개별 테스트 결과는 **Tests** 아래에 표시되며, 명령어 지속 시간은 빌드 인사이트에 표시됩니다.

## 기타 컴파일러 도구 {#other-compiler-tools}

Tuist는 `RUSTC_WRAPPER`, `CARGO_BUILD_RUSTC_WRAPPER` 또는 Cargo 구성을 통해 구성된 기존 컴파일러 래퍼를 보존하며 `RUSTC_WORKSPACE_WRAPPER`를 그대로 둡니다. 기존 전역 래퍼가 있으면 Tuist의 캐시 및 컴파일러 옵저버가 비활성화됩니다. Tuist는 해당 래퍼가 실제로 rustc를 실행했는지 확인할 수 없기 때문입니다. 맞춤형 워크스페이스 래퍼 역시 보고서에 포함된 컴파일러 작업 수를 줄일 수 있습니다.

Tuist는 rustup을 통해 Cargo를 찾습니다. 맞춤형 설치를 사용하는 경우 `TUIST_CARGO_EXECUTABLE`를 실행 파일 경로로 설정하세요. 직접 툴체인 경로로 Cargo를 호출하면 mise의 래퍼를 우회합니다. Cargo 별칭은 `build`와 같은 내장 명령어를 대체할 수 없습니다.

Cargo의 야간 `-C` 옵션을 사용하는 경우, 대신 먼저 워크스페이스 디렉터리로 이동하세요. Tuist는 `-C` 명령어를 전달하지만 빌드 타이밍은 수집하지 않습니다.

## 문제 해결 {#troubleshooting}

빌드가 대시보드에 표시되지 않는 경우, 디버그 출력을 활성화하여 보고서가 전송되지 않은 이유를 확인하세요:

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

보고 기능은 빌드 결과를 변경하지 않습니다.
