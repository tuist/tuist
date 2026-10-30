---
{
  "title": "Шардирование тестов Xcode",
  "titleTemplate": ":title · Шардирование тестов · Возможности · Руководства · Tuist",
  "description": "Распределяйте тесты Xcode между несколькими CI-раннерами с помощью шардирования тестов Tuist."
}
---
# Сегментирование тестов Xcode {#xcode-test-sharding}

> [!WARNING]
> **Требования**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Инсайты тестов Xcode</.localized_link> настроены. Сегментирование использует данные о времени выполнения тестов за последние 30 дней для балансировки сегментов; без инсайтов каждый сегмент выполняется так, как если бы набор тестов был неизвестен.

Сегментирование тестов для проектов Xcode использует `tuist xcodebuild build-for-testing` для создания плана сегментирования и `tuist xcodebuild test` для выполнения каждого сегмента.

## Как это работает {#how-it-works}

Сегментирование тестов следует двухэтапному рабочему процессу:

1. **Этап сборки:** Tuist считывает тестовые модули из собранного файла `.xctestrun` и создает **план сегментирования** на сервере. Сервер использует исторические данные о времени выполнения тестов за последние 30 дней, чтобы распределить тесты по сегментам так, чтобы каждый сегмент занимал примерно одинаковое количество времени. Этап сборки выводит **матрицу сегментов**, которую ваша система CI использует для запуска параллельных раннеров.
2. **Этап тестирования:** Каждый раннер непрерывной интеграции получает **индекс сегмента** и точный **идентификатор плана сегментирования**, а затем выполняет выборку тестов этого плана.

При гранулярности на уровне наборов тестов сервер выбирает известные наборы для каждого модуля: для каждого модуля в текущем `.xctestrun` он объединяет наборы из последних нескольких запусков CI в собираемой ветке, возвращаясь к ветке по умолчанию проекта для модулей без истории ветки. Чтение нескольких запусков вместо только последнего важно, потому что сегментированный запуск загружает один прогон тестов на сегмент по мере завершения каждого сегмента, поэтому самый последний прогон содержит только ту часть модуля, которая была обработана на данный момент, а также потому, что это не позволяет прогонам выборочного тестирования скрывать наборы, которые были пропущены в последнем запуске ветки.

Когда используется `--shard-granularity suite`, Tuist распределяет известные наборы по запрошенному количеству сегментов и использует последний сегмент как резервный. Например, `--shard-total 5` создает индексы сегментов от `0` до `4`, при этом индекс сегмента `4` является резервным. Обычные сегменты запускаются с `-only-testing` для назначенных им наборов. Последний сегмент запускается без `-only-testing` и передает `-skip-testing` для каждого набора, назначенного предыдущим сегментам, поэтому он выполняет свои запланированные наборы плюс недавно добавленные наборы или наборы, отсутствующие в исторической инвентаризации. Гранулярность на уровне модулей не требует резервного сегмента, поскольку файл `.xctestrun` предоставляет список модулей.

## Этап сборки {#build-phase}

