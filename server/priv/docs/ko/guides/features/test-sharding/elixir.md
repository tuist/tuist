---
{
  "title": "Elixir 테스트 샤딩",
  "titleTemplate": ":title · 테스트 샤딩 · 기능 · 가이드 · Tuist",
  "description": "Tuist 테스트 샤딩을 사용하여 Elixir 프로젝트의 테스트를 여러 CI 러너에 분산하세요."
}
---
# Elixir 테스트 샤딩 {#elixir-test-sharding}

Tuist Hex 패키지는 Elixir 프로젝트의 테스트를 샤딩하는 기능을 내장하고 있습니다. Tuist 서버를 사용해 과거 타이밍 데이터를 기반으로 균형 잡힌 샤드 계획을 생성하며, 프로젝트를 한 번만 컴파일하여 모든 러너가 바로 테스트를 실행할 수 있도록 합니다.

> [!IMPORTANT] REQUIREMENTS
> - CI 샤드 작업을 구성하기 전에 <.localized_link href="/guides/get-started/elixir-project">공유 Elixir 설정</.localized_link>을 완료하세요

## 작동 방식 {#how-it-works}

테스트 샤딩은 두 단계 워크플로우를 따릅니다:

1. **빌드 단계:** Tuist는 테스트를 위해 프로젝트를 컴파일하고, 테스트 파일을 열거한 후 서버에 **샤드 계획**을 생성합니다. 서버는 지난 30일간의 과거 테스트 타이밍 데이터를 사용해 각 샤드가 대략 동일한 시간이 소요되도록 테스트를 분배합니다. 빌드 단계는 빌드를 업로드하고 CI 시스템이 병렬 러너를 생성하는 데 사용하는 **샤드 매트릭스**를 출력합니다.
2. **테스트 단계:** 각 CI 러너는 **샤드 인덱스**를 수신하고, 빌드를 다운로드한 후 해당 샤드에 할당된 테스트만 실행합니다.

테스트는 파일 단위로 분배됩니다: 파일 내의 모든 테스트는 동일한 샤드에서 실행됩니다. Tuist가 아직 확인하지 않은 테스트는 추정치를 사용하므로, 프로젝트의 초기 계획은 이후 계획보다 균형이 덜 잡힐 수 있습니다.

## 빌드 단계 {#build-phase}

`tuist.test.build` 작업을 사용하여 테스트 샤드를 준비하세요:

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-max 5
```

샤딩 작업을 호출하기 전에 공유 설정으로 설치된 별칭을 통해 컴파일하세요. 콜드 체크아웃 상태에서는 Tuist의 의존성 캐시가 복원할 기회를 갖기 전에 Mix가 `tuist.test.build`를 검색하면서 의존성을 컴파일할 수 있습니다. 명시적 컴파일은 샤딩 작업과 동일한 테스트 환경에서 실행됩니다.

이 작업은 다음과 같습니다:
1. 테스트 환경에서 프로젝트를 컴파일합니다
2. 과거 타이밍 데이터를 사용하여 Tuist 서버에 샤드 계획을 생성합니다
3. 샤드가 다시 컴파일하지 않도록 빌드를 업로드합니다
4. CI 시스템용 샤드 매트릭스를 출력합니다

### 빌드 옵션 {#build-options}

| 옵션 | 설명 |
|--------|-------------|
| `--shard-max <N>` | 최대 샤드 수 (기본값: 2) |
| `--shard-min <N>` | 최소 샤드 수 |
| `--shard-total <N>` | 범위 대신 정확한 샤드 수 |
| `--shard-max-duration <MS>` | 샤드당 목표 최대 지속 시간(밀리초) |
| `--shard-reference <REF>` | 샤드가 계획을 찾는 데 사용하는 이름 |
| `--no-upload` | 빌드를 업로드하지 않고 샤드를 계획합니다; 각 샤드는 자체적으로 컴파일합니다 |

다른 모든 인수는 `mix compile`로 전달됩니다.

샤드 참조는 CI 환경 변수(`GITHUB_RUN_ID`, `CI_PIPELINE_ID`, `CIRCLE_WORKFLOW_ID`, `BUILDKITE_BUILD_ID`)에서 자동으로 파생되거나 `TUIST_SHARD_REFERENCE` 환경 변수를 통해 명시적으로 설정할 수 있습니다. 이러한 제공자 외부에서는 빌드 단계와 한 파이프라인 실행의 샤드가 공유하는 값으로 설정해야 합니다. GitHub Actions에서는 참조에 실행 시도도 포함됩니다: 실패한 작업만 다시 실행할 때, 샤드 작업에서 새로운 참조를 파생하는 대신 원래 빌드 작업의 참조를 전달하세요.

## 테스트 단계 {#test-phase}

`TUIST_SHARD_INDEX`가 설정되면 패키지는 서버에서 샤드 할당을 가져오고, 빌드를 다운로드하며, 컴파일 없이 할당된 테스트 파일만 실행합니다. 콜드 러너에서는 작업을 호출하기 전에 SDK를 부트스트랩하고 경로를 로드하세요:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test
```

