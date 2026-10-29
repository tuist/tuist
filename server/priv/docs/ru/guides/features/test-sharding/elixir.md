---
{
  "title": "Elixir Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute the tests of your Elixir project across multiple CI runners with Tuist Test Sharding."
}
---
# Шардирование тестов Elixir {#elixir-test-sharding}

Пакет Tuist для Hex включает встроенную поддержку шардирования тестов проекта на Elixir. Он использует сервер Tuist для создания сбалансированных планов шардов на основе исторических данных о времени выполнения и компилирует ваш проект один раз, чтобы каждый раннер мог сразу приступить к запуску тестов.

> [!IMPORTANT] REQUIREMENTS
> - Завершите <.localized_link href="/guides/get-started/elixir-project">настройку общего окружения для Elixir</.localized_link> перед настройкой задач шардирования в CI

## Как это работает {#how-it-works}

Шардирование тестов следует рабочему процессу из двух фаз:

1. **Фаза сборки:** Tuist компилирует ваш проект для тестирования, перечисляет файлы тестов и создает **план шардов** на сервере. Сервер использует исторические данные о времени выполнения тестов за последние 30 дней, чтобы распределить тесты по шардам так, чтобы каждый шард занимал примерно одинаковое количество времени. Фаза сборки загружает сборку и выводит **матрицу шардов**, которую ваша система CI использует для запуска параллельных раннеров.
2. **Фаза тестирования:** Каждый раннер CI получает **индекс шарда**, загружает сборку и выполняет только те тесты, которые назначены этому шарду.

Тесты распределяются по файлам: все тесты в одном файле выполняются на одном шарде. Для тестов, которые Tuist еще не видел, используется оценка, поэтому первые планы проекта менее сбалансированы, чем последующие.

## Фаза сборки {#build-phase}

Подготовьте шарды тестов с помощью задачи `tuist.test.build`:

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-max 5
```

Выполните компиляцию через алиас, установленный общей настройкой, перед вызовом задачи шардирования. При чистой выгрузке кода Mix может компилировать зависимости во время обнаружения `tuist.test.build`, прежде чем кэш зависимостей Tuist успеет их восстановить. Явная компиляция выполняется в том же тестовом окружении, что и задача шардирования.

Эта задача:
1. Компилирует проект в тестовом окружении
2. Создает план шардов на сервере Tuist, используя исторические данные о времени выполнения
3. Загружает сборку, чтобы шарды не компилировали ее повторно
4. Выводит матрицу шардов для вашей системы CI

### Параметры сборки {#build-options}

| Параметр | Описание |
|--------|-------------|
| `--shard-max <N>` | Максимальное количество шардов (по умолчанию: 2) |
| `--shard-min <N>` | Минимальное количество шардов |
| `--shard-total <N>` | Точное количество шардов вместо диапазона |
| `--shard-max-duration <MS>` | Целевая максимальная длительность одного шарда в миллисекундах |
| `--shard-reference <REF>` | Имя, по которому шарды находят план |
| `--no-upload` | Спланировать шарды без загрузки сборки; в этом случае каждый шард компилирует самостоятельно |

Все остальные аргументы передаются в `mix compile`.

Ссылка на шард автоматически определяется из переменных окружения CI (`GITHUB_RUN_ID`, `CI_PIPELINE_ID`, `CIRCLE_WORKFLOW_ID`, `BUILDKITE_BUILD_ID`) или может быть явно задана через переменную окружения `TUIST_SHARD_REFERENCE`. Вне этих провайдеров необходимо задать ее значение, которое будет общим для фазы сборки и шардов одного запуска конвейера. В GitHub Actions ссылки также включают попытку запуска: при повторном запуске только неудачных задач передавайте ссылку исходной задачи сборки, а не создавайте новую в задачах шардов.

## Фаза тестирования {#test-phase}

Когда установлена переменная `TUIST_SHARD_INDEX`, пакет получает назначение шарда с сервера, загружает сборку и запускает только назначенные файлы тестов без компиляции. На холодном раннере инициализируйте SDK и загрузите его пути перед вызовом задачи:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test
```