Соберите ваши тесты и создайте план сегментирования:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5
```

Эта команда:
1. Собирает ваши тесты с помощью `xcodebuild build-for-testing`
2. Создает план сегментирования на сервере Tuist, используя исторические данные о времени выполнения
3. Загружает бандл `.xctestproducts` или записывает архив сегментов для использования раннерами сегментов
4. Выводит матрицу сегментов для вашей системы CI

### Параметры сборки {#build-options}

| Флаг | Переменная окружения | Описание |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | Максимальное количество сегментов. Используется вместе с `--shard-max-duration` для ограничения количества сегментов |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | Минимальное количество сегментов |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | Точное количество сегментов (взаимоисключающе с `--shard-min`/`--shard-max`). При гранулярности на уровне наборов тестов последний сегмент является резервным |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | Целевая максимальная длительность одного сегмента в миллисекундах |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (по умолчанию) распределяет целые тестовые модули по сегментам; `suite` распределяет отдельные тестовые классы для более детальной балансировки |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Уникальный идентификатор плана сегментирования (автоматически определяется на поддерживаемых провайдерах CI) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Путь, по которому Tuist записывает оптимизированный архив сегментов вместо загрузки тестовых продуктов в удаленное хранилище |

## Этап тестирования {#test-phase}

Каждый раннер сегмента выполняет назначенные ему тесты:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Параметры тестирования {#test-options}

| Флаг | Переменная окружения | Описание |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | Индекс сегмента для выполнения (начиная с нуля) |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | Точный идентификатор плана сегментирования, созданный на этапе сборки. Сгенерированные выводы провайдеров включают это значение автоматически |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Уникальный идентификатор плана сегментирования (автоматически определяется на поддерживаемых провайдерах CI) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Путь к локально управляемому архиву сегментов; Tuist извлекает его вместо загрузки тестовых продуктов из удаленного хранилища |

Tuist загружает бандл `.xctestproducts` и фильтрует его, чтобы включить только тесты, назначенные этому сегменту.

## Непрерывная интеграция {#continuous-integration}

Tuist автоматически обнаруживает следующие провайдеры CI:

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

Для других провайдеров обратитесь к файлу `.tuist-shard-matrix.json`, чтобы настроить параллельные задачи.

### GitHub Actions {#github-actions}

Используйте матричную стратегию для параллельного запуска сегментов:

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
        run: |
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
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
      - run: |
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'
```

### GitLab CI {#gitlab-ci}

Tuist генерирует файл `.tuist-shard-child-pipeline.yml`, который вы запускаете как [дочерний пайплайн](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). Определите шаблонную задачу `.tuist-shard`, от которой будут наследоваться сгенерированные задачи сегментов:

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
    - |
      tuist xcodebuild build-for-testing \
        -scheme MyScheme \
        -destination 'platform=iOS Simulator,name=iPhone 16' \
        --shard-total 5
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
    - |
      tuist xcodebuild test \
        -scheme MyScheme \
        -destination 'platform=iOS Simulator,name=iPhone 16'
```

### CircleCI {#circleci}

Tuist генерирует файл `.tuist-shard-continuation.json` с параметрами для [орба продолжения](https://circleci.com/developer/orbs/orb/circleci/continuation). Параметр `shard-plan-id` должен быть объявлен в вашей конфигурации продолжения:

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
            tuist xcodebuild build-for-testing \
              -scheme MyScheme \
              -destination 'platform=iOS Simulator,name=iPhone 16' \
              --shard-total 5
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
            tuist xcodebuild test \
              -scheme MyScheme \
              -destination 'platform=iOS Simulator,name=iPhone 16'

workflows:
  test:
    jobs:
      - test-shard:
          matrix:
            parameters:
              shard-index: [<< pipeline.parameters.shard-indices >>]
```

### Buildkite {#buildkite}

Tuist генерирует файл `.tuist-shard-pipeline.yml` с одним шагом для каждого сегмента. Загрузите его с помощью `buildkite-agent pipeline upload`:

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      tuist xcodebuild build-for-testing \
        -scheme MyScheme \
        -destination 'platform=iOS Simulator,name=iPhone 16' \
        --shard-total 5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
    agents:
      queue: macos
