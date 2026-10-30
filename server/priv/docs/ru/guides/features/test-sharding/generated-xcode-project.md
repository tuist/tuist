---
{
  "title": "Сгенерированный проект Xcode",
  "titleTemplate": ":title · Шардирование тестов · Возможности · Руководства · Tuist",
  "description": "Распределите тесты в сгенерированном Tuist проекте Xcode по нескольким CI-раннерам с помощью шардирования тестов Tuist."
}
---
# Сгенерированный проект Xcode {#generated-xcode-project-test-sharding}

Разделение тестов для сгенерированных проектов использует `tuist test` как на этапе сборки, так и на этапе тестирования.

## Как это работает {#how-it-works}

Разделение тестов следует двухэтапному рабочему процессу:

1. **Этап сборки:** Tuist считывает тестовые модули из собранного файла `.xctestrun` и создает **план шардирования** на сервере. Сервер использует исторические данные о времени выполнения тестов за последние 30 дней, чтобы распределить тесты по шардам так, чтобы каждый шард занимал примерно одинаковое количество времени. Этап сборки выводит **матрицу шардов**, которую ваша CI-система использует для запуска параллельных раннеров.
2. **Этап тестирования:** Каждый раннер непрерывной интеграции получает **индекс шарда** и точный **идентификатор плана шардирования**, а затем выполняет выборку тестов этого плана.

При использовании `--shard-granularity suite` Tuist не загружает каждый тестовый бандл для перечисления наборов тестов во время этапа сборки. Вместо этого текущий файл `.xctestrun` предоставляет список модулей, а сервер выбирает известные наборы тестов для каждого модуля: для каждого модуля он объединяет наборы тестов из последних нескольких запусков CI в собираемой ветке. Если у модуля нет истории в этой ветке, сервер возвращается к ветке по умолчанию проекта. Чтение нескольких запусков, а не только последнего, важно, потому что шардированный запуск выгружает один прогон тестов на каждый шард по мере его завершения, поэтому самый последний запуск содержит только ту часть модуля, которая была обработана на данный момент, а также потому, что это предотвращает скрытие наборов тестов, которые были пропущены в последнем запуске ветки, при выборочном тестировании. Сервер по-прежнему использует данные о времени выполнения наборов тестов за последние 30 дней для оценки длительности.

Tuist распределяет эти известные наборы тестов по запрошенному количеству шардов и использует последний шард как резервный. Например, `--shard-total 5` создает индексы шардов от `0` до `4`, при этом индекс шарда `4` является резервным. Обычные шарды запускаются с `-only-testing` для назначенных им наборов тестов. Последний шард запускается без `-only-testing` и передает `-skip-testing` для каждого набора тестов, назначенного предыдущим шардам, поэтому он также запускает вновь добавленные наборы тестов, переименованные наборы или наборы, отсутствующие в исторической инвентаризации. Гранулярность на уровне модулей не требует резервного шарда, поскольку файл `.xctestrun` предоставляет список модулей.

## Этап сборки {#build-phase}

Сгенерируйте проект, соберите тесты и создайте план шардирования:

```sh
tuist test --build-only --shard-total 5
```

Флаг `--build-only` указывает Tuist собрать тесты без их запуска. Tuist выдаст ошибку, если вы передадите флаги планирования шардов (`--shard-min`/`--shard-max`/`--shard-total`) без `--build-only`.

Эта команда:
1. Генерирует проект Xcode из ваших манифестов
2. Собирает ваши тесты
3. Создает план шардирования на сервере Tuist, используя исторические данные о времени выполнения
4. Загружает бандл `.xctestproducts` или записывает архив шарда для использования раннерами шардов
5. Выводит матрицу шардов для вашей CI-системы
6. Сохраняет граф <.localized_link href="/guides/features/selective-testing">выборочного тестирования</.localized_link> (если применимо), чтобы раннеры шардов не пересоздавали проект

### Параметры сборки {#build-options}

| Флаг | Переменная окружения | Описание |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | Максимальное количество шардов. Используется с `--shard-max-duration` для ограничения количества шардов |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | Минимальное количество шардов |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | Точное количество шардов (взаимоисключающе с `--shard-min`/`--shard-max`). При гранулярности на уровне наборов тестов последний шард является резервным |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | Целевая максимальная длительность одного шарда в миллисекундах |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (по умолчанию) распределяет целые тестовые модули по шардам; `suite` распределяет отдельные тестовые классы для более детального балансирования |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Уникальный идентификатор плана шардирования (автоматически определяется на поддерживаемых CI-провайдерах) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Путь, по которому Tuist записывает оптимизированный архив шарда вместо загрузки тестовых продуктов в удаленное хранилище |

## Этап тестирования {#test-phase}

Каждый раннер шарда выполняет назначенные ему тесты:

```sh
tuist test --without-building
```

Флаг `--without-building` указывает Tuist запустить тесты, используя ранее собранные продукты, вместо повторной сборки. Tuist выдаст ошибку, если `TUIST_SHARD_INDEX` / `--shard-index` установлен без `--without-building`.

### Параметры тестирования {#test-options}

