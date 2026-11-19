---
{
  "title": "Установка плагина Gradle",
  "titleTemplate": ":title · Руководства · Tuist",
  "description": "Узнайте, как установить и настроить плагин Gradle от Tuist в вашем проекте."
}
---
# Установка плагина Gradle {#install-the-gradle-plugin}

Tuist предоставляет плагин для Gradle, который интегрируется с вашим проектом и открывает доступ к таким возможностям, как <.localized_link href="/guides/features/cache/gradle-cache">удалённое кэширование сборок</.localized_link> и <.localized_link href="/guides/features/build-insights/gradle">аналитика сборок</.localized_link>. В этом руководстве описаны установка и настройка плагина.

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

Команда проведёт вас через аутентификацию, создание или выбор проекта Tuist и генерацию конфигурации для вашего проекта Gradle.

## 2. Применение плагина {#apply-the-plugin}

После выполнения `tuist init` добавьте плагин Tuist в файл `settings.gradle.kts`, следуя инструкциям в выводе команды:

<!-- @snippet: ./_gradle-plugin-block -->

## 3. Аутентификация команды и непрерывной интеграции {#authenticate}

Хотя `tuist init` выполняет локальную аутентификацию для вас, вашим коллегам и средам <.localized_link href="/guides/integrations/continuous-integration">непрерывной интеграции</.localized_link> потребуется пройти аутентификацию отдельно.

Каждому участнику команды следует выполнить следующую команду, чтобы получить доступ к возможностям Tuist на своём компьютере:

```bash
tuist auth login
```

При использовании собственного или локального сервера Tuist передайте тот же базовый URL, который указан в `tuist.toml`:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

Сохраняйте единообразие в написании имени хоста. Например, учётные данные, сохранённые для `localhost`, отличаются от тех, что сохранены для `127.0.0.1`.

Для автоматизированных раннеров следуйте <.localized_link href="/guides/server/authentication#continuous-integration">руководству по аутентификации в непрерывной интеграции</.localized_link>, чтобы настроить аутентификацию для вашей среды.

## Кэш конфигурации и изолированные проекты {#configuration-cache-and-isolated-projects}

Плагин поддерживает кэш конфигурации Gradle и [изолированные проекты](https://docs.gradle.org/current/userguide/isolated_projects.html). Оставьте подключение плагина в файле `settings.gradle.kts`; применять его отдельно к каждому подпроекту не нужно.

Tuist не включает эти возможности автоматически. Чтобы активировать их, добавьте следующее в файл `gradle.properties`:

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

Задача собирает и проверяет один подписанный APK-файл, а затем публикует его, используя вашу текущую аутентификацию Tuist. Вызов задачи является способом активации: обычные задачи `assemble`, `build` и тестирования не публикуют превью. Дополнительный шаг загрузки через CLI не требуется. Подробнее об условиях использования, воспроизведении кэша и поведении при ошибках читайте в разделе <.localized_link href="/guides/features/previews/gradle">превью для Gradle</.localized_link>.

## Справочник по конфигурации {#configuration-reference}

В блоке расширения `tuist` файла `settings.gradle.kts` доступны следующие параметры:

| Параметр | Тип | По умолчанию | Описание |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (необязательно) | Идентификатор проекта в формате `account/project`. Если не задан, плагин считывает его из файла `tuist.toml`. |
| `url` | `String?` | `null` | Базовый URL сервера Tuist. Если не задан, по умолчанию используется `"https://tuist.dev"` или значение, указанное в файле `tuist.toml`. |
| `uploadInBackground` | `Boolean?` | `null` | Определяет, загружать ли аналитику сборок и тестов в фоновом режиме. При значении `null` (по умолчанию) загрузка выполняется в фоне для локальных сборок и на переднем плане для раннеров непрерывной интеграции. |
| `stressNewTests.mode` | `String?` | `null` | `"report"` или `"enforce"`. Повторно запускает тесты, добавленные сборкой, и помечает нестабильные; см. раздел <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">стресс-тестирование новых тестов</.localized_link>. Отключено, если параметр не задан. |

Для локального сервера, использующего URL с протоколом `http://`, разрешите небезопасный протокол только в этой локальной конфигурации:

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

Не включайте параметр `allowInsecureProtocol` для размещённых серверов или других серверов с протоколом `https://`.

> [!NOTE]
> **Tuist.toml**
>
> Рекомендуемый способ настройки параметров `project` (и опционально `url`) — через файл `tuist.toml` в корне проекта. Так конфигурация будет общей для интерфейса командной строки Tuist и плагина Gradle. При необходимости вы всё ещё можете переопределить эти значения в файле `settings.gradle.kts`.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP-прокси {#http-proxy}

Если ваша сеть направляет исходящий трафик через HTTP-прокси, обратитесь к <.localized_link href="/guides/integrations/http-proxy">руководству по работе с HTTP-прокси</.localized_link>.

## Следующие шаги {#next-steps}

После установки и настройки плагина вы можете включить:

- <.localized_link href="/guides/features/cache/gradle-cache">Удалённый кэш сборок</.localized_link> для обмена артефактами сборки между членами команды и раннерами непрерывной интеграции.
- <.localized_link href="/guides/features/build-insights/gradle">Аналитику сборок</.localized_link> для отслеживания времени выполнения задач и поведения кэша в панели управления Tuist.
- <.localized_link href="/guides/features/test-insights/gradle">Аналитику тестов</.localized_link> для отслеживания производительности тестов и выявления нестабильных тестов.
- <.localized_link href="/guides/features/test-insights/flaky-tests">Нестабильные тесты</.localized_link> для автоматического обнаружения, отслеживания и карантина нестабильных тестов.
