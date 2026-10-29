---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Test sharding · Features · Guides · Tuist",
  "description": "Distribute tests in a Tuist-generated Xcode project across multiple CI runners with Tuist Test Sharding."
}
---
# 생성된 Xcode 프로젝트 {#generated-xcode-project-test-sharding}

생성된 프로젝트의 테스트 샤딩은 빌드 및 테스트 단계 모두에서 `tuist test`를 사용합니다.

## 작동 방식 {#how-it-works}

테스트 샤딩은 두 단계 워크플로를 따릅니다:

1. **빌드 단계:** Tuist는 빌드된 `.xctestrun` 파일에서 테스트 모듈을 읽고 서버에 **샤드 계획**을 생성합니다. 서버는 지난 30일간의 히스토리컬 테스트 타이밍 데이터를 사용하여 각 샤드가 대략 동일한 시간이 소요되도록 테스트를 샤드에 분배합니다. 빌드 단계는 CI 시스템이 병렬 러너를 생성하는 데 사용하는 **샤드 매트릭스**를 출력합니다.
2. **테스트 단계:** 각 지속적 통합(CI) 러너는 **샤드 인덱스**와 정확한 **샤드 계획 식별자**를 받은 후, 해당 계획의 테스트 선택을 실행합니다.

`--shard-granularity suite`가 사용될 때, Tuist는 빌드 단계 동안 스위트 목록을 열거하기 위해 모든 테스트 번들을 부팅하지 않습니다. 대신 현재 `.xctestrun` 파일이 모듈 목록을 제공하고, 서버는 모듈별로 알려진 스위트를 선택합니다: 각 모듈에 대해 빌드 중인 브랜치에서 최근 몇 차례의 CI 실행에 포함된 스위트들의 합집합을 구합니다. 만약 해당 브랜치에 모듈의 히스토리가 없다면, 서버는 프로젝트의 기본 브랜치를 폴백으로 사용합니다. 최신 실행이 아닌 여러 실행을 읽는 것이 중요한 이유는, 샤딩된 실행은 각 샤드가 완료될 때마다 샤드당 하나의 테스트 실행을 업로드하므로 가장 최근 실행에는 지금까지 수집된 모듈의 일부만 포함되기 때문이며, 또한 최신 브랜치 실행에서 건너뛴 스위트가 선택적 테스트 실행에서 숨겨지지 않도록 하기 때문입니다. 서버는 여전히 지속 시간 추정을 위해 지난 30일간의 스위트 타이밍을 사용합니다.

Tuist는 요청된 샤드 수에 걸쳐 알려진 스위트들을 균형 있게 분배하고 마지막 샤드를 catch-all로 사용합니다. 예를 들어, `--shard-total 5`는 샤드 인덱스 `0`부터 `4`까지를 생성하며, 샤드 인덱스 `4`가 catch-all 역할을 합니다. 일반 샤드는 할당된 스위트에 대해 `-only-testing` 옵션과 함께 실행됩니다. 마지막 샤드는 `-only-testing` 없이 실행되며 이전 샤드에 할당된 모든 스위트에 대해 `-skip-testing`를 전달하므로, 새로 추가된 스위트, 이름이 변경된 스위트 또는 히스토리컬 인벤토리에 없는 스위트도 실행합니다. 모듈 단위는 `.xctestrun` 파일이 모듈 목록을 제공하므로 catch-all이 필요하지 않습니다.

## 빌드 단계 {#build-phase}

프로젝트를 생성하고, 테스트를 빌드한 후, 샤드 계획을 생성하세요:

```sh
tuist test --build-only --shard-total 5
```

`--build-only` 플래그는 Tuist에게 테스트를 실행하지 않고 빌드하도록 지시합니다. `--build-only` 없이 샤드 계획 플래그(`--shard-min`/`--shard-max`/`--shard-total`)를 전달하면 Tuist는 오류를 발생시킵니다.

이 명령어는 다음을 수행합니다:
1. 매니페스트로부터 Xcode 프로젝트를 생성합니다
2. 테스트를 빌드합니다
3. 히스토리컬 타이밍 데이터를 사용하여 Tuist 서버에 샤드 계획을 생성합니다
4. `.xctestproducts` 번들을 업로드하거나 샤드 러너가 사용할 샤드 아카이브를 작성합니다
5. CI 시스템을 위한 샤드 매트릭스를 출력합니다
6. 샤드 러너가 프로젝트를 다시 생성할 필요가 없도록 <.localized_link href="/guides/features/selective-testing">선택적 테스트</.localized_link> 그래프를 유지합니다(해당되는 경우)

### 빌드 옵션 {#build-options}

