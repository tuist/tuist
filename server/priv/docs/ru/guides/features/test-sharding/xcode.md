---
{
  "title": "Шардирование тестов Xcode",
  "titleTemplate": ":title · Шардирование тестов · Возможности · Руководства · Tuist",
  "description": "Распределяйте тесты Xcode между несколькими CI-раннерами с помощью шардирования тестов Tuist."
}
---
# Сегментирование тестов Xcode {#xcode-test-sharding}

> [!IMPORTANT]
> **Требования**
>
> - Настроены <.localized_link href="/guides/features/test-insights/xcode">инсайты тестов Xcode</.localized_link>. Сегментирование использует данные о времени выполнения тестов за последние 30 дней для балансировки сегментов; без инсайтов каждый сегмент выполняется так, как если бы набор тестов был неизвестен.

Сегментирование тестов для проектов Xcode использует `tuist xcodebuild build-for-testing` для создания плана сегментов и `tuist xcodebuild test` для выполнения каждого сегмента.

## Как это работает {#how-it-works}

Сегментирование тестов следует двухэтапному рабочему процессу:

1. **Этап сборки:** Tuist считывает тестовые модули из собранного файла `.xctestrun` и создаёт на сервере **план сегментов**. Сервер использует исторические данные о времени выполнения тестов за последние 30 дней, чтобы распределить тесты по сегментам так, чтобы каждый сегмент занимал примерно одинаковое время. Этап сборки выводит **матрицу сегментов**, которую ваша система CI использует для запуска параллельных раннеров.
2. **Этап тестирования:** Каждый раннер непрерывной интеграции получает **индекс сегмента** и точный **идентификатор плана сегментов**, затем выполняет выборку тестов согласно этому плану.

При гранулярности на уровне наборов тестов сервер использует наборы, которые недавние запуски CI в вашей ветке сообщили для каждого модуля в текущем `.xctestrun`, возвращаясь к ветке по умолчанию проекта для модулей без истории в ветке. Объединение нескольких запусков сохраняет наборы, которые сегментированный или выборочный запуск не включил в последний отчёт.

Когда используется `--shard-granularity suite`, Tuist распределяет известные наборы тестов по запрошенному количеству сегментов и использует последний сегмент как резервный. Например, `--shard-total 5` создаёт индексы сегментов от `0` до `4`, при этом индекс сегмента `4` является резервным. Обычные сегменты запускаются с `-only-testing` для назначенных им наборов тестов. Последний сегмент запускается без `-only-testing` и передаёт `-skip-testing` для каждого набора, назначенного предыдущим сегментам, поэтому он выполняет запланированные наборы, а также новые наборы или наборы, отсутствующие в исторической инвентаризации. Гранулярность на уровне модулей не требует резервного сегмента, потому что файл `.xctestrun` предоставляет список модулей.

## Этап сборки {#build-phase}

