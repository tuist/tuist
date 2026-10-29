---
{
  "title": "Gradle Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute Gradle tests across multiple CI runners with Tuist Test Sharding."
}
---
# Сегментирование тестов Gradle {#gradle-test-sharding}

Плагин Tuist для Gradle включает встроенную поддержку сегментирования тестов. Он планирует наборы тестов, которые Tuist записал в предыдущих запусках CI для задач тестирования ваших проектов, и использует сервер Tuist для создания сбалансированных планов сегментов на основе исторических данных о времени выполнения.

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/features/test-insights/gradle">Аналитика тестов</.localized_link> должна быть настроена

## Как это работает {#how-it-works}

Сегментирование тестов следует двухэтапному рабочему процессу:

1. **Этап сборки:** Tuist создает **план сегментов** на сервере на основе наборов тестов, записанных для ваших проектов. Сервер использует исторические данные о времени выполнения тестов за последние 30 дней, чтобы распределить тесты по сегментам так, чтобы каждый сегмент занимал примерно одинаковое количество времени. Этап сборки выводит **матрицу сегментов**, которую ваша система CI использует для запуска параллельных исполнителей.
2. **Этап тестирования:** Каждый исполнитель CI получает **индекс сегмента** и выполняет только те тесты, которые назначены этому сегменту. Последний сегмент также запускает каждый набор тестов, который не назначен другому сегменту.

## Этап сборки {#build-phase}

Подготовьте сегменты тестов с помощью задачи `tuistPrepareTestShards`:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5
```

Эта задача:
1. Находит проекты, имеющие задачу тестирования для сегментирования, без их компиляции
2. Создает план сегментов на сервере Tuist на основе наборов тестов и временных меток, записанных для этих проектов за последние 30 дней
3. Выводит матрицу сегментов для вашей системы CI

Если наборы тестов еще не записаны, например, при первом запуске, план содержит один сегмент, который запускает все тесты.

### Параметры сборки {#build-options}

Настройте сегментирование через свойства проекта Gradle:

| Свойство | Описание |
|----------|-------------|
| `-PtuistShardMax=<N>` | Максимальное количество сегментов (по умолчанию: 2) |
| `-PtuistShardMin=<N>` | Минимальное количество сегментов |
| `-PtuistShardMaxDuration=<MS>` | Целевая максимальная длительность одного сегмента в миллисекундах |
| `-PtuistShardTestTask=<NAME>` | Задача тестирования, тесты которой сегментируются, например `testDebugUnitTest`. По умолчанию используются все задачи тестирования в сборке |

Проекты Android с несколькими вариантами сборки имеют одну задачу модульного теста для каждого варианта. Установите `-PtuistShardTestTask` на вариант, который запускают ваши сегменты, чтобы планировались только проекты, имеющие его:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5 \
  -PtuistShardTestTask=testDebugUnitTest
```

Ссылка на сегмент автоматически определяется из переменных окружения CI (`GITHUB_RUN_ID`, `CI_PIPELINE_ID` и т. д.) или может быть явно установлена через переменную окружения `TUIST_SHARD_REFERENCE`.

## Этап тестирования {#test-phase}

Каждый исполнитель сегмента выполняет назначенные ему тесты, используя стандартную задачу `test`. Когда установлен `TUIST_SHARD_INDEX`, плагин автоматически получает назначение сегмента с сервера и фильтрует выполнение тестов, включая только назначенные наборы тестов. Задачи тестирования в проектах, где нет наборов, назначенных сегменту, пропускаются.

Последний сегмент запускает каждую задачу тестирования и исключает наборы, назначенные другим сегментам, поэтому наборы, у которых еще нет записанных запусков, такие как недавно добавленные, все равно выполняются.

```sh
TUIST_SHARD_INDEX=0 ./gradlew test
```

Если вы установили `-PtuistShardTestTask` на этапе сборки, запускайте ту же задачу в каждом сегменте, например `./gradlew testDebugUnitTest`.

## Непрерывная интеграция {#continuous-integration}

Tuist автоматически обнаруживает следующих провайдеров CI:

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

Для других провайдеров обратитесь к файлу `.tuist-shard-matrix.json`, чтобы настроить параллельные задания.

### GitHub Actions {#github-actions}

Используйте стратегию матрицы для параллельного запуска сегментов:

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

Tuist генерирует `.tuist-shard-child-pipeline.yml`, который вы запускаете как [дочерний пайплайн](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). Определите шаблонное задание `.tuist-shard`, которое расширяют сгенерированные задания сегментов:

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

Дочернему пайплайну требуется шаблон задания `.tuist-shard`:

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  script:
    - tuist auth login
    - ./gradlew test
```

### CircleCI {#circleci}

Tuist генерирует `.tuist-shard-continuation.json` с параметрами для [orb продолжения](https://circleci.com/developer/orbs/orb/circleci/continuation):

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

Tuist генерирует `.tuist-shard-pipeline.yml` с одним шагом на каждый сегмент. Загрузите его с помощью `buildkite-agent pipeline upload`:

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
```

Каждый сгенерированный шаг имеет установленную в своем окружении переменную `TUIST_SHARD_INDEX`. Добавьте команду тестирования к каждому шагу сегмента, используя общий скрипт:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
./gradlew test
```

### Codemagic {#codemagic}

Codemagic не поддерживает динамические матричные задания, поэтому определите отдельный рабочий процесс для каждого сегмента. Tuist записывает `TUIST_SHARD_MATRIX` и `TUIST_SHARD_COUNT` в файл `CM_ENV` для использования в каждом рабочем процессе:

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

В Bitrise Tuist записывает `.tuist-shard-matrix.json` в `BITRISE_DEPLOY_DIR`, делая его доступным как артефакт сборки для последующих этапов пайплайна. Используйте Bitrise Pipelines с предопределенными параллельными рабочими процессами:

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
> Bitrise не поддерживает динамическое создание параллельных заданий во время выполнения. Определите фиксированное количество рабочих процессов сегментов на этапах вашего пайплайна — рабочие процессы внутри этапа выполняются параллельно автоматически.
