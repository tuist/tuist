---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute Cargo test targets across CI workers using historical test durations."
}
---
# Rust 테스트 샤딩 {#rust-test-sharding}

Tuist는 과거 타겟 실행 시간을 기반으로 CI 워커 간에 Cargo 테스트 타겟을 분배합니다. 단위 테스트 타겟, 통합 테스트 타겟 및 각 라이브러리의 doctests는 별도의 모듈로 처리됩니다. 하나의 타겟 내 테스트는 함께 유지됩니다.

> [!IMPORTANT] Requirements
> - <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>를 구성하고 계획 작업 및 워커에서 CLI를 인증하세요.
> - 워크스페이스에서 `-p <package>`를 사용하여 단일 패키지를 선택하세요. 다중 패키지 샤딩은 지원되지 않습니다.
> - 모든 작업에서 동일한 리비전, Rust 툴체인, 패키지 선택, 기능 및 테스트 필터를 사용하세요.

## 계획 생성 {#create-a-plan}

테스트를 실행하지 않고 타겟을 컴파일하고 열거하기 위해 `--no-run`에 샤드 수를 추가하세요:

```sh
TUIST_SHARD_REFERENCE=my-ci-run tuist cargo test -p store --no-run --shard-max 4
```

이 명령은 `shard_plan_id`과 0부터 시작하는 `shards` 배열을 포함한 JSON을 출력합니다. GitHub Actions에서는 `shard-plan-id`와 `shards`를 `GITHUB_OUTPUT`에도 기록합니다. 명시적 참조가 없으면 Tuist는 지원되는 CI 환경에서 참조를 파생시킵니다.

| 옵션 | 설명 |
| --- | --- |
| `--shard-max N` | 최대 샤드 수 |
| `--shard-min N` | 최소 샤드 수 |
| `--shard-total N` | 사용 가능한 타겟까지의 정확한 개수 |
| `--shard-max-duration N` | 밀리초 단위의 대상 최대 샤드 지속 시간 |

`--shard-total`만 단독으로 사용하거나 `--shard-min`와 `--shard-max`를 결합하세요. 과거 실행 시간이 없으면 플래너는 기본 타겟 추정치를 사용합니다. 샤딩 옵션이 없는 일반 `--no-run`는 빌드 전용 명령으로 남습니다.

## 각 샤드 실행 {#execute-each-shard}

각 워커에서 계획 ID와 샤드 인덱스를 설정한 후 동일한 Cargo 테스트 인수를 사용하세요:

```sh
TUIST_SHARD_PLAN_ID=<plan-id> TUIST_SHARD_INDEX=0 tuist cargo test -p store
```

또는 계획 ID를 전달하는 대신 `TUIST_SHARD_REFERENCE`를 계획 작업의 참조로 설정하세요. Tuist는 할당 정보를 가져와 Cargo에게 해당 타겟만 실행하도록 요청합니다. 유효하지 않거나 호환되지 않는 할당은 모든 테스트를 실행하는 대신 명령을 실패시킵니다. 빈 할당은 테스트를 실행하지 않습니다. 워커의 결과는 Test Insights에서 계획에 연결되며, <.localized_link href="/guides/features/test-insights/flaky-tests/rust#quarantine">격리</.localized_link>는 각 샤드 내에서 적용됩니다.

## 제한 사항 {#limits}

이는 타겟 수준 샤딩이며, 한 번 빌드하여 배포하는 방식이 아닙니다. 각 워커는 소스 체크아웃이 필요하며 자체 타겟을 빌드합니다. <.localized_link href="/guides/features/cache/rust">Cargo 컴파일 캐시</.localized_link>는 적절한 컴파일 출력을 재사용할 수 있습니다. Tuist는 테스트 실행 파일을 업로드하거나 다른 Rust 테스트 러너를 요구하지 않습니다.

샤딩에는 선택된 패키지 하나가 필요합니다. 다중 패키지 명령을 좁히면 Cargo의 통합 종속성 기능이 변경될 수 있으므로, Tuist는 다른 기능 그래프로 테스트를 실행하는 대신 이를 거부합니다. 다중 패키지 샤딩이 지원될 때까지 각 패키지를 별도로 계획하세요.

샤딩에는 표준 libtest 하네스와 캡처된 기본 출력이 필요합니다. Quiet, verbose, alternate-format, uncaptured-output 및 custom-harness 명령은 거부됩니다. Cargo가 타겟을 고유하게 식별할 수 없는 경우 `-p <package>`를 사용하여 정확한 워크스페이스 패키지를 선택하세요. 종속성 패키지, 버전 한정 선택기, 패키지/타겟 이름 글롭 및 Cargo의 야간 `-C` 옵션은 샤딩에서 지원되지 않습니다. 계획 단계와 실행 단계 간 테스트 선택을 동일하게 유지하세요.
