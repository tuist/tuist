---
{
  "title": "Install the Hex package",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Learn how to install and configure Tuist's Hex package in your Elixir project."
}
---
# Установка Hex-пакета {#install-the-hex-package}

Tuist предоставляет пакет [Hex](https://hex.pm/packages/tuist_ex) — `tuist_ex`, который интегрируется с вашим проектом на Elixir и позволяет использовать такие функции, как <.localized_link href="/guides/features/build-insights/elixir">аналитика сборки</.localized_link> и <.localized_link href="/guides/features/test-insights/elixir">аналитика тестов</.localized_link>. В этом руководстве показано, как установить и настроить его.

Пакет требует Elixir версии 1.18 или новее. Интерфейс командной строки Tuist не нужен.

## 1. Создание проекта {#create-the-project}

Создайте проект в панели управления Tuist и выберите **Mix (Elixir)** в качестве системы сборки. Его идентификатор `account/project` связывает ваш Mix-проект с ним.

## 2. Добавление пакета {#add-the-package}

Добавьте `tuist_ex` в зависимости вашего файла `mix.exs`:

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

Затем загрузите его:

```bash
mix deps.get
```

`runtime: false` исключает Tuist из работающего приложения. Продолжите с разделом <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Начало работы с Elixir</.localized_link>, чтобы вместе настроить кэширование, аналитику сборки и аналитику тестов. В разделах ниже описаны детали аутентификации и конфигурации.

## 3. Аутентификация команды и непрерывной интеграции {#authenticate}

Каждому участнику команды нужно выполнить следующие действия, чтобы получить доступ к функциям Tuist на своем компьютере:

```bash
mix tuist.login
```

Откроется браузер, где нужно подтвердить авторизацию. Чтобы войти без браузера, передайте свои учетные данные:

```bash
mix tuist.login --email person@example.com --password secret
```

Если вы используете самостоятельно размещенный или локальный сервер Tuist, задайте его базовый URL в `mix.exs` или передайте через `--url`:

```bash
mix tuist.login --url http://localhost:8080
```

Сохраняйте единообразие написания имени хоста. Например, логин, сохраненный для `localhost`, отделен от логина для `127.0.0.1`.

В GitHub Actions, CircleCI и Bitrise этап входа не требуется. При первой отправке отчета задача обменивает токен OpenID Connect провайдера на токен Tuist. <.localized_link href="/guides/integrations/gitforge/github">Подключите ваш репозиторий GitHub</.localized_link> к проекту Tuist и в GitHub Actions предоставьте задаче разрешение `id-token: write`:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix test
```

Для любого другого поставщика удостоверений OpenID Connect, например Fly.io Machines, настройте политику доверия рабочих нагрузок в разделе **Рабочие удостоверения** на странице **Настройки → Аутентификация** вашей учетной записи. Это даст CI доступ ко всем текущим и будущим проектам, принадлежащим этой учетной записи. Установите `TUIST_OIDC_ACCOUNT` в значение учетной записи Tuist, которой принадлежит проект, и передайте свежесгенерированный токен удостоверения с аудиторией политики через `TUIST_OIDC_TOKEN`. Интеграция автоматически выполняет обмен, если нет токена учетной записи или действительного сохраненного логина; `mix tuist.login` также принимает его вне CI. Автоматический обмен повторно использует активную сессию только для того же сервера, учетной записи и предоставленного токена удостоверения. Смена этого удостоверения запускает новый обмен, а пустой токен приводит к ошибке вместо повторного использования предыдущей сессии. Сессии Tuist действуют один час без токенов обновления, поэтому для долгоживущих задач сгенерируйте новый токен удостоверения и снова выполните `mix tuist.login` до истечения срока сессии. Следуйте инструкциям по <.localized_link href="/guides/server/authentication#workload-identity-trust-policies">настройке рабочего удостоверения</.localized_link> и <.localized_link href="/guides/server/authentication#flyio-machines">примеру для Fly.io</.localized_link>.

Pull-запросы из форков не получают токен OpenID Connect, поэтому их запуски не отправляются в отчеты и завершаются успехом или неудачей как обычно. На других провайдерах установите переменную окружения `TUIST_TOKEN` в значение токена учетной записи. Следуйте <.localized_link href="/guides/integrations/continuous-integration#authentication">руководству по аутентификации непрерывной интеграции</.localized_link>, чтобы создать его.

## 4. Продолжайте использовать `mix test` и `mix compile` {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Общая настройка</.localized_link> устанавливает для вас алиасы компиляции и тестирования. `mix test test/my_app_test.exs:12 --trace` сообщает о запуске с тем же выводом и кодом выхода, а интеграция компиляции охватывает сборки, запущенные через `mix test` или `mix phx.server`. Компиляция, которая не находит задач для выполнения, не отправляется в отчет.

Задачи также работают при вызове по собственному имени. Mix запускает такую задачу в окружении `dev`, поэтому для тестового окружения она должна перезапуститься во втором процессе. Добавьте задачи в предпочтительные окружения, чтобы избежать этого:

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## Справочник конфигурации {#configuration-reference}

Следующие параметры доступны в разделе `tuist` настроек проекта в файле `mix.exs`:

| Параметр | Тип | По умолчанию | Описание |
| --- | --- | --- | --- |
| `project` | `String` | нет (обязательно) | Идентификатор проекта в формате `account/project`. |
| `url` | `String` | `"https://tuist.dev"` | Базовый URL сервера Tuist. |
| `cache` | `boolean` или список ключевых слов | отключено | Настройка включает кэширование зависимостей. См. <.localized_link href="/guides/features/cache/elixir">кэш Elixir</.localized_link> для исключений и дополнительных входных данных. |
| `test_retries` | `integer` | `0` | Количество повторных попыток для неуспешных тестов; см. <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">повторные попытки тестов</.localized_link>. |
| `tags` | список `String` | `[]` | Теги, прикрепляемые к каждой сборке; см. <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">пользовательские метаданные</.localized_link>. |
| `values` | карта | `%{}` | Данные в виде пар ключ-значение, прикрепляемые к каждой сборке. |

Переменные окружения имеют приоритет над `mix.exs`:

| Переменная | Описание |
| --- | --- |
| `TUIST_PROJECT` | Идентификатор проекта в формате `account/project`. |
| `TUIST_URL` | Базовый URL сервера Tuist. |
| `TUIST_TOKEN` | Токен для аутентификации вместо сохраненного входа в систему. |
| `TUIST_OIDC_TOKEN` | Новый токен идентификации OpenID Connect, обмениваемый на токен Tuist. Его аудиторией должен быть `tuist` для GitHub Actions и Bitrise или соответствовать политике доверия проекта для других провайдеров. Используется `mix tuist.login` или как запасной вариант, когда нет токена аккаунта или действительного сохраненного входа. |
| `TUIST_OIDC_ACCOUNT` | Идентификатор аккаунта Tuist, которому принадлежит проект. Требуется при обмене токена через политику доверия проекта. Он выбирает среди существующих политик доверия и сам по себе не предоставляет доступ. |
| `TUIST_TEST_RETRIES` | Количество повторных попыток выполнения неуспешных тестов. |
| `TUIST_TAGS` | Теги, разделенные запятыми, прикрепляемые к сборке. |
| `TUIST_VALUES` | Разделенные запятыми пары `key=value`, прикрепляемые к сборке. |
| `TUIST_DEBUG` | Установите значение `1`, чтобы вывести причину, по которой отчет не удалось отправить. |

Отчетность никогда не меняет код выхода `mix test` или `mix compile`. Если отчет не удается отправить, задача ничего не сообщает, если не установлено `TUIST_DEBUG=1`.

## Следующие шаги {#next-steps}

После установки и настройки пакета вы можете использовать:

- <.localized_link href="/guides/features/cache/elixir">Кэширование зависимостей</.localized_link> для повторного использования скомпилированных зависимостей локально и в сборках CI.
- <.localized_link href="/guides/features/build-insights/elixir">Аналитика сборок</.localized_link> для отслеживания времени компиляции, предупреждений и факторов, замедляющих ваши сборки.
- <.localized_link href="/guides/features/test-insights/elixir">Аналитика тестов</.localized_link> для отслеживания производительности тестов вплоть до каждого отдельного теста.
- <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">Нестабильные тесты</.localized_link> для обнаружения и отслеживания тестов, которые периодически завершаются неудачей.
- <.localized_link href="/guides/features/test-sharding/elixir">Шардирование тестов</.localized_link> для распределения ваших тестов между раннерами непрерывной интеграции.