```

Каждый сгенерированный шаг имеет установленные переменные окружения `TUIST_SHARD_INDEX` и `TUIST_SHARD_PLAN_ID`. Добавьте команду тестирования к каждому шагу сегмента, используя общий скрипт:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Codemagic {#codemagic}

Codemagic не поддерживает динамические матричные задачи, поэтому определите отдельный воркфлоу для каждого сегмента. Tuist записывает `TUIST_SHARD_MATRIX` и `TUIST_SHARD_COUNT` в файл `CM_ENV` для использования внутри воркфлоу сборки. Переменная `CM_ENV` в Codemagic ограничена рамками воркфлоу, поэтому точный идентификатор плана сегментирования не передается между воркфлоу; воркфлоу тестирования используют поиск сегментов по ссылке:

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
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5

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
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'

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

В Bitrise Tuist записывает файл `.tuist-shard-matrix.json` (включая `shard_plan_id`) в директорию `BITRISE_DEPLOY_DIR`, делая его доступным как артефакт сборки для последующих этапов пайплайна. Каждый воркфлоу тестирования извлекает идентификатор плана из загруженного артефакта с помощью `envman`, чтобы передать его в окружение команды тестирования:

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
                tuist xcodebuild build-for-testing \
                  -scheme MyScheme \
                  -destination 'platform=iOS Simulator,name=iPhone 16' \
                  --shard-total 5
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
                tuist xcodebuild test \
                  -scheme MyScheme \
                  -destination 'platform=iOS Simulator,name=iPhone 16'
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
> Bitrise не поддерживает динамическое создание параллельных задач во время выполнения. Определите фиксированное количество воркфлоу сегментов на этапах вашего пайплайна — воркфлоу внутри одного этапа выполняются параллельно автоматически.

## Общие тома {#shared-volumes}

По умолчанию этап сборки загружает бандл `.xctestproducts` в удаленное хранилище, и каждый раннер сегмента скачивает его. Если ваш провайдер CI поддерживает **общие тома** (постоянное хранилище, монтируемое между задачами), вы можете полностью пропустить эту загрузку и скачивание, передавая тестовые продукты через общую файловую систему.

Это может значительно сократить время запуска сегментов, особенно для больших тестовых бандлов.

Чтобы использовать общие тома:

1. На **этапе сборки** передайте параметр `-testProductsPath`, указывающий на общий том, и добавьте флаг `--shard-skip-upload`, чтобы пропустить удаленную загрузку:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-skip-upload \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. На **этапе тестирования** передайте тот же параметр `-testProductsPath`, чтобы Tuist считывал тестовые продукты локально вместо их скачивания:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

> [!IMPORTANT]
> Используйте уникальный путь для каждого запуска воркфлоу (например, включите ID запуска CI), чтобы избежать конфликтов между параллельными запусками. Также следует очищать тестовые продукты после завершения сегментирования, чтобы избежать накопления устаревших данных на томе.

| Флаг | Переменная окружения | Описание |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | Пропустить загрузку бандла тестовых продуктов в удаленное хранилище |

## Самостоятельно управляемые артефакты {#self-managed-artifacts}

Если ваш провайдер CI уже имеет шаги загрузки и скачивания артефактов, вы можете поручить Tuist архивацию и извлечение, пока CI занимается транспортировкой.

1. На **этапе сборки** передайте параметр `--shard-archive-path`, чтобы Tuist записывал оптимизированный архив сегментов локально вместо загрузки тестовых продуктов:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. Загрузите этот архив, используя нативный шаг артефактов вашего CI.

3. В каждой задаче **этапа тестирования** скачайте архив и передайте тот же путь обратно в Tuist:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

Когда установлен параметр `--shard-archive-path`, Tuist пропускает передачу тестовых продуктов в удаленное хранилище и использует локальный архив. Если вы также передаете параметр `--shard-skip-upload`, путь к архиву имеет приоритет.

### Namespace {#namespace}

Раннеры [Namespace](https://namespace.so) хорошо работают с артефактами GitHub Actions. Установите переменную `TUIST_TEST_SHARD_ARCHIVE_PATH` один раз, чтобы задача сборки записывала архив сегментов локально, затем загрузите его и скачайте в каждой задаче сегмента перед запуском `tuist xcodebuild test`:

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
        run: |
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5
      - uses: actions/upload-artifact@v4
        with:
          name: test-shard-archive
          path: ${{ env.TUIST_TEST_SHARD_ARCHIVE_PATH }}
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
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
      - run: |
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}
```
