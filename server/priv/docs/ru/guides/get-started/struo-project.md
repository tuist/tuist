---
{
  "title": "Проект Struo",
  "titleTemplate": ":title · Начало работы · Руководства · Tuist",
  "description": "Подключите Struo к Tuist для общего кэширования, оперативной аналитики сборок и тестов, шардирования тестов и предварительного просмотра приложений."
}
---
# Проект Struo {#struo-project}

<a id="once-project"></a>

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/struo-project
```

:::

[Struo](https://struo.run) запускает кешируемые скрипты и графы сборки. Подключите его к Tuist, чтобы делиться результатами кеша между машинами, отслеживать запуски в реальном времени и публиковать приложения для тестирования вашей командой. Сохраните существующие исходные коды проекта и определения сборки; интеграция настраивается в файле `struo.toml`.

## Предварительные требования

- Установлен [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) или более поздняя версия, а также имеется рабочее пространство или кешируемый скрипт. Следуйте [руководству по установке](https://struo.run/docs/guide/getting-started) или зафиксируйте версию через mise:

  ```bash
  mise use -g github:tuist/struo@1.0.0
  ```

- Аккаунт Tuist. Для интеграции со Struo CLI Tuist не требуется.

## Обновление с Once {#upgrading-from-once}

Struo — это новое название Once. Переименуйте файлы `once.toml` в `struo.toml`, обновите привязки версий в mise с `github:tuist/once` на `github:tuist/struo` и замените команды `once` на `struo`. Обновите заголовки скриптов с `# once` на `# struo` и shebang на `#!/usr/bin/env -S struo exec -- bash`. Переименуйте переменные окружения `ONCE_*` в `STRUO_*`, например `STRUO_CACHE_PROVIDER`; учетные данные Tuist по-прежнему используют `TUIST_TOKEN`.

Замените entries `.once/` в файлах игнорирования на `.struo/`. Результаты теперь сохраняются в `.struo/out/`, а общий локальный кеш контента использует `$XDG_CACHE_HOME/struo/cas` (по умолчанию `~/.cache/struo/cas`). Ключи кеша и локальное хранилище используют новое имя, поэтому после обновления ожидайте холодный локальный кеш вместо переноса старых записей. Войдите снова с помощью `struo auth login --provider tuist`.

Переименование не меняет endpoints совместимости Tuist: отчетность в реальном времени по-прежнему использует `once.events.v1`, а существующие маршруты `/api/.../once` остаются поддерживаемыми. См. [руководство по переименованию в upstream](https://struo.run/changelog/2026-11-18-once-is-now-struo).

## Подключение проекта {#connect-the-project}

Из корня вашего репозитория выполните:

```bash
struo connect --provider tuist --create
```

При необходимости Struo выполнит вход, создаст проект Tuist в вашем личном аккаунте и запишет привязку провайдера в `struo.toml`. См. раздел [Подключение проекта](https://struo.run/docs/guide/infrastructure/connect), чтобы выбрать другой аккаунт или существующий проект.

Для существующего проекта Tuist настройте провайдера и привязку кеша самостоятельно:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

Замените `acme` и `app` на идентификаторы вашего аккаунта и проекта, затем выполните аутентификацию:

```bash
struo auth login --provider tuist
```

Зафиксируйте `struo.toml` в системе контроля версий, чтобы ваши коллеги и CI использовали назначение, а не ваши учетные данные. Каждый разработчик входит в систему на своей машине.

## Общий кеш

Локальный кеш помогает только той машине, которая его заполнила. При настроенном Tuist Struo может восстанавливать совпадающие результаты, созданные другим разработчиком или CI, вместо повторного выполнения той же работы.

Запустите ваш кешируемый скрипт или цель графа как обычно:

```bash
struo build MyApplication
```

Откройте **Struo Cache** в панели управления, чтобы просмотреть активность удаленного кеша. См. раздел <.localized_link href="/guides/features/cache/struo">Кеш Struo</.localized_link> для настройки и проверки повторного использования между машинами.

## Аналитика сборок

Struo выводит ссылку на панель управления при начале запуска. Откройте её, чтобы отслеживать граф, статус действий и решения кеша по мере выполнения запуска. Используйте раздел **Сборки** для сравнения производительности локально и в CI, а также для расследования неудачных действий. Сохраняйте логи CI для полного вывода процесса; ingestion сырых логов действий в настоящее время недоступна.

См. раздел <.localized_link href="/guides/features/build-insights/struo">Аналитика сборок Struo</.localized_link>, чтобы узнать, что записывается и как получить доступ из агентов кодирования или Grafana.

## Аналитика тестов и шардирование

Запустите цели тестов Struo:

```bash
struo test
```

Откройте раздел **Тесты**, чтобы проверить reported suites, cases, длительность и сбои. Результаты зависят от возможностей отчетности цели теста; действие, запускающее процесс теста, не автоматически создает отчет по каждому case.

Когда suite превышает возможности одной машины, создайте план hosted shard и распределите его batches across CI workers. См. разделы <.localized_link href="/guides/features/test-insights/struo">Аналитика тестов Struo</.localized_link> и <.localized_link href="/guides/features/test-sharding/struo">Шардирование тестов Struo</.localized_link>.

## Previews и размер bundle

Добавьте привязку artifacts к тому же провайдеру, чтобы публиковать поддерживаемые приложения для Android, симулятора Apple и macOS:

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
struo artifact publish MyApplication --track review
```

Возвращенная ссылка открывает previews вашего проекта; обработка может занять некоторое время. См. раздел <.localized_link href="/guides/features/previews/struo">Previews Struo</.localized_link> для требований к подписи и опциональной публикации после сборок.

Для отслеживания размера bundle используйте CLI Tuist отдельно против собранного `.app`, `.ipa`, `.xcarchive`, `.apk` или `.aab`. Следуйте <.localized_link href="/guides/features/bundle-insights">руководству по аналитике bundle для Apple или Android</.localized_link>; публикация artifact Struo не автоматически загружает отчет о размере bundle.

## Непрерывная интеграция

Используйте токен аккаунта, авторизованный для операций проекта, в `TUIST_TOKEN`, или аутентифицируйтесь через OpenID Connect identity поддерживаемого провайдера CI:

```bash
struo auth login --provider tuist --no-browser
struo build MyApplication
struo test
```

В GitHub Actions предоставьте задаче права `id-token: write` и `contents: read`. См. пример в разделе <.localized_link href="/guides/integrations/continuous-integration#struo">Struo в непрерывной интеграции</.localized_link>. Личный вход разработчика не является учетными данными для CI.

## Удаленное выполнение

Аккаунты с включенным удаленным выполнением могут также запускать подходящие действия команд графа на Linux-воркерах Tuist. Это отдельно от обмена результатами кеша и от запуска всего workflow CI. См. раздел <.localized_link href="/guides/features/runners/struo">Удаленное выполнение Struo</.localized_link> для требований к воркерам и настройки.
