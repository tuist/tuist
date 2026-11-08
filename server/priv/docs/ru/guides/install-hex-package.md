---
{
  "title": "Установка Hex-пакета",
  "titleTemplate": ":title · Руководства · Tuist",
  "description": "Узнайте, как установить и настроить Hex-пакет Tuist в вашем Elixir-проекте."
}
---
# Установите Hex-пакет {#install-the-hex-package}

Tuist предоставляет пакет [Hex](https://hex.pm/packages/tuist_ex) — `tuist_ex`, который интегрируется с вашим Elixir-проектом и включает такие возможности, как <.localized_link href="/guides/features/build-insights/elixir">аналитика сборок</.localized_link> и <.localized_link href="/guides/features/test-insights/elixir">аналитика тестов</.localized_link>. В этом руководстве описаны шаги по установке и настройке.

Пакет требует Elixir версии 1.18 или новее. Командный интерфейс Tuist не нужен.

## 1. Создайте проект {#create-the-project}

Создайте проект в панели управления Tuist и выберите **Mix (Elixir)** в качестве системы сборки. Его идентификатор, `account/project`, связывает ваш Mix-проект с проектом в Tuist.

## 2. Добавьте пакет {#add-the-package}

Добавьте `tuist_ex` в зависимости вашего файла `mix.exs`:

<!-- @snippet: ./_tuist-ex-dependency -->

Затем загрузите его:

```bash
mix deps.get
```

`runtime: false` исключает Tuist из работающего приложения. Перейдите к разделу <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Начало работы с Elixir</.localized_link>, чтобы вместе настроить кэширование, аналитику сборок и аналитику тестов. Разделы ниже описывают аутентификацию и детали конфигурации.

## 3. Аутентифицируйте команду и непрерывную интеграцию {#authenticate}

Каждый участник команды выполняет следующую команду, чтобы получить доступ к возможностям Tuist на своём компьютере:

```bash
mix tuist.login
```

Команда выводит короткий код для входа, открывает браузер, куда нужно ввести этот код, и ожидает авторизации. Чтобы войти без браузера, передайте учётные данные:

```bash
mix tuist.login --email person@example.com --password secret
```

Если вы используете собственный или локальный сервер Tuist, задайте его базовый URL в `mix.exs` или передайте через `--url`:

```bash
mix tuist.login --url http://localhost:8080
```

Сохраняйте единообразие в написании хоста. Например, логин, сохранённый для `localhost`, отличается от логина для `127.0.0.1`.

В GitHub Actions, CircleCI и Bitrise этап входа не требуется. При первой отправке отчёта задача обменивает токен OpenID Connect провайдера на токен Tuist. <.localized_link href="/guides/integrations/gitforge/github">Подключите репозиторий GitHub</.localized_link> к проекту Tuist и предоставьте задаче в GitHub Actions разрешение `id-token: write`:

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

Для любого другого провайдера удостоверений OpenID Connect, например Fly.io Machines, настройте политику доверия рабочих удостоверений в разделе **Рабочие удостоверения** на странице **Настройки → Аутентификация** вашего аккаунта. Это даёт CI доступ ко всем текущим и будущим проектам этого аккаунта. Укажите в `TUIST_OIDC_ACCOUNT` аккаунт Tuist, которому принадлежит проект, и передайте свежий токен удостоверения с аудиторией политики через `TUIST_OIDC_TOKEN`. Интеграция автоматически обменивает его, если нет токена аккаунта или действующего сохранённого логина; `mix tuist.login` также принимает его вне CI. Автоматический обмен повторно использует незавершённую сессию только для того же сервера, аккаунта и переданного токена удостоверения. Смена удостоверения запускает новый обмен, а пустой токен приводит к ошибке вместо повторного использования предыдущей сессии. Сессии Tuist действуют один час без токенов обновления, поэтому для долгоживущих задач выпустите новый токен удостоверения и снова выполните `mix tuist.login` до истечения срока сессии. Следуйте инструкциям по <.localized_link href="/guides/server/authentication#workload-identity-trust-policies">настройке рабочего удостоверения</.localized_link> и <.localized_link href="/guides/server/authentication#flyio-machines">примеру для Fly.io</.localized_link>.

Pull-запросы из форков не получают токен OpenID Connect, поэтому их запуски не отправляются в отчёты и завершаются успехом или неудачей как обычно. На других провайдерах установите переменную окружения `TUIST_TOKEN` в токен аккаунта. Следуйте <.localized_link href="/guides/server/authentication#continuous-integration">руководству по аутентификации непрерывной интеграции</.localized_link>, чтобы создать его.

## 4. Продолжайте использовать `mix test` и `mix compile` {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Общая настройка</.localized_link> устанавливает алиасы компиляции и тестирования. `mix test test/my_app_test.exs:12 --trace` сообщает о запуске с тем же выводом и кодом выхода, а интеграция компиляции охватывает сборки, запускаемые через `mix test` или `mix phx.server`. Если компиляция не находит работы, отчёт не отправляется.

Задачи также работают при вызове по собственному имени. Mix запускает такую задачу в среде `dev`, поэтому для среды тестирования ей приходится запускаться заново во втором процессе. Добавьте задачи в предпочтительные среды, чтобы пропустить это:

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
| `test_retries` | `integer` | `0` | Сколько раз повторять упавшие тесты; см. <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">повторные запуски тестов</.localized_link>. |
| `tags` | список `String` | `[]` | Теги, прикрепляемые к каждой сборке; см. <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">пользовательские метаданные</.localized_link>. |
| `values` | карта | `%{}` | Данные «ключ-значение», прикрепляемые к каждой сборке. |

Переменные окружения имеют приоритет над `mix.exs`:

| Переменная | Описание |
| --- | --- |
| `TUIST_PROJECT` | Идентификатор проекта в формате `account/project`. |
| `TUIST_URL` | Базовый URL сервера Tuist. |
| `TUIST_TOKEN` | Токен для аутентификации вместо сохранённого входа. |
| `TUIST_OIDC_TOKEN` | Свежевыпущенный токен удостоверения OpenID Connect, обмениваемый на токен Tuist. Его аудиторией должно быть значение `tuist` для GitHub Actions и Bitrise или совпадать с рабочей идентичностью аккаунта для других провайдеров. Используется командой `mix tuist.login` или как запасной вариант, если нет токена аккаунта или действительного сохранённого входа. |
| `TUIST_OIDC_ACCOUNT` | Идентификатор аккаунта Tuist, которому принадлежит проект. Требуется при обмене токена через рабочую идентичность аккаунта. Он выбирает среди существующих рабочих идентичностей и сам по себе не предоставляет доступ. |
| `TUIST_TEST_RETRIES` | Количество повторных попыток запуска упавших тестов. |
| `TUIST_TAGS` | Теги, прикрепляемые к сборке, разделённые запятыми. |
| `TUIST_VALUES` | Пары `key=value`, разделённые запятыми, прикрепляемые к сборке. |
| `TUIST_DEBUG` | Установите значение `1`, чтобы вывести причину, по которой отчёт не удалось отправить. |

Отправка отчётов никогда не меняет код выхода команд `mix test` или `mix compile`. Если отчёт не удаётся отправить, задача ничего не выводит, если не установлена переменная `TUIST_DEBUG=1`.

## Дальнейшие шаги {#next-steps}

После установки и настройки пакета вы можете использовать:

- <.localized_link href="/guides/features/cache/elixir">Кэширование зависимостей</.localized_link> для повторного использования скомпилированных зависимостей локально и в сборках CI.
- <.localized_link href="/guides/features/build-insights/elixir">Аналитика сборок</.localized_link> для отслеживания времени компиляции, предупреждений и факторов, замедляющих сборки.
- <.localized_link href="/guides/features/test-insights/elixir">Аналитика тестов</.localized_link> для отслеживания производительности тестов вплоть до каждого отдельного теста.
- <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">Нестабильные тесты</.localized_link> для обнаружения и отслеживания тестов, которые периодически падают.
- <.localized_link href="/guides/features/test-sharding/elixir">Разделение тестов</.localized_link> для распределения тестов между раннерами непрерывной интеграции.
