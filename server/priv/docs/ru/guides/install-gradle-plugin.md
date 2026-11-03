---
{
  "title": "Установка плагина Gradle",
  "titleTemplate": ":title · Руководства · Tuist",
  "description": "Узнайте, как установить и настроить плагин Gradle от Tuist в вашем проекте."
}
---
# Установка плагина Gradle {#install-the-gradle-plugin}

Tuist предоставляет плагин Gradle, который интегрируется с вашим проектом Gradle и позволяет использовать такие возможности, как <.localized_link href="/guides/features/cache/gradle-cache">удаленное кэширование сборок</.localized_link> и <.localized_link href="/guides/features/build-insights/gradle">аналитика сборок</.localized_link>. В этом руководстве описаны шаги по установке и настройке плагина.

Для работы плагина требуется Gradle версии 8.12.1 или новее.

## 1. Инициализация Tuist {#initialize-tuist}

Выполните следующую команду в корневом каталоге вашего проекта Gradle:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

Команда проведет вас через процесс аутентификации, создания или выбора проекта Tuist, а также генерации конфигурации для вашего проекта Gradle.

## 2. Подключение плагина {#apply-the-plugin}

После выполнения `tuist init` вам нужно добавить плагин Tuist в ваш файл `settings.gradle.kts`, следуя инструкциям из вывода команды:

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

## 3. Аутентификация команды и непрерывной интеграции {#authenticate}

Хотя `tuist init` выполняет локальную аутентификацию для вас, вашим коллегам и средам <.localized_link href="/guides/integrations/continuous-integration">непрерывной интеграции</.localized_link> потребуется пройти аутентификацию отдельно.

Каждому участнику команды следует выполнить следующую команду, чтобы получить доступ к возможностям Tuist на своем компьютере:

```bash
tuist auth login
```

Если вы используете самостоятельно размещенный или локальный сервер Tuist, укажите тот же базовый URL, что настроен в `tuist.toml`:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

Следите за единообразием написания имени хоста. Например, данные входа, сохраненные для `localhost`, отделены от данных, сохраненных для `127.0.0.1`.

Для автоматизированных раннеров следуйте <.localized_link href="/guides/integrations/continuous-integration#authentication">руководству по аутентификации в среде непрерывной интеграции</.localized_link>, чтобы настроить аутентификацию для вашей среды.

## Кэш конфигурации и изолированные проекты {#configuration-cache-and-isolated-projects}

Плагин поддерживает кэш конфигурации Gradle и [изолированные проекты](https://docs.gradle.org/current/userguide/isolated_projects.html). Оставьте подключение плагина в файле `settings.gradle.kts`; вам не нужно применять его отдельно к каждому подпроекту.

Tuist не включает эти функции автоматически. Чтобы активировать их, добавьте следующее в файл `gradle.properties`:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

Ваши скрипты сборки и другие плагины также должны поддерживать эти функции. Gradle сообщает о проблемах совместимости при сохранении кэша конфигурации.

## Публикация превью {#publish-previews}

Для модулей Android-приложений плагин регистрирует задачи `tuistShare<Variant>`:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

Задача собирает и проверяет один подписанный APK-файл, а затем публикует его, используя вашу существующую аутентификацию Tuist. Вызов задачи является способом активации: обычные задачи `assemble`, `build` и тестирования не публикуют превью. Дополнительный шаг загрузки через CLI не требуется. См. раздел <.localized_link href="/guides/features/previews/gradle">превью для Gradle</.localized_link>, чтобы узнать о требованиях, воспроизведении кэша и поведении при сбоях.

## Справочник по конфигурации {#configuration-reference}

В блоке расширения `tuist` в файле `settings.gradle.kts` доступны следующие параметры:

| Параметр | Тип | По умолчанию | Описание |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (необязательно) | Идентификатор проекта в формате `account/project`. Если не задан, плагин считывает его из файла `tuist.toml`. |
| `url` | `String?` | `null` | Базовый URL сервера Tuist. Если не задан, по умолчанию используется `"https://tuist.dev"` или значение, определенное в файле `tuist.toml`. |
| `uploadInBackground` | `Boolean?` | `null` | Определяет, загружать ли аналитику сборок и тестов в фоновом режиме. При значении `null` (по умолчанию) загрузка выполняется в фоновом режиме для локальных сборок и в основном потоке на раннерах непрерывной интеграции. |
| `stressNewTests.mode` | `String?` | `null` | `"report"` или `"enforce"`. Повторно запускает тесты, добавленные сборкой, и помечает те, которые оказываются нестабильными; см. раздел <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">стресс-тестирование новых тестов</.localized_link>. Отключено, если не задано. |

Для локального сервера, использующего URL с протоколом `http://`, разрешите небезопасный протокол только в этой локальной конфигурации:

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

Не включайте параметр `allowInsecureProtocol` для размещенных или других серверов с протоколом `https://`.

> [!NOTE]
> **Tuist.toml**
>
> Рекомендуемый способ настройки параметров `project` (и опционально `url`) — через файл `tuist.toml` в корневом каталоге проекта. Таким образом конфигурация будет общей для интерфейса командной строки Tuist и плагина Gradle. При необходимости вы все еще можете переопределить эти значения в файле `settings.gradle.kts`.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP-прокси {#http-proxy}

Если ваша сеть направляет исходящий трафик через HTTP-прокси, см. <.localized_link href="/guides/integrations/http-proxy">руководство по настройке HTTP-прокси</.localized_link>.

## Следующие шаги {#next-steps}

После установки и настройки плагина вы можете включить:

- <.localized_link href="/guides/features/cache/gradle-cache">Удаленный кэш сборок</.localized_link>, чтобы делиться артефактами сборки с командой и раннерами непрерывной интеграции.
- <.localized_link href="/guides/features/build-insights/gradle">Аналитику сборок</.localized_link>, чтобы отслеживать время выполнения задач и поведение кэша в панели управления Tuist.
- <.localized_link href="/guides/features/test-insights/gradle">Аналитику тестов</.localized_link>, чтобы отслеживать производительность тестов и выявлять нестабильные тесты.
- <.localized_link href="/guides/features/test-insights/flaky-tests">Нестабильные тесты</.localized_link>, чтобы автоматически обнаруживать, отслеживать и помещать в карантин нестабильные тесты.
