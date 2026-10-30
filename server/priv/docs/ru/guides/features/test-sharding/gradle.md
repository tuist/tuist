---
{
  "title": "Шардирование тестов Gradle",
  "titleTemplate": ":title · Шардирование тестов · Возможности · Руководства · Tuist",
  "description": "Распределяйте тесты Gradle между несколькими CI-раннерами с помощью шардирования тестов Tuist."
}
---
# Шардирование тестов Gradle {#gradle-test-sharding}

Плагин Tuist для Gradle включает встроенную поддержку шардирования тестов. Он планирует наборы тестов, которые Tuist записал в предыдущих запусках CI для задач тестирования ваших проектов, и использует сервер Tuist для создания сбалансированных планов шардов на основе исторических данных о времени выполнения.

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/features/test-insights/gradle">Аналитика тестов</.localized_link> должна быть настроена

## Как это работает {#how-it-works}

Шардирование тестов следует двухфазному рабочему процессу:

1. **Фаза сборки:** Tuist создает **план шардов** на сервере на основе наборов тестов, записанных для ваших проектов. Сервер использует исторические данные о времени выполнения тестов за последние 30 дней, чтобы распределить тесты по шардам так, чтобы каждый шард занимал примерно одинаковое количество времени. Фаза сборки выводит **матрицу шардов**, которую ваша система CI использует для запуска параллельных исполнителей.
2. **Фаза тестирования:** Каждый исполнитель CI получает **индекс шарда** и выполняет только те тесты, которые назначены этому шарду. Последний шард также запускает каждый набор тестов, который не назначен другому шарду.

## Фаза сборки {#build-phase}

Подготовьте шарды тестов с помощью задачи `tuistPrepareTestShards`:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5
```

Эта задача:
1. Находит проекты, имеющие задачу тестирования для шардирования, без их компиляции
2. Создает план шардов на сервере Tuist на основе наборов тестов и времени выполнения, записанных для этих проектов за последние 30 дней
3. Выводит матрицу шардов для вашей системы CI

Если наборы тестов еще не записаны, например, при первом запуске, план содержит один шард, который запускает все тесты.

### Параметры сборки {#build-options}

Настройте шардирование через свойства проекта Gradle:

| Свойство | Описание |
|----------|-------------|
| `-PtuistShardMax=<N>` | Максимальное количество шардов (по умолчанию: 2) |
| `-PtuistShardMin=<N>` | Минимальное количество шардов |
| `-PtuistShardMaxDuration=<MS>` | Целевая максимальная длительность на шард в миллисекундах |
| `-PtuistShardTestTask=<NAME>` | Задача тестирования, тесты которой шардируются, например `testDebugUnitTest`. По умолчанию используются все задачи тестирования в сборке |

Проекты Android с несколькими вариантами сборки имеют одну задачу модульного тестирования на вариант. Установите `-PtuistShardTestTask` в вариант, который запускают ваши шарды, чтобы планировались только проекты, имеющие его:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5 \
  -PtuistShardTestTask=testDebugUnitTest
```

Ссылка на шард автоматически определяется из переменных окружения CI (`GITHUB_RUN_ID`, `CI_PIPELINE_ID` и т. д.) или может быть явно установлена через переменную окружения `TUIST_SHARD_REFERENCE`.

## Фаза тестирования {#test-phase}

Каждый исполнитель шарда выполняет назначенные ему тесты, используя стандартную задачу `test`. Когда установлена переменная `TUIST_SHARD_INDEX`, плагин автоматически получает назначение шарда с сервера и фильтрует выполнение тестов, включая только назначенные наборы тестов. Задачи тестирования в проектах, где нет наборов, назначенных шарду, пропускаются.

Последний шард запускает каждую задачу тестирования и исключает наборы, назначенные другим шардам, поэтому наборы, у которых еще нет записанных запусков, например, недавно добавленные, все равно выполняются.

```sh
TUIST_SHARD_INDEX=0 ./gradlew test
```

Если вы установили `-PtuistShardTestTask` в фазе сборки, запустите ту же задачу в каждом шарде, например `./gradlew testDebugUnitTest`.

## Непрерывная интеграция {#continuous-integration}

Tuist автоматически обнаруживает следующих провайдеров CI:

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

Для других провайдеров обратитесь к файлу `.tuist-shard-matrix.json`, чтобы настроить параллельные задачи.

### GitHub Actions {#github-actions}

Используйте матричную стратегию для параллельного запуска шардов:

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

Tuist генерирует файл `.tuist-shard-child-pipeline.yml`, который вы запускаете как [дочерний пайплайн](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). Определите шаблонную задачу `.tuist-shard`, от которой будут наследоваться сгенерированные задачи шардов:

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

Дочернему пайплайну требуется шаблон задачи `.tuist-shard`:

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  script:
    - tuist auth login
    - ./gradlew test
```

### CircleCI {#circleci}

Tuist генерирует файл `.tuist-shard-continuation.json` с параметрами для [orb продолжения](https://circleci.com/developer/orbs/orb/circleci/continuation):

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

Tuist генерирует файл `.tuist-shard-pipeline.yml` с одним шагом на каждый шард. Загрузите его с помощью `buildkite-agent pipeline upload`:

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
```

Каждый сгенерированный шаг имеет установленную в окружении переменную `TUIST_SHARD_INDEX`. Добавьте команду тестирования к каждому шагу шарда, используя общий скрипт:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
./gradlew test
```

### Codemagic {#codemagic}

Codemagic не поддерживает динамические матричные задачи, поэтому определите отдельный workflow для каждого шарда. Tuist записывает `TUIST_SHARD_MATRIX` и `TUIST_SHARD_COUNT` в файл `CM_ENV` для использования внутри каждого workflow:

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

В Bitrise Tuist записывает `.tuist-shard-matrix.json` в `BITRISE_DEPLOY_DIR`, делая его доступным как артефакт сборки для последующих этапов пайплайна. Используйте Bitrise Pipelines с предопределенными параллельными workflow:

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
> Bitrise не поддерживает динамическое создание параллельных задач во время выполнения. Определите фиксированное количество workflow шардов на этапах вашего пайплайна — workflow внутри этапа выполняются параллельно автоматически.