Mix의 워커 프로세스에서 SDK를 컴파일해도 부모 프로세스에는 로드되지 않습니다. 명시적인 `deps.loadpaths` 단계는 빌드를 다운로드하기 전에 나머지 의존성이 컴파일되는 것을 방지합니다. 이 단일 명령 형식은 프로젝트의 테스트 준비 별칭을 유지합니다. 설정 명령이 컴파일을 트리거하면 아래의 별도 설정 시퀀스를 사용하세요.

전달하는 테스트 파일이나 디렉터리는 샤드를 더욱 좁힙니다: 샤드에 속하면서도 선택 항목에 포함된 파일만 실행됩니다. 테스트가 없는 샤드는 성공적으로 종료됩니다.

모든 샤드의 결과는 대시보드에서 단일 테스트 실행으로 표시되며, **샤드** 섹션에 각 샤드의 소요 시간이 표시됩니다.

테스트 전에 설정을 실행해야 하는 경우, 애플리케이션을 시작하지 않고 먼저 빌드를 다운로드하세요:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
```

컴파일을 비활성화한 별도의 프로세스에서 설정을 실행하세요. 예를 들어, Ecto 프로젝트는 다음을 사용하여 데이터베이스를 생성하고 마이그레이션할 수 있습니다:

```sh
MIX_ENV=test mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
```

다른 프로젝트별 준비 작업은 이 단계에서 유지하세요. 부트스트랩 작업을 수행하기 전에 컴파일 별칭도 `--no-compile`를 준수해야 합니다: Mix는 목록 별칭의 마지막 작업에만 플래그를 전달하므로, 이전의 무조건적 `deps.compile`는 여전히 실행됩니다. <.localized_link href="/guides/features/cache/elixir-advanced#manual-compile-integration">수동 컴파일 통합</.localized_link>에서 가드된 별칭을 참조하세요.

그런 다음 샤드를 실행하기 전에 컴파일 없이 복원된 SDK를 로드하세요. 이는 소스가 다운로드된 빌드보다 최신일 때 경로 의존성이 컴파일되는 것도 방지합니다:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

두 명령 모두 동일한 샤드 참조가 필요합니다. `--prepare-only`는 업로드된 빌드가 필요하며, 준비된 애플리케이션 아티팩트가 없으면 `--no-download`가 실패합니다. `--no-download`는 재시도를 포함하여 프로젝트의 테스트 준비 별칭을 명시적으로 건너뛰며, 설정 단계를 건너뛸 때 알림을 출력합니다. 일반 실행은 `--no-compile --no-deps-check`를 전달하더라도 별칭을 유지합니다. 데이터베이스 마이그레이션을 별도 프로세스로 유지하면 마이그레이션 회귀 테스트가 해당 모듈을 직접 로드할 때 모듈 재정의 경고도 방지합니다.

다른 환경을 테스트할 때는 `--scheme` 라벨(예: `--scheme clickhouse-current` 또는 `--scheme clickhouse-floor`)과 같이 안정적인 라벨을 전달하세요. 다른 라벨을 가진 결과는 동일 구성의 불안정한 재실행으로 처리되지 않습니다.

### 샤드에 필요한 것 {#what-the-shards-need}

업로드된 빌드는 `_build/test` 디렉터리입니다. 각 샤드 러너는 여전히 다음이 필요합니다:
- 빌드 단계와 동일한 체크아웃
- 동일한 Elixir 및 Erlang/OTP 버전
- `mix deps.get`에서 가져온 의존성 소스

엄브렐라 프로젝트의 루트에서의 샤딩은 아직 지원되지 않습니다. 해당 애플리케이션 중 하나 내에서 두 단계를 모두 실행하세요.

## 지속적 통합 {#continuous-integration}

### GitHub Actions {#github-actions}

GitHub Actions에서는 빌드 단계가 샤드 인덱스를 단계의 `matrix` 출력에 기록합니다. 매트릭스 전략을 사용하여 샤드를 병렬로 실행하세요:

```yaml
name: Tests
on: [pull_request]

env:
  MIX_ENV: test
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    name: Build test shards
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - id: build
        run: mix tuist.test.build --shard-max 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.build.outputs.matrix).shard }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
      # Ecto example: keep all project-specific test preparation here.
      # The project's compile alias must honor --no-compile (see above).
      - run: mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
      - run: mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

### 다른 제공자 {#other-providers}

GitHub Actions 외의 환경에서는 빌드 단계가 계획을 `.tuist-shard-matrix.json`에 기록합니다:

```json
{
  "reference": "gitlab-1234",
  "shard_count": 2,
  "shards": [
    {
      "index": 0,
      "test_targets": ["MyApp.AccountsTest", "MyApp.CheckoutTest"],
      "estimated_duration_ms": 41000
    },
    {
      "index": 1,
      "test_targets": ["MyAppWeb.PageControllerTest"],
      "estimated_duration_ms": 39500
    }
  ]
}
```

`shard_count`를 사용하여 병렬 작업을 설정하고, 각 작업에 `0`부터 `shard_count - 1`까지의 `TUIST_SHARD_INDEX`를 할당하세요. Tuist가 참조를 자동으로 파생하지 않는 제공자의 경우, 모든 작업에 동일한 `TUIST_SHARD_REFERENCE`도 부여하세요.
