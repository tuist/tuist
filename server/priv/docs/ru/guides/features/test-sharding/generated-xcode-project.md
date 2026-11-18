---
{
  "title": "Сгенерированный проект Xcode",
  "titleTemplate": ":title · Распараллеливание тестов · Возможности · Руководства · Tuist",
  "description": "Распределите тесты в сгенерированном Tuist проекте Xcode между несколькими CI-раннерами с помощью функции Tuist Test Sharding."
}
---
# Сгенерированный проект Xcode {#generated-xcode-project-test-sharding}

Распараллеливание тестов для сгенерированных проектов использует `tuist test` как на этапе сборки, так и на этапе тестирования.

## Как это работает {#how-it-works}

Распараллеливание тестов выполняется в два этапа:

1. **Этап сборки:** Tuist считывает тестовые модули из собранного файла `.xctestrun` и создает **план шардирования** на сервере. Сервер использует исторические данные о времени выполнения тестов за последние 30 дней, чтобы распределить тесты по шардам так, чтобы каждый шард занимал примерно одинаковое время. Этап сборки выводит **матрицу шардов**, которую ваша система CI использует для запуска параллельных раннеров.
2. **Этап тестирования:** Каждый раннер непрерывной интеграции получает **индекс шарда** и точный **идентификатор плана шардирования**, затем выполняет выборку тестов согласно этому плану.

При использовании `--shard-granularity suite` сервер использует наборы тестов (suites), которые недавние запуски CI на вашей ветке сообщили для каждого модуля в текущем `.xctestrun`, возвращаясь к ветке по умолчанию проекта для модулей без истории ветки. Объединение нескольких запусков сохраняет наборы тестов, которые шардированный или выборочный запуск исключил из последнего отчета. Сервер использует данные о времени выполнения наборов тестов за последние 30 дней для оценки длительности.

Tuist распределяет эти известные наборы тестов по запрошенному количеству шардов и использует последний шард как резервный. Например, `--shard-total 5` создает индексы шардов от `0` до `4`, при этом индекс шарда `4` является резервным. Обычные шарды запускаются с `-only-testing` для назначенных им наборов тестов. Последний шард запускается без `-only-testing` и передает `-skip-testing` для каждого набора тестов, назначенного предыдущим шардам, поэтому он также запускает недавно добавленные наборы тестов, переименованные наборы тестов или наборы тестов, отсутствующие в исторической инвентаризации. Гранулярность на уровне модулей не требует резервного шарда, поскольку файл `.xctestrun` предоставляет список модулей.

## Этап сборки {#build-phase}

Сгенерируйте проект, соберите тесты и создайте план шардирования:

```sh
tuist test --build-only --shard-total 5
```

Флаг `--build-only` указывает Tuist собрать тесты без их запуска. Tuist завершится с ошибкой, если вы передадите флаги планирования шардов (`--shard-min`/`--shard-max`/`--shard-total`) без `--build-only`.

Эта команда:
1. Генерирует проект Xcode из ваших манифестов
2. Собирает ваши тесты
3. Создает план шардирования на сервере Tuist, используя исторические данные о времени выполнения
4. Загружает бандл `.xctestproducts` или записывает архив шардов для использования раннерами шардов
5. Выводит матрицу шардов для вашей системы CI
6. Сохраняет граф <.localized_link href="/guides/features/selective-testing">выборочного тестирования</.localized_link> (если применимо), чтобы раннерам шардов не нужно было повторно генерировать проект

<!-- @snippet: ./_xcode-build-options -->

## Этап тестирования {#test-phase}

Каждый раннер шарда выполняет назначенные ему тесты:

```sh
tuist test --without-building
```

Флаг `--without-building` указывает Tuist запустить тесты, используя ранее собранные продукты вместо повторной сборки. Tuist завершится с ошибкой, если `TUIST_SHARD_INDEX` / `--shard-index` установлено без `--without-building`.

<!-- @snippet: ./_xcode-test-options -->

> [!TIP]
> **Выборочное тестирование**
>
> Распараллеливание тестов seamlessly работает с <.localized_link href="/guides/features/selective-testing">выборочным тестированием</.localized_link>. Граф выборочного тестирования сохраняется во время этапа сборки и восстанавливается для каждого шарда, поэтому раннерам не нужно повторно генерировать проект.

## Непрерывная интеграция {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

### GitHub Actions {#github-actions}

Используйте стратегию матрицы для параллельного запуска шардов:

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

