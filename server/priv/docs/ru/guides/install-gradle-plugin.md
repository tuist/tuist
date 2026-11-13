---
{
  "title": "Установка плагина Gradle",
  "titleTemplate": ":title · Руководства · Tuist",
  "description": "Узнайте, как установить и настроить плагин Gradle от Tuist в вашем проекте."
}
---
# Установите плагин Gradle {#install-the-gradle-plugin}

Tuist предоставляет плагин Gradle, который интегрируется с вашим проектом Gradle и включает такие возможности, как <.localized_link href="/guides/features/cache/gradle-cache">удалённое кэширование сборок</.localized_link> и <.localized_link href="/guides/features/build-insights/gradle">аналитика сборок</.localized_link>. Это руководство поможет вам установить и настроить плагин.

Плагин требует Gradle 8.12.1 или новее.

## 1. Инициализируйте Tuist {#initialize-tuist}

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

## 2. Подключите плагин {#apply-the-plugin}

После выполнения `tuist init` добавьте плагин Tuist в ваш `settings.gradle.kts`, как указано в выводе команды:

<!-- @snippet: ./_gradle-plugin-block -->

## 3. Аутентифицируйте команду и непрерывную интеграцию {#authenticate}

Хотя `tuist init` выполняет локальную аутентификацию для вас, вашим коллегам и средам <.localized_link href="/guides/integrations/continuous-integration">непрерывной интеграции</.localized_link> потребуется пройти аутентификацию отдельно.

Каждому участнику команды следует выполнить следующее, чтобы получить доступ к возможностям Tuist на своём компьютере:

```bash
tuist auth login
```

Если вы используете самостоятельно размещённый или локальный сервер Tuist, передайте тот же базовый URL, который настроен в `tuist.toml`:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

Сохраняйте единообразие написания имени хоста. Например, учётные данные, сохранённые для `localhost`, отличаются от тех, что сохранены для `127.0.0.1`.

Для автоматизированных раннеров следуйте <.localized_link href="/guides/server/authentication#continuous-integration">руководству по аутентификации в непрерывной интеграции</.localized_link>, чтобы настроить аутентификацию для вашей среды.

## Кэш конфигурации и изолированные проекты {#configuration-cache-and-isolated-projects}

Плагин поддерживает кэш конфигурации Gradle и [изолированные проекты](https://docs.gradle.org/current/userguide/isolated_projects.html). Оставьте подключение плагина в `settings.gradle.kts`; применять его отдельно к каждому подпроекту не нужно.

Tuist не включает эти возможности автоматически. Чтобы активировать их, добавьте следующее в `gradle.properties`:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

Ваши скрипты сборки и другие плагины также должны поддерживать эти возможности. Gradle сообщает о проблемах совместимости при сохранении кэша конфигурации.

## Публикация превью {#publish-previews}

Для модулей Android-приложений плагин регистрирует задачи `tuistShare<Variant>`:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

Задача собирает и проверяет один подписанный APK, затем публикует его с использованием вашей текущей аутентификации Tuist. Вызов задачи является способом активации: обычные задачи `assemble`, `build` и тестирования не публикуют превью. Дополнительный шаг загрузки через CLI не требуется. См. <.localized_link href="/guides/features/previews/gradle">превью Gradle</.localized_link> для получения информации о требованиях, воспроизведении кэша и поведении при сбоях.

## Справочник по конфигурации {#configuration-reference}

Следующие параметры доступны в блоке расширения `tuist` в файле `settings.gradle.kts`:

| Параметр | Тип | По умолчанию | Описание |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (необязательно) | Идентификатор проекта в формате `account/project`. Если не задан, плагин считывает его из `tuist.toml`. |
| `url` | `String?` | `null` | Базовый URL сервера Tuist. Если не задан, по умолчанию используется `"https://tuist.dev"` или значение, определённое в `tuist.toml`. |
| `uploadInBackground` | `Boolean?` | `null` | Загружать аналитику сборок и тестов в фоновом режиме. При значении `null` (по умолчанию) загрузка выполняется в фоновом режиме для локальных сборок и в основном потоке на раннерах непрерывной интеграции. |
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
> Рекомендуемый способ настройки `project` (и опционально `url`) — через файл `tuist.toml` в корне проекта. Таким образом конфигурация будет общей для интерфейса командной строки Tuist и плагина Gradle. При необходимости вы всё ещё можете переопределить эти значения в `settings.gradle.kts`.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP-прокси {#http-proxy}

Если ваша сеть направляет исходящий трафик через HTTP-прокси, см. <.localized_link href="/guides/integrations/http-proxy">руководство по HTTP-прокси</.localized_link>.

## Следующие шаги {#next-steps}

После установки и настройки плагина вы можете включить:

- <.localized_link href="/guides/features/cache/gradle-cache">Удалённый кэш сборок</.localized_link> для обмена артефактами сборки между членами команды и раннерами непрерывной интеграции.
- <.localized_link href="/guides/features/build-insights/gradle">Аналитику сборок</.localized_link> для отслеживания времени выполнения задач и поведения кэша в панели управления Tuist.
- <.localized_link href="/guides/features/test-insights/gradle">Аналитику тестов</.localized_link> для отслеживания производительности тестов и обнаружения нестабильных тестов.
- <.localized_link href="/guides/features/test-insights/flaky-tests">Нестабильные тесты</.localized_link> для автоматического обнаружения, отслеживания и карантина нестабильных тестов.
