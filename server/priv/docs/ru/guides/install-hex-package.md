---
{
  "title": "Установка Hex-пакета",
  "titleTemplate": ":title · Руководства · Tuist",
  "description": "Узнайте, как установить и настроить Hex-пакет Tuist в вашем Elixir-проекте."
}
---
# Установите Hex-пакет {#install-the-hex-package}

Tuist предоставляет пакет [Hex](https://hex.pm/packages/tuist_ex) — `tuist_ex`, который интегрируется с вашим Elixir-проектом и включает такие возможности, как <.localized_link href="/guides/features/build-insights/elixir">аналитика сборок</.localized_link> и <.localized_link href="/guides/features/test-insights/elixir">аналитика тестов</.localized_link>. В этом руководстве описано, как его установить и настроить.

Пакет требует Elixir 1.18 или новее. Ему не нужен интерфейс командной строки Tuist.

## 1. Создайте проект {#create-the-project}

Создайте проект в панели управления Tuist и выберите **Mix (Elixir)** в качестве системы сборки. Его идентификатор, `account/project`, связывает ваш Mix-проект с ним.

## 2. Добавьте пакет {#add-the-package}

Добавьте `tuist_ex` в зависимости вашего `mix.exs`:

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

`runtime: false` исключает Tuist из работающего приложения. Перейдите к разделу <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Начало работы с Elixir</.localized_link>, чтобы вместе настроить кэширование, аналитику сборок и тестов. Ниже описаны детали аутентификации и конфигурации.

## 3. Аутентифицируйте команду и непрерывную интеграцию {#authenticate}

Каждый участник команды выполняет следующую команду, чтобы получить доступ к возможностям Tuist на своём компьютере:

```bash
mix tuist.login
```

Откроется браузер, где нужно подтвердить авторизацию. Чтобы войти без браузера, передайте учётные данные:

```bash
mix tuist.login --email person@example.com --password secret
```

Если вы используете собственный или локальный сервер Tuist, задайте его базовый URL в `mix.exs` или передайте через `--url`:

```bash
mix tuist.login --url http://localhost:8080
```

Сохраняйте одинаковое написание хоста. Например, логин для `localhost` хранится отдельно от логина для `127.0.0.1`.

В GitHub Actions, CircleCI и Bitrise этап входа не требуется. При первой отправке отчёта задача обменивает токен OpenID Connect провайдера на токен Tuist. <.localized_link href="/guides/integrations/gitforge/github">Подключите репозиторий GitHub</.localized_link> к проекту Tuist и в GitHub Actions дайте задаче разрешение `id-token: write`:

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

Для любого другого провайдера идентификации OpenID Connect, например Fly.io Machines, настройте политику доверия рабочей нагрузки в разделе **Рабочие нагрузки** страницы **Настройки → Аутентификация** аккаунта. Это предоставит CI доступ ко всем текущим и будущим проектам этого аккаунта. Укажите в `TUIST_OIDC_ACCOUNT` аккаунт Tuist, которому принадлежит проект, и передайте свежий токен идентичности с аудиторией политики через `TUIST_OIDC_TOKEN`. Интеграция автоматически выполнит обмен, если нет токена аккаунта или сохранённого входа; `mix tuist.login` также принимает его вне CI. Автоматический обмен повторно использует активную сессию только для того же сервера, аккаунта и переданного токена идентичности. Смена идентичности запускает новый обмен, а пустой токен приведёт к ошибке вместо повторного использования предыдущей сессии. Сессии Tuist действуют один час без токенов обновления, поэтому для долгоживущих задач выпустите новый токен идентичности и снова выполните `mix tuist.login` до истечения срока сессии. Следуйте инструкциям по <.localized_link href="/guides/server/authentication#workload-identity-trust-policies">настройке рабочей нагрузки</.localized_link> и примеру для <.localized_link href="/guides/server/authentication#flyio-machines">Fly.io</.localized_link>.

Пулл-реквесты из форков не получают токен OpenID Connect, поэтому их запуски не отчитываются и проходят или падают как обычно. На других провайдерах установите переменную окружения `TUIST_TOKEN` в токен аккаунта. Чтобы создать его, следуйте <.localized_link href="/guides/integrations/continuous-integration#authentication">руководству по аутентификации в непрерывной интеграции</.localized_link>.

## 4. Продолжайте использовать `mix test` и `mix compile` {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Общая настройка</.localized_link> устанавливает алиасы компиляции и тестирования. `mix test test/my_app_test.exs:12 --trace` отчитывает запуск с тем же выводом и кодом выхода, а интеграция компиляции охватывает сборки, вызванные через `mix test` или `mix phx.server`. Компиляция, которая ничего не делает, не отчитывается.

Задачи также работают при вызове по собственному имени. Mix запускает такую задачу в окружении `dev`, поэтому для тестового окружения она перезапускается во втором процессе. Добавьте задачи в предпочтительные окружения, чтобы избежать этого:

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## Справочник конфигурации {#configuration-reference}

В проекте `mix.exs` доступны следующие опции под ключом `tuist`:

| Опция | Тип | По умолчанию | Описание |
| --- | --- | --- | --- |
| `project` | `String` | нет (обязательно) | Идентификатор проекта в формате `account/project`. |
| `url` | `String` | `"https://tuist.dev"` | Базовый URL сервера Tuist. |
| `cache` | `boolean` или список ключевых слов | отключено | Настройка включает кэширование зависимостей. См. <.localized_link href="/guides/features/cache/elixir">кэш Elixir</.localized_link> для исключений и дополнительных входных данных. |
| `test_retries` | `integer` | `0` | Сколько раз повторять упавшие тесты; см. <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">повторные попытки тестов</.localized_link>. |
| `tags` | список `String` | `[]` | Теги, прикрепляемые к каждой сборке; см. <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">пользовательские метаданные</.localized_link>. |
| `values` | карта | `%{}` | Данные «ключ–значение», прикрепляемые к каждой сборке. |

Переменные окружения имеют приоритет над `mix.exs`:

| Переменная | Описание |
| --- | --- |
| `TUIST_PROJECT` | Идентификатор проекта в формате `account/project`. |
| `TUIST_URL` | Базовый URL сервера Tuist. |
| `TUIST_TOKEN` | Токен для аутентификации вместо сохранённых учётных данных. |
| `TUIST_OIDC_TOKEN` | Свежевыпущенный токен идентификации OpenID Connect, обмениваемый на токен Tuist. Его audience должен быть `tuist` для GitHub Actions и Bitrise или соответствовать политике доверия проекта для других провайдеров. Используется командой `mix tuist.login` или как запасной вариант, если нет токена аккаунта или действительных сохранённых учётных данных. |
| `TUIST_OIDC_ACCOUNT` | Хэндл аккаунта Tuist, которому принадлежит проект. Требуется при обмене токена через политику доверия проекта. Он выбирает среди существующих политик доверия и сам по себе не предоставляет доступ. |
| `TUIST_TEST_RETRIES` | Сколько раз повторять упавшие тесты. |
| `TUIST_TAGS` | Теги, разделённые запятыми, прикрепляемые к сборке. |
| `TUIST_VALUES` | Разделённые запятыми пары `key=value`, прикрепляемые к сборке. |
| `TUIST_DEBUG` | Установите значение `1`, чтобы вывести причину, по которой отчёт не удалось отправить. |

Отправка отчётов никогда не меняет код выхода `mix test` или `mix compile`. Если отчёт не удаётся отправить, задача ничего не выводит, если не установлена переменная `TUIST_DEBUG=1`.

## Дальнейшие шаги {#next-steps}

После установки и настройки пакета вы можете использовать:

- <.localized_link href="/guides/features/cache/elixir">Кэширование зависимостей</.localized_link> для повторного использования скомпилированных зависимостей локально и в сборках CI.
- <.localized_link href="/guides/features/build-insights/elixir">Аналитика сборок</.localized_link> для отслеживания времени компиляции, предупреждений и факторов, замедляющих сборки.
- <.localized_link href="/guides/features/test-insights/elixir">Аналитика тестов</.localized_link> для отслеживания производительности тестов вплоть до каждого отдельного теста.
- <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">Нестабильные тесты</.localized_link> для выявления и отслеживания тестов, которые периодически падают.
- <.localized_link href="/guides/features/test-sharding/elixir">Шардирование тестов</.localized_link> для распределения тестов между раннерами непрерывной интеграции.