Tuist генерирует `.tuist-shard-child-pipeline.yml`, который вы запускаете как [дочерний пайплайн](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines). Определите шаблонную задачу `.tuist-shard`, которую расширяют сгенерированные задачи шардов:

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

Tuist генерирует `.tuist-shard-pipeline.yml` с одним шагом на шард. Загрузите его с помощью `buildkite-agent pipeline upload`:

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

Каждый сгенерированный шаг имеет `TUIST_SHARD_INDEX` и `TUIST_SHARD_PLAN_ID`, установленные в его окружении. Добавьте команду тестирования к каждому шагу шарда, используя общий скрипт:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic не поддерживает динамические матричные задачи, поэтому определите отдельный рабочий процесс для каждого шарда. Tuist записывает `TUIST_SHARD_MATRIX` и `TUIST_SHARD_COUNT` в файл `CM_ENV` для использования внутри рабочего процесса сборки. `CM_ENV` в Codemagic имеет область действия рабочего процесса, поэтому точный идентификатор плана шардирования не пересекает границы рабочих процессов; рабочие процессы тестирования возвращаются к поиску шардов на основе ссылки:

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

В Bitrise Tuist записывает `.tuist-shard-matrix.json` (включая `shard_plan_id`) в `BITRISE_DEPLOY_DIR`, делая его доступным как артефакт сборки для последующих этапов пайплайна. Каждый рабочий процесс тестирования извлекает ID плана из загруженного артефакта с помощью `envman`, чтобы он попал в окружение команды тестирования:

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
> Bitrise не поддерживает динамическое создание параллельных задач во время выполнения. Определите фиксированное количество рабочих процессов шардов в этапах вашего пайплайна — рабочие процессы внутри этапа выполняются параллельно автоматически.

## Общие тома {#shared-volumes}

По умолчанию этап сборки загружает бандл `.xctestproducts` в удаленное хранилище, и каждый раннер шарда скачивает его. Если ваш провайдер CI поддерживает **общие тома** (постоянное хранилище, монтируемое между задачами), вы можете полностью пропустить эту загрузку/скачивание, передавая тестовые продукты через общую файловую систему.

Это может значительно сократить время запуска шардов, особенно для больших тестовых бандлов.

Чтобы использовать общие тома:

1. На этапе **сборки** передайте `-testProductsPath` (после `--`), указывающий на общий том, и добавьте `--shard-skip-upload`, чтобы пропустить удаленную загрузку:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. На этапе **тестирования** передайте тот же `-testProductsPath`, чтобы Tuist считывал тестовые продукты локально вместо их скачивания:

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| Флаг | Переменная окружения | Описание |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | Пропустить загрузку бандла тестовых продуктов в удаленное хранилище |

## Артефакты под собственным управлением {#self-managed-artifacts}

Если ваш провайдер CI уже имеет шаги загрузки и скачивания артефактов, вы можете поручить Tuist архивацию и извлечение, а транспорт оставить за CI.

1. На этапе **сборки** передайте `--shard-archive-path`, чтобы Tuist записывал оптимизированный архив шарда локально вместо загрузки тестовых продуктов:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. Загрузите этот архив, используя нативный шаг артефактов вашего CI.

3. В каждой задаче этапа **тестирования** скачайте архив и передайте тот же путь обратно в Tuist:

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

Когда установлен `--shard-archive-path`, Tuist пропускает передачу тестовых продуктов через удаленное хранилище и использует локальный архив. Если вы также передаете `--shard-skip-upload`, путь к архиву имеет приоритет.

Когда нет тестов для запуска, например, потому что выборочное тестирование пропустило все цели тестирования, этап сборки выводит пустую матрицу шардов и не записывает архив. Выполняйте шаг загрузки только тогда, когда в матрице есть шарды.

> [!IMPORTANT]
> Используйте уникальный путь для каждого запуска рабочего процесса (например, включите ID запуска CI), чтобы избежать коллизий между параллельными запусками. Также следует очищать архив шарда после завершения шардирования, чтобы избежать накопления устаревших данных на раннере.

### Namespace {#namespace}

Раннеры [Namespace](https://namespace.so) хорошо работают с артефактами GitHub Actions. Установите `TUIST_TEST_SHARD_ARCHIVE_PATH` один раз, чтобы задача сборки записывала архив шарда локально, загрузите его и скачайте в каждой задаче шарда перед запуском `tuist test`:

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