| 플래그 | 환경 변수 | 설명 |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | 최대 샤드 수. 샤드 수를 제한하기 위해 `--shard-max-duration`와 함께 사용됩니다 |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | 최소 샤드 수 |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | 정확한 샤드 수(`--shard-min`/`--shard-max`와 상호 배타적). 스위트 단위에서는 마지막 샤드가 catch-all 역할을 합니다 |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | 샤드당 목표 최대 지속 시간(밀리초) |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module`(기본값)은 전체 테스트 모듈을 샤드에 분배합니다; `suite`는 더 세밀한 균형을 위해 개별 테스트 클래스를 분배합니다 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 샤드 계획의 고유 식별자(지원되는 CI 제공업체에서 자동 파생) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Tuist가 테스트 제품을 원격 스토리지에 업로드하는 대신 최적화된 샤드 아카이브를 작성하는 경로 |

## 테스트 단계 {#test-phase}

각 샤드 러너는 할당된 테스트를 실행합니다:

```sh
tuist test --without-building
```

`--without-building` 플래그는 Tuist에게 다시 빌드하는 대신 이전에 빌드된 제품을 사용하여 테스트를 실행하도록 지시합니다. `--without-building` 없이 `TUIST_SHARD_INDEX` / `--shard-index`가 설정되면 Tuist는 오류를 발생시킵니다.

### 테스트 옵션 {#test-options}

| 플래그 | 환경 변수 | 설명 |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | 실행할 샤드의 0 기반 인덱스 |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | 빌드 단계에서 생성된 정확한 샤드 계획 식별자. 생성된 제공업체 출력에는 이 값이 자동으로 포함됩니다 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 샤드 계획의 고유 식별자(지원되는 CI 제공업체에서 자동 파생) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | 로컬로 관리되는 샤드 아카이브의 경로; Tuist는 원격 스토리지에서 테스트 제품을 다운로드하는 대신 이를 추출합니다 |

Tuist는 `.xctestproducts` 번들을 다운로드하고 해당 샤드에 할당된 테스트만 포함하도록 필터링합니다.

> [!TIP]
> **선택적 테스트**
>
> 테스트 샤딩은 <.localized_link href="/guides/features/selective-testing">선택적 테스트</.localized_link>와 원활하게 작동합니다. 선택적 테스트 그래프는 빌드 단계에서 유지되고 각 샤드에 대해 복원되므로, 러너가 프로젝트를 다시 생성할 필요가 없습니다.

## 지속적 통합 {#continuous-integration}

Tuist는 다음 CI 제공업체를 자동으로 감지합니다:

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

다른 제공업체의 경우, 병렬 작업을 설정하려면 `.tuist-shard-matrix.json` 파일을 참조하세요.

### GitHub Actions {#github-actions}

매트릭스 전략을 사용하여 샤드를 병렬로 실행하세요:

```yaml
name: Tests
on: [pull_request]

