---
{
  "title": "Gradle 테스트 샤딩",
  "titleTemplate": ":title · 테스트 샤딩 · 기능 · 가이드 · Tuist",
  "description": "Tuist 테스트 샤딩으로 여러 CI 러너에 Gradle 테스트를 분산하세요."
}
---
# Gradle 테스트 샤딩 {#gradle-test-sharding}

Tuist Gradle 플러그인에는 테스트 샤딩을 위한 기본 지원이 포함되어 있습니다. 이전 CI 실행에서 Tuist가 기록한 프로젝트의 테스트 작업에 대한 테스트 스위트 계획을 수립하고, Tuist 서버를 사용하여 과거 타이밍 데이터를 기반으로 균형 잡힌 샤드 계획을 생성합니다.

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/features/test-insights/gradle">테스트 인사이트</.localized_link>를 구성해야 합니다

## 작동 방식 {#how-it-works}

테스트 샤딩은 두 단계 워크플로를 따릅니다:

1. **빌드 단계:** Tuist는 서버에서 프로젝트에 대해 기록된 테스트 스위트를 기반으로 **샤드 계획**을 생성합니다. 서버는 지난 30일간의 과거 테스트 타이밍 데이터를 사용하여 각 샤드가 대략 동일한 시간이 소요되도록 테스트를 샤드에 분배합니다. 빌드 단계는 CI 시스템이 병렬 러너를 생성하는 데 사용하는 **샤드 매트릭스**를 출력합니다.
2. **테스트 단계:** 각 CI 러너는 **샤드 인덱스**를 수신하고 해당 샤드에 할당된 테스트만 실행합니다. 마지막 샤드는 다른 샤드에 할당되지 않은 모든 테스트 스위트도 실행합니다.

## 빌드 단계 {#build-phase}

`tuistPrepareTestShards` 작업을 사용하여 테스트 샤드를 준비하세요:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5
```

이 작업은 다음을 수행합니다:
1. 컴파일하지 않고 샤딩할 테스트 작업이 있는 프로젝트를 찾습니다
2. 지난 30일 동안 해당 프로젝트에 대해 기록된 테스트 스위트와 타이밍을 바탕으로 Tuist 서버에서 샤드 계획을 생성합니다
3. CI 시스템을 위한 샤드 매트릭스를 출력합니다

아직 테스트 스위트가 기록되지 않은 경우(예: 첫 번째 실행 시), 계획은 모든 테스트를 실행하는 단일 샤드로 구성됩니다.

### 빌드 옵션 {#build-options}

Gradle 프로젝트 속성을 통해 샤딩을 구성하세요:

| 속성 | 설명 |
|----------|-------------|
| `-PtuistShardMax=<N>` | 최대 샤드 수(기본값: 2) |
| `-PtuistShardMin=<N>` | 최소 샤드 수 |
| `-PtuistShardMaxDuration=<MS>` | 샤드당 목표 최대 지속 시간(밀리초 단위) |
| `-PtuistShardTestTask=<NAME>` | 테스트가 샤딩되는 테스트 작업(예: `testDebugUnitTest`). 기본적으로 빌드의 모든 테스트 작업이 대상입니다 |

여러 빌드 변형(variant)이 있는 Android 프로젝트는 변형당 하나의 단위 테스트 작업을 가집니다. 샤드가 실행할 변형에 `-PtuistShardTestTask`를 설정하여 해당 변형이 있는 프로젝트만 계획에 포함되도록 하세요:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5 \
  -PtuistShardTestTask=testDebugUnitTest
```

샤드 참조는 CI 환경 변수(`GITHUB_RUN_ID`, `CI_PIPELINE_ID` 등)에서 자동으로 파생되거나 `TUIST_SHARD_REFERENCE` 환경 변수를 통해 명시적으로 설정할 수 있습니다.

## 테스트 단계 {#test-phase}

각 샤드 러너는 표준 `test` 작업을 사용하여 할당된 테스트를 실행합니다. `TUIST_SHARD_INDEX`가 설정되면 플러그인이 서버에서 샤드 할당을 자동으로 가져오고 할당된 테스트 스위트만 포함하도록 테스트 실행을 필터링합니다. 샤드에 할당된 스위트가 없는 프로젝트의 테스트 작업은 건너뜁니다.

마지막 샤드는 모든 테스트 작업을 실행하고 다른 샤드에 할당된 스위트는 제외하므로, 새로 추가된 스위트처럼 아직 기록된 실행이 없는 스위트도 여전히 실행됩니다.

```sh
TUIST_SHARD_INDEX=0 ./gradlew test
```