Компиляция SDK в рабочих процессах Mix не загружает его в родительский процесс. Явный шаг `deps.loadpaths` предотвращает компиляцию оставшихся зависимостей при обнаружении задач до загрузки сборки. Эта форма одной команды сохраняет алиас подготовки тестов вашего проекта. Если его команды настройки вызывают компиляцию, используйте отдельную последовательность настройки ниже.

Любые переданные файлы или директории тестов дополнительно сужают шард: выполняются только файлы, которые находятся и в шарде, и в вашем выборе. Шард, в котором не осталось тестов, завершается успешно.

Результаты всех шардов поступают на панель управления как единый запуск тестов, а раздел **Шарды** показывает, сколько времени занял каждый из них.

Если настройка должна выполняться перед тестами, сначала загрузите сборку без запуска приложения:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
```

Запустите настройку в отдельном процессе с отключенной компиляцией. Например, проект Ecto может создать и выполнить миграцию своих баз данных с помощью:

```sh
MIX_ENV=test mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
```

Сохраните любую другую специфичную для проекта подготовку на этом этапе. Ваш алиас компиляции также должен учитывать `--no-compile` перед выполнением работы по инициализации: Mix передает флаги только последней задаче в списке алиасов, поэтому более ранняя безусловная задача `deps.compile` все равно выполнится. См. защищенный алиас в разделе <.localized_link href="/guides/features/cache/elixir-advanced#manual-compile-integration">ручная интеграция компиляции</.localized_link>.

Затем загрузите восстановленный SDK без компиляции перед выполнением шарда. Это также предотвращает компиляцию зависимостей по пути при обнаружении задач, если их исходные файлы новее загруженной сборки:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

Обе команды требуют одну и ту же ссылку на шард. `--prepare-only` требует загруженную сборку, а `--no-download` завершается ошибкой, если отсутствует подготовленный артефакт приложения. `--no-download` явно пропускает алиас подготовки тестов вашего проекта, включая повторные попытки, и выводит уведомление при пропуске шагов настройки. Обычные запуски сохраняют свои алиасы, даже если вы передаете `--no-compile --no-deps-check`. Разделение миграций базы данных в отдельный процесс также позволяет избежать предупреждений о переопределении модулей, когда регрессионные тесты миграций сами загружают эти модули.

При тестировании разных окружений передавайте стабильную метку `--scheme`, например `--scheme clickhouse-current` или `--scheme clickhouse-floor`. Результаты с разными метками не рассматриваются как нестабильные повторные запуски одной и той же конфигурации.

### Что нужно шардам {#what-the-shards-need}

Загруженная сборка — это директория `_build/test`. Каждому раннеру шарда по-прежнему требуется:
- Та же самая версия кода, что и на этапе сборки
- Те же версии Elixir и Erlang/OTP
- Исходные коды зависимостей, полученные через `mix deps.get`

Разделение на шарды из корня umbrella-проекта пока не поддерживается. Запускайте оба этапа внутри одного из его приложений.

## Непрерывная интеграция {#continuous-integration}

### GitHub Actions {#github-actions}

В GitHub Actions этап сборки записывает индексы шардов в вывод `matrix` своего шага. Используйте матричную стратегию для параллельного запуска шардов:

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

### Другие провайдеры {#other-providers}

За пределами GitHub Actions этап сборки записывает план в файл `.tuist-shard-matrix.json`:

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

Используйте `shard_count` для настройки параллельных задач и присвойте каждой задаче её `TUIST_SHARD_INDEX` от `0` до `shard_count - 1`. На провайдере, откуда Tuist не может автоматически вывести ссылку, также задайте всем задачам одинаковое значение `TUIST_SHARD_REFERENCE`.