jobs:
  build:
    name: Build test shards
    runs-on: macos-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - id: build
        run: tuist test --build-only --shard-total 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    if: toJSON(fromJSON(needs.build.outputs.matrix).shard) != '[]'
    runs-on: macos-latest
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.build.outputs.matrix) }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
      TUIST_SHARD_PLAN_ID: ${{ matrix.shard_plan_id }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist test --without-building
```

### GitLab CI {#gitlab-ci}

Tuist는 [하위 파이프라인](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines)으로 트리거할 수 있는 `.tuist-shard-child-pipeline.yml`을 생성합니다. 생성된 샤드 작업이 확장하는 `.tuist-shard` 템플릿 작업을 정의하세요:

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test

build-shards:
  stage: build
  tags: [macos]
  script:
    - tuist auth login
    - tuist test --build-only --shard-total 5
  artifacts:
    paths:
      - .tuist-shard-child-pipeline.yml

test-shards:
  stage: test
  needs: [build-shards]
  trigger:
    include:
      - artifact: .tuist-shard-child-pipeline.yml
        job: build-shards
    strategy: depend
```

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  tags: [macos]
  script:
    - tuist auth login
    - tuist test --without-building
```

### CircleCI {#circleci}

Tuist는 [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation)용 매개변수가 포함된 `.tuist-shard-continuation.json`을 생성합니다. `shard-plan-id` 매개변수는 계속되는 구성에서 선언되어야 합니다:

```yaml
# .circleci/config.yml
version: 2.1
setup: true

orbs:
  continuation: circleci/continuation@1

jobs:
  build-shards:
    macos:
      xcode: "16.0"
    steps:
      - checkout
      - run:
          name: Build and plan shards
          command: |
            tuist auth login
            tuist test --build-only --shard-total 5
      - continuation/continue:
          configuration_path: .circleci/continue-config.yml
          parameters: .tuist-shard-continuation.json

workflows:
  setup:
    jobs:
      - build-shards
```

```yaml
# .circleci/continue-config.yml
version: 2.1

parameters:
  shard-indices:
    type: string
    default: ""
  shard-count:
    type: integer
    default: 0
  shard-plan-id:
    type: string
    default: ""

jobs:
  test-shard:
    macos:
      xcode: "16.0"
    parameters:
      shard-index:
        type: integer
    steps:
      - checkout
      - run:
          name: Run shard
          command: |
            export TUIST_SHARD_INDEX=<< parameters.shard-index >>
            export TUIST_SHARD_PLAN_ID=<< pipeline.parameters.shard-plan-id >>
            tuist auth login
            tuist test --without-building

workflows:
  test:
    jobs:
      - test-shard:
          matrix:
            parameters:
              shard-index: [<< pipeline.parameters.shard-indices >>]
```

### Buildkite {#buildkite}

Tuist는 샤드당 하나의 단계가 포함된 `.tuist-shard-pipeline.yml`을 생성합니다. `buildkite-agent pipeline upload`를 사용하여 업로드하세요:

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      tuist test --build-only --shard-total 5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
    agents:
      queue: macos
```

각 생성된 단계에는 환경에 `TUIST_SHARD_INDEX` 및 `TUIST_SHARD_PLAN_ID`가 설정되어 있습니다. 공유 스크립트를 사용하여 각 샤드 단계에 테스트 명령을 추가하세요:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic은 동적 매트릭스 작업을 지원하지 않으므로, 샤드별로 별도의 워크플로를 정의하세요. Tuist는 빌드 워크플로 내에서 사용할 수 있도록 `TUIST_SHARD_MATRIX` 및 `TUIST_SHARD_COUNT`를 `CM_ENV` 파일에 기록합니다. Codemagic의 `CM_ENV`는 워크플로 범위를 가지므로, 정확한 샤드 계획 식별자는 워크플로 경계를 넘지 않습니다; 테스트 워크플로는 참조 기반 샤드 조회로 대체됩니다:

```yaml
# codemagic.yaml
workflows:
  build-shards:
    name: Build test shards
    instance_type: mac_mini_m2
    environment:
      xcode: latest
    scripts:
      - name: Build and plan shards
        script: |
          tuist auth login
          tuist test --build-only --shard-total 5

  test-shard-0: &shard-workflow
    name: "Shard #0"
    instance_type: mac_mini_m2
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 0
    scripts:
      - name: Run shard
        script: |
          tuist auth login
          tuist test --without-building

  test-shard-1:
    <<: *shard-workflow
    name: "Shard #1"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 1

  test-shard-2:
    <<: *shard-workflow
    name: "Shard #2"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 2

  test-shard-3:
    <<: *shard-workflow
    name: "Shard #3"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 3

  test-shard-4:
    <<: *shard-workflow
    name: "Shard #4"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 4
```

### Bitrise {#bitrise}

Bitrise에서는 Tuist가 `BITRISE_DEPLOY_DIR`에 `.tuist-shard-matrix.json`(`shard_plan_id` 포함)를 작성하여 다운스트림 파이프라인 단계에서 빌드 아티팩트로 사용할 수 있게 합니다. 각 테스트 워크플로는 `envman`를 사용하여 다운로드한 아티팩트에서 계획 ID를 추출하므로 테스트 명령의 환경에 전달됩니다:

```yaml
# bitrise.yml
pipelines:
  test-pipeline:
    stages:
      - build-stage: {}
      - test-stage: {}

stages:
  build-stage:
    workflows:
      - build-shards: {}
  test-stage:
    workflows:
      - test-shard-0: {}
      - test-shard-1: {}
      - test-shard-2: {}
      - test-shard-3: {}
      - test-shard-4: {}

workflows:
  build-shards:
    steps:
      - script:
          title: Build and plan shards
          inputs:
            - content: |
                tuist auth login
                tuist test --build-only --shard-total 5
      - deploy-to-bitrise-io: {}

  test-shard-0: &shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 0
    steps:
      - pull-intermediate-files: {}
      - script:
          title: Set shard plan ID from artifact
          inputs:
            - content: |
                PLAN_ID=$(jq -r '.shard_plan_id' "$BITRISE_DEPLOY_DIR/.tuist-shard-matrix.json")
                envman add --key TUIST_SHARD_PLAN_ID --value "$PLAN_ID"
      - script:
          title: Run shard
          inputs:
            - content: |
                tuist auth login
                tuist test --without-building
  test-shard-1:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 1
  test-shard-2:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 2
  test-shard-3:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 3
  test-shard-4:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 4
```

> [!TIP]
> Bitrise는 런타임 시 동적 병렬 작업 생성을 지원하지 않습니다. 파이프라인 단계에서 고정된 수의 샤드 워크플로를 정의하세요 — 단계 내의 워크플로는 자동으로 병렬로 실행됩니다.

## 공유 볼륨 {#shared-volumes}

기본적으로 빌드 단계는 `.xctestproducts` 번들을 원격 스토리지에 업로드하고 각 샤드 러너가 이를 다운로드합니다. CI 제공업체가 **공유 볼륨**(작업 간에 마운트되는 영구 스토리지)을 지원하는 경우, 공유 파일 시스템을 통해 테스트 제품을 전달함으로써 이 업로드/다운로드를 완전히 건너뛸 수 있습니다.

이는 특히 대형 테스트 번들의 경우 샤드 시작 시간을 크게 줄일 수 있습니다.

공유 볼륨을 사용하려면:

1. **빌드 단계**에서 공유 볼륨을 가리키는 `-testProductsPath`(`--` 이후)를 전달하고 원격 업로드를 건너뛰기 위해 `--shard-skip-upload`를 추가하세요:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. **테스트 단계**에서 동일한 `-testProductsPath`를 전달하여 Tuist가 테스트 제품을 다운로드하는 대신 로컬에서 읽도록 하세요:

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| 플래그 | 환경 변수 | 설명 |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | 테스트 제품 번들을 원격 스토리지에 업로드하지 않음 |

## 자체 관리 아티팩트 {#self-managed-artifacts}

CI 제공업체에 이미 아티팩트 업로드 및 다운로드 단계가 있는 경우, Tuist가 아카이브 및 추출을 처리하고 CI가 전송을 처리하도록 할 수 있습니다.

1. **빌드 단계**에서 `--shard-archive-path`를 전달하여 Tuist가 테스트 제품을 업로드하는 대신 최적화된 샤드 아카이브를 로컬에 작성하도록 하세요:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. CI의 기본 아티팩트 단계를 사용하여 해당 아카이브를 업로드하세요.

3. 각 **테스트 단계** 작업에서 아카이브를 다운로드하고 동일한 경로를 Tuist에 다시 전달하세요:

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

`--shard-archive-path`가 설정되면 Tuist는 원격 테스트 제품 전송을 건너뛰고 로컬 아카이브를 대신 사용합니다. `--shard-skip-upload`도 함께 전달하면 아카이브 경로가 우선 적용됩니다.

실행할 테스트가 없는 경우(예: 선택적 테스트로 모든 테스트 대상이 건너뛰어진 경우), 빌드 단계는 빈 샤드 매트릭스를 출력하고 아카이브를 작성하지 않습니다. 매트릭스에 샤드가 있을 때만 업로드 단계를 실행하세요.

> [!IMPORTANT]
> 동시 실행 간 충돌을 방지하기 위해 워크플로 실행마다 고유한 경로를 사용하세요(예: CI 실행 ID 포함). 또한 러너에 오래된 데이터가 누적되지 않도록 샤딩 완료 후 샤드 아카이브를 정리해야 합니다.

### 네임스페이스 {#namespace}

[네임스페이스](https://namespace.so) 러너는 GitHub Actions 아티팩트와 잘 연동됩니다. 빌드 작업이 샤드 아카이브를 로컬에 작성하도록 `TUIST_TEST_SHARD_ARCHIVE_PATH`를 한 번 설정하고, 이를 업로드한 후 각 샤드 작업에서 `tuist test`를 실행하기 전에 다운로드하세요:

```yaml
name: Tests
on: [pull_request]

env:
  TUIST_TEST_SHARD_ARCHIVE_PATH: /tmp/shards/${{ github.run_id }}/bundle.aar

jobs:
  build:
    name: Build test shards
    runs-on: namespace-profile-default-macos
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - id: build
        run: tuist test --build-only --shard-total 5
      - if: toJSON(fromJSON(steps.build.outputs.matrix).shard) != '[]'
        uses: actions/upload-artifact@v4
        with:
          name: test-shard-archive
          path: ${{ env.TUIST_TEST_SHARD_ARCHIVE_PATH }}
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    if: toJSON(fromJSON(needs.build.outputs.matrix).shard) != '[]'
    runs-on: namespace-profile-default-macos
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.build.outputs.matrix) }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
      TUIST_SHARD_PLAN_ID: ${{ matrix.shard_plan_id }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - uses: actions/download-artifact@v4
        with:
          name: test-shard-archive
          path: /tmp/shards/${{ github.run_id }}
      - run: tuist test --without-building
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}
```