빌드 단계에서 `-PtuistShardTestTask`를 설정했다면, 각 샤드에서도 동일한 작업을 실행하세요(예: `./gradlew testDebugUnitTest`).

## 지속적 통합(CI) {#continuous-integration}

Tuist는 다음 CI 제공자를 자동으로 감지합니다:

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

다른 제공자의 경우, 병렬 작업을 설정하려면 `.tuist-shard-matrix.json` 파일을 참조하세요.

### GitHub Actions {#github-actions}

매트릭스 전략을 사용하여 샤드를 병렬로 실행하세요:

```yaml
name: Tests
on: [pull_request]

jobs:
  build:
    name: Build test shards
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v4
      - run: tuist auth login
      - id: build
        run: ./gradlew tuistPrepareTestShards -PtuistShardMax=5

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
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v4
      - run: tuist auth login
      - run: ./gradlew test
```

### GitLab CI {#gitlab-ci}

Tuist는 [하위 파이프라인](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines)으로 트리거할 수 있는 `.tuist-shard-child-pipeline.yml`을 생성합니다. 생성된 샤드 작업이 확장할 `.tuist-shard` 템플릿 작업을 정의하세요:

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test

build-shards:
  stage: build
  script:
    - tuist auth login
    - ./gradlew tuistPrepareTestShards -PtuistShardMax=5
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

하위 파이프라인에는 `.tuist-shard` 작업 템플릿이 필요합니다:

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  script:
    - tuist auth login
    - ./gradlew test
```

### CircleCI {#circleci}

Tuist는 [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation)용 매개변수가 포함된 `.tuist-shard-continuation.json`을 생성합니다:

```yaml
# .circleci/config.yml
version: 2.1
setup: true

orbs:
  continuation: circleci/continuation@1

jobs:
  build-shards:
    docker:
      - image: cimg/openjdk:17.0
    steps:
      - checkout
      - run:
          name: Build and plan shards
          command: |
            tuist auth login
            ./gradlew tuistPrepareTestShards -PtuistShardMax=5
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

jobs:
  test-shard:
    docker:
      - image: cimg/openjdk:17.0
    parameters:
      shard-index:
        type: integer
    steps:
      - checkout
      - run:
          name: Run shard
          command: |
            export TUIST_SHARD_INDEX=<< parameters.shard-index >>
            tuist auth login
            ./gradlew test

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
      ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
```

각 생성된 단계에는 환경에 `TUIST_SHARD_INDEX`가 설정되어 있습니다. 공유 스크립트를 사용하여 각 샤드 단계에 테스트 명령을 추가하세요:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
./gradlew test
```

### Codemagic {#codemagic}

Codemagic은 동적 매트릭스 작업을 지원하지 않으므로 샤드별로 별도의 워크플로를 정의해야 합니다. Tuist는 각 워크플로 내에서 사용할 수 있도록 `CM_ENV` 파일에 `TUIST_SHARD_MATRIX`와 `TUIST_SHARD_COUNT`를 기록합니다:

```yaml
# codemagic.yaml
workflows:
  build-shards:
    name: Build test shards
    instance_type: linux_x2
    environment:
      java: 17
    scripts:
      - name: Build and plan shards
        script: |
          tuist auth login
          ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test-shard-0: &shard-workflow
    name: "Shard #0"
    instance_type: linux_x2
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 0
    scripts:
      - name: Run shard
        script: |
          tuist auth login
          ./gradlew test

  test-shard-1:
    <<: *shard-workflow
    name: "Shard #1"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 1

  test-shard-2:
    <<: *shard-workflow
    name: "Shard #2"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 2

  test-shard-3:
    <<: *shard-workflow
    name: "Shard #3"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 3

  test-shard-4:
    <<: *shard-workflow
    name: "Shard #4"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 4
```

### Bitrise {#bitrise}

Bitrise에서는 Tuist가 `BITRISE_DEPLOY_DIR`에 `.tuist-shard-matrix.json`를 작성하여 다운스트림 파이프라인 단계에서 빌드 아티팩트로 사용할 수 있게 합니다. 미리 정의된 병렬 워크플로와 함께 Bitrise Pipelines를 사용하세요:

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
                ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test-shard-0: &shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 0
    steps:
      - script:
          title: Run shard
          inputs:
            - content: |
                tuist auth login
                ./gradlew test
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
> Bitrise는 런타임에 동적 병렬 작업 생성을 지원하지 않습니다. 파이프라인 단계에 고정된 수의 샤드 워크플로를 정의하세요. 단계 내의 워크플로는 자동으로 병렬로 실행됩니다.