Соберите тесты и создайте план сегментов:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5
```

Эта команда:
1. Собирает ваши тесты с помощью `xcodebuild build-for-testing`
2. Создаёт план сегментов на сервере Tuist, используя исторические данные о времени выполнения
3. Загружает бандл `.xctestproducts` или записывает архив сегментов для использования раннерами сегментов
4. Выводит матрицу сегментов для вашей системы CI

<!-- @snippet: ./_xcode-build-options -->

## Этап тестирования {#test-phase}

Каждый раннер сегмента выполняет назначенные ему тесты:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

<!-- @snippet: ./_xcode-test-options -->

## Непрерывная интеграция {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

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

Tuist генерирует `.tuist-shard-child-pipeline.yml`, который вы запускаете как [дочерний пайплайн](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines). Определите шаблонную задачу `.tuist-shard`, которую будут расширять сгенерированные задачи сегментов:

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

Tuist генерирует `.tuist-shard-continuation.json` с параметрами для [orb продолжения](https://circleci.com/developer/orbs/orb/circleci/continuation). Параметр `shard-plan-id` должен быть объявлен в вашей конфигурации продолжения:

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

Tuist генерирует `.tuist-shard-pipeline.yml` с одним шагом на сегмент. Загрузите его с помощью `buildkite-agent pipeline upload`:

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

Каждый сгенерированный шаг имеет установленные в своей среде переменные `TUIST_SHARD_INDEX` и `TUIST_SHARD_PLAN_ID`. Добавьте команду тестирования к каждому шагу сегмента, используя общий скрипт:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Codemagic {#codemagic}

Codemagic не поддерживает динамические матричные задачи, поэтому определите отдельный рабочий процесс для каждого сегмента. Tuist записывает `TUIST_SHARD_MATRIX` и `TUIST_SHARD_COUNT` в файл `CM_ENV` для использования внутри рабочего процесса сборки. Переменная `CM_ENV` в Codemagic имеет область видимости рабочего процесса, поэтому точный идентификатор плана сегментов не передаётся между рабочими процессами; рабочие процессы тестирования возвращаются к поиску сегментов по ссылке:

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

В Bitrise Tuist записывает `.tuist-shard-matrix.json` (включая `shard_plan_id`) в `BITRISE_DEPLOY_DIR`, делая его доступным как артефакт сборки для последующих этапов пайплайна. Каждый рабочий процесс тестирования извлекает идентификатор плана из загруженного артефакта с помощью `envman`, чтобы передать его в среду команды тестирования:

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
> Bitrise не поддерживает динамическое создание параллельных задач во время выполнения. Определите фиксированное количество рабочих процессов сегментов в этапах вашего пайплайна — рабочие процессы внутри этапа выполняются параллельно автоматически.

## Общие тома {#shared-volumes}

По умолчанию этап сборки загружает бандл `.xctestproducts` в удалённое хранилище, и каждый раннер сегмента скачивает его. Если ваш провайдер CI поддерживает **общие тома** (постоянное хранилище, монтируемое между задачами), вы можете полностью пропустить эту загрузку/скачивание, передавая тестовые продукты через общую файловую систему.

Это может значительно сократить время запуска сегментов, особенно для больших тестовых бандлов.

Чтобы использовать общие тома:

1. На **этапе сборки** передайте `-testProductsPath`, указывающий на общий том, и добавьте `--shard-skip-upload`, чтобы пропустить удалённую загрузку:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-skip-upload \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. На **этапе тестирования** передайте тот же `-testProductsPath`, чтобы Tuist читал тестовые продукты локально вместо их скачивания:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

> [!IMPORTANT]
> Используйте уникальный путь для каждого запуска рабочего процесса (например, включите идентификатор запуска CI), чтобы избежать коллизий между параллельными запусками. Также следует очищать тестовые продукты после завершения сегментирования, чтобы не накапливать устаревшие данные на томе.

| Флаг | Переменная окружения | Описание |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | Пропустить загрузку бандла тестовых продуктов в удалённое хранилище |

## Артефакты под собственным управлением {#self-managed-artifacts}

Если ваш провайдер CI уже имеет шаги загрузки и скачивания артефактов, вы можете поручить Tuist архивацию и извлечение, пока CI занимается транспортировкой.

1. На **этапе сборки** передайте `--shard-archive-path`, чтобы Tuist записывал оптимизированный архив сегментов локально вместо загрузки тестовых продуктов:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. Загрузите этот архив, используя встроенный шаг работы с артефактами вашего CI.

3. В каждой задаче **этапа тестирования** скачайте архив и передайте тот же путь обратно в Tuist:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

Когда установлен `--shard-archive-path`, Tuist пропускает передачу тестовых продуктов через удалённое хранилище и использует локальный архив. Если вы также передадите `--shard-skip-upload`, путь к архиву будет иметь приоритет.

### Namespace {#namespace}

Раннеры [Namespace](https://namespace.so) хорошо работают с артефактами GitHub Actions. Установите `TUIST_TEST_SHARD_ARCHIVE_PATH` один раз, чтобы задача сборки записывала архив сегментов локально, загрузите его и скачайте в каждой задаче сегмента перед запуском `tuist xcodebuild test`:

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