| Флаг | Переменная окружения | Описание |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | Индекс шарда для выполнения (начинается с нуля) |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | Точный идентификатор плана шардирования, созданный на этапе сборки. Сгенерированные выводы провайдера автоматически включают это значение |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Уникальный идентификатор плана шардирования (автоматически определяется на поддерживаемых CI-провайдерах) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Путь к локально управляемому архиву шарда; Tuist извлекает его вместо загрузки тестовых продуктов из удаленного хранилища |

Tuist скачивает пакет `.xctestproducts` и фильтрует его, оставляя только тесты, назначенные этому шарду.

> [!TIP]
> **Выборочное тестирование**
>
> Шардирование тестов без проблем работает с <.localized_link href="/guides/features/selective-testing">выборочным тестированием</.localized_link>. Граф выборочного тестирования сохраняется на этапе сборки и восстанавливается для каждого шарда, поэтому раннерам не нужно заново генерировать проект.

## Непрерывная интеграция {#continuous-integration}

Tuist автоматически определяет следующие CI-провайдеры:

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

Tuist генерирует файл `.tuist-shard-child-pipeline.yml`, который вы запускаете как [дочерний пайплайн](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). Определите шаблонную задачу `.tuist-shard`, от которой будут наследоваться сгенерированные задачи шардов:

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

Tuist генерирует файл `.tuist-shard-continuation.json` с параметрами для [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation). Параметр `shard-plan-id` должен быть объявлен в вашей продолженной конфигурации:

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

Tuist генерирует файл `.tuist-shard-pipeline.yml` с одним шагом на каждый шард. Загрузите его с помощью `buildkite-agent pipeline upload`:

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

Каждый сгенерированный шаг имеет переменные окружения `TUIST_SHARD_INDEX` и `TUIST_SHARD_PLAN_ID`. Добавьте команду тестирования к каждому шагу шарда, используя общий скрипт:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic не поддерживает динамические матричные задачи, поэтому определите отдельный воркфлоу для каждого шарда. Tuist записывает `TUIST_SHARD_MATRIX` и `TUIST_SHARD_COUNT` в файл `CM_ENV` для использования внутри воркфлоу сборки. Область видимости `CM_ENV` в Codemagic ограничена воркфлоу, поэтому точный идентификатор плана шардирования не передается между воркфлоу; тестовые воркфлоу используют поиск шарда по ссылке:

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

В Bitrise Tuist записывает файл `.tuist-shard-matrix.json` (включая `shard_plan_id`) в директорию `BITRISE_DEPLOY_DIR`, делая его доступным как артефакт сборки для последующих этапов пайплайна. Каждый тестовый воркфлоу извлекает ID плана из загруженного артефакта с помощью `envman`, чтобы передать его в окружение команды тестирования:

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
> Bitrise не поддерживает динамическое создание параллельных задач во время выполнения. Определите фиксированное количество воркфлоу шардов в этапах вашего пайплайна — воркфлоу внутри этапа выполняются параллельно автоматически.

## Общие тома {#shared-volumes}

По умолчанию этап сборки загружает пакет `.xctestproducts` в удаленное хранилище, и каждый раннер шарда скачивает его. Если ваш CI-провайдер поддерживает **общие тома** (постоянное хранилище, монтируемое между задачами), вы можете полностью пропустить эту загрузку/скачивание, передавая тестовые продукты через общую файловую систему.

Это может значительно сократить время запуска шарда, особенно для больших тестовых пакетов.

Чтобы использовать общие тома:

1. На **этапе сборки** передайте `-testProductsPath` (после `--`), указывающий на общий том, и добавьте `--shard-skip-upload`, чтобы пропустить удаленную загрузку:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. На **этапе тестирования** передайте тот же `-testProductsPath`, чтобы Tuist считывал тестовые продукты локально вместо их скачивания:

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| Флаг | Переменная окружения | Описание |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | Пропустить загрузку пакета тестовых продуктов в удаленное хранилище |

## Самостоятельно управляемые артефакты {#self-managed-artifacts}

Если ваш CI-провайдер уже имеет шаги загрузки и скачивания артефактов, вы можете поручить Tuist архивацию и извлечение, пока ваш CI занимается транспортировкой.

1. На **этапе сборки** передайте `--shard-archive-path`, чтобы Tuist записывал оптимизированный архив шарда локально вместо загрузки тестовых продуктов:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. Загрузите этот архив, используя нативный шаг артефактов вашего CI.

3. В каждой задаче **этапа тестирования** скачайте архив и передайте тот же путь обратно в Tuist:

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

Когда установлен `--shard-archive-path`, Tuist пропускает передачу тестовых продуктов удаленно и вместо этого использует локальный архив. Если вы также передаете `--shard-skip-upload`, путь к архиву имеет приоритет.

Если нет тестов для запуска, например, потому что выборочное тестирование пропустило все цели тестирования, этап сборки выводит пустую матрицу шардов и не записывает архив. Выполняйте шаг загрузки только тогда, когда в матрице есть шарды.

> [!IMPORTANT]
> Используйте уникальный путь для каждого запуска воркфлоу (например, включите ID запуска CI), чтобы избежать коллизий между параллельными запусками. Также следует очищать архив шарда после завершения шардирования, чтобы избежать накопления устаревших данных на раннере.

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
