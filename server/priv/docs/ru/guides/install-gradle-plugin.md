---
{
  "title": "Установка плагина Gradle",
  "titleTemplate": ":title · Руководства · Tuist",
  "description": "Узнайте, как установить и настроить плагин Gradle от Tuist в вашем проекте."
}
---
# Установка плагина Gradle {#install-the-gradle-plugin}

Tuist предоставляет плагин Gradle, который интегрируется с вашим проектом Gradle и включает такие возможности, как <.localized_link href="/guides/features/cache/gradle-cache">удалённое кэширование сборок</.localized_link> и <.localized_link href="/guides/features/build-insights/gradle">аналитика сборок</.localized_link>. Это руководство поможет вам установить и настроить плагин.

Плагин требует Gradle версии 8.12.1 или новее.

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

Команда проведёт вас через аутентификацию, создание или выбор проекта Tuist и генерацию конфигурации для вашего проекта Gradle.

## 2. Подключение плагина {#apply-the-plugin}

После выполнения `tuist init` добавьте плагин Tuist в ваш `settings.gradle.kts`, следуя инструкциям в выводе команды:

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

## 3. Аутентификация команды и непрерывной интеграции {#authenticate}

Хотя `tuist init` выполняет локальную аутентификацию для вас, вашим коллегам и средам <.localized_link href="/guides/integrations/continuous-integration">непрерывной интеграции</.localized_link> потребуется пройти аутентификацию отдельно.

Каждому участнику команды следует выполнить следующую команду, чтобы получить доступ к возможностям Tuist на своём компьютере:

```bash
tuist auth login
```

Если вы используете самостоятельно размещённый или локальный сервер Tuist, укажите тот же базовый URL, который настроен в `tuist.toml`:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

Сохраняйте единообразие в написании имени хоста. Например, учётные данные, сохранённые для `localhost`, отделены от тех, что сохранены для `127.0.0.1`.

Для автоматизированных раннеров следуйте <.localized_link href="/guides/integrations/continuous-integration#authentication">руководству по аутентификации в среде непрерывной интеграции</.localized_link>, чтобы настроить аутентификацию для вашей среды.

## Кэш конфигурации и изолированные проекты {#configuration-cache-and-isolated-projects}

Плагин поддерживает кэш конфигурации Gradle и [изолированные проекты](https://docs.gradle.org/current/userguide/isolated_projects.html). Оставьте плагин в `settings.gradle.kts`; вам не нужно подключать его отдельно к каждому подпроекту.

Tuist не включает эти функции автоматически. Чтобы активировать их, добавьте следующее в `gradle.properties`:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

Ваши скрипты сборки и другие плагины также должны поддерживать эти функции. Gradle сообщает о проблемах совместимости при сохранении кэша конфигурации.

## Справочник по конфигурации {#configuration-reference}

В блоке расширения `tuist` в файле `settings.gradle.kts` доступны следующие параметры:

| Параметр | Тип | Значение по умолчанию | Описание |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (необязательно) | Идентификатор проекта в формате `account/project`. Если не задан, плагин считывает его из `tuist.toml`. |
| `url` | `String?` | `null` | Базовый URL сервера Tuist. Если не задан, по умолчанию используется `"https://tuist.dev"` или значение, определённое в `tuist.toml`. |
| `uploadInBackground` | `Boolean?` | `null` | Определяет, следует ли загружать аналитику сборок и тестов в фоновом режиме. При значении `null` (по умолчанию) загрузка выполняется в фоновом режиме для локальных сборок и в основном потоке на раннерах непрерывной интеграции. |
| `stressNewTests.mode` | `String?` | `null` | `"report"` или `"enforce"`. Повторно запускает тесты, добавленные сборкой, и помечает нестабильные; см. <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">стресс-тестирование новых тестов</.localized_link>. Отключено, если не задано. |

Для локального сервера, использующего URL с протоколом `http://`, разрешите небезопасный протокол только в этой локальной конфигурации:

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

Не включайте `allowInsecureProtocol` для размещённых или других серверов с `https://`.

> [!NOTE]
> **Tuist.toml**
>
> Рекомендуемый способ настройки `project` (и опционально `url`) — через файл `tuist.toml` в корневом каталоге проекта. Таким образом конфигурация будет общей для интерфейса командной строки Tuist и плагина Gradle. При необходимости вы всё ещё можете переопределить эти значения в `settings.gradle.kts`.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP-прокси {#http-proxy}

Если ваша сеть направляет исходящий трафик через HTTP-прокси, см. <.localized_link href="/guides/integrations/http-proxy">руководство по настройке HTTP-прокси</.localized_link>.

## Следующие шаги {#next-steps}

После установки и настройки плагина вы можете включить:

- <.localized_link href="/guides/features/cache/gradle-cache">Удалённый кэш сборок</.localized_link> для обмена артефактами сборки между членами команды и раннерами непрерывной интеграции.
- <.localized_link href="/guides/features/build-insights/gradle">Аналитика сборок</.localized_link> для отслеживания времени выполнения задач и поведения кэша в панели управления Tuist.
- <.localized_link href="/guides/features/test-insights/gradle">Аналитика тестов</.localized_link> для отслеживания производительности тестов и выявления нестабильных тестов.
- <.localized_link href="/guides/features/test-insights/flaky-tests">Нестабильные тесты</.localized_link> для автоматического выявления, отслеживания и изоляции нестабильных тестов.
