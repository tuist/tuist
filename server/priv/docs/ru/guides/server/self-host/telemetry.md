---
{
  "title": "Телеметрия",
  "titleTemplate": ":title | Самостоятельное размещение | Сервер | Руководства | Tuist",
  "description": "Мониторинг сервера Tuist с помощью метрик Prometheus, трассировок OpenTelemetry и пересылки логов."
}
---
# Телеметрия {#telemetry}

Tuist предоставляет три взаимодополняющих сигнала наблюдаемости: **метрики** (Prometheus), **трейсы** (OpenTelemetry) и **логи** (совместимые с Loki). Все три опциональны и могут включаться независимо.

## Распределённая трассировка (OpenTelemetry) {#opentelemetry}

Tuist поддерживает [OpenTelemetry](https://opentelemetry.io/) для распределённой трассировки. При включении сервер генерирует трейсы для HTTP-запросов (Phoenix и Bandit), запросов к базе данных (Ecto), исходящих HTTP-вызовов (Finch) и обработки сообщений Broadway. Эти трейсы помогают понять задержки запросов, выявить медленные запросы и отслеживать запросы между сервисами.

### Конфигурация {#opentelemetry-configuration}

Установите следующую переменную окружения, чтобы включить экспорт трейсов:

| Переменная окружения | Описание | Обязательно | По умолчанию | Пример |
| --- | --- | --- | --- | --- |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | gRPC-эндпоинт коллектора OpenTelemetry (например, Grafana Alloy, Jaeger или любой коллектор, совместимый с OTLP) | Нет | | `http://localhost:4317` |

Если эта переменная не задана, трассировка отключена и не создаёт дополнительной нагрузки.

### Инструментируемые библиотеки {#opentelemetry-instrumented-libraries}

Следующие библиотеки автоматически инструментруются при включении трассировки:

- **Bandit** — спаны соединений HTTP-сервера
- **Phoenix** — спаны жизненного цикла запроса (действия контроллеров, LiveView)
- **Ecto** — спаны запросов к базе данных с метаданными запроса
- **Finch** — спаны исходящих запросов HTTP-клиента
- **Broadway** — спаны конвейера обработки сообщений

### Пример настройки с Grafana Alloy {#opentelemetry-alloy-example}

Если вы используете [Grafana Alloy](https://grafana.com/docs/alloy/latest/) в качестве коллектора, настройте его на приём OTLP-трейсов и пересылку их в ваш бэкенд трассировки (например, Grafana Cloud Tempo):

```alloy
otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "0.0.0.0:4317"
  }
  output {
    traces = [otelcol.exporter.otlp.your_backend.input]
  }
}
```

Затем установите `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT`, указав на экземпляр Alloy, например `http://alloy:4317`.

## Пересылка логов (Loki) {#log-forwarding}

Tuist может пересылать логи приложения на эндпоинт, совместимый с [Loki](https://grafana.com/oss/loki/). Это позволяет централизовать логи вместе с метриками и трейсами для полной картины наблюдаемости. Логи отправляются через HTTP API Loki (`/loki/api/v1/push`) и включают метки для `app`, `env` и `level`.

### Конфигурация {#log-forwarding-configuration}

| Переменная окружения | Описание | Обязательно | По умолчанию | Пример |
| --- | --- | --- | --- | --- |
| `TUIST_LOKI_URL` | Базовый URL эндпоинта push API, совместимого с Loki | Нет | | `http://localhost:3100` |

Если эта переменная не задана, пересылка логов отключена.

### Пример настройки с Grafana Alloy {#log-forwarding-alloy-example}

Grafana Alloy может выступать в роли локального ретранслятора логов, используя компонент [`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/):

```alloy
loki.source.api "default" {
  http {
    listen_address = "0.0.0.0"
    listen_port    = 3100
  }
  forward_to             = [loki.write.your_backend.receiver]
  use_incoming_timestamp = true
}

loki.write "your_backend" {
  endpoint {
    url = "https://your-loki-instance/loki/api/v1/push"
    basic_auth {
      username = "your-username"
      password = "your-password"
    }
  }
}
```

Затем установите `TUIST_LOKI_URL=http://alloy:3100`.

Вы также можете направить `TUIST_LOKI_URL` напрямую на экземпляр Loki, если он предоставляет push API.

## Метрики Prometheus {#prometheus-metrics}

Вы можете собирать метрики, полученные сервером Tuist, с помощью [Prometheus](https://prometheus.io/) и инструмента визуализации, такого как [Grafana](https://grafana.com/), чтобы создать пользовательскую панель мониторинга, адаптированную под ваши нужды. Метрики Prometheus доступны через эндпоинт `/metrics` на порту 9091. Параметр [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) в Prometheus следует установить меньше 10 000 секунд (мы рекомендуем 30 секунд, чтобы сбалансировать наблюдаемость и затраты на сбор метрик).

## Мониторинг реальных пользователей {#real-user-monitoring}

Tuist может сообщать о производительности браузера на маркетинговом сайте, в документации и на панели управления, используя Web SDK [Grafana Faro](https://grafana.com/oss/faro/), который встроен в отдаваемый JavaScript. Он фиксирует основные веб-метрики (включая Largest Contentful Paint), необработанные ошибки и просмотры страниц, а затем отправляет их в запускаемый вами [Faro receiver](https://grafana.com/docs/alloy/latest/reference/components/faro/faro.receiver/) — например, компонент `faro.receiver` в Grafana Alloy, который пересылает данные в Loki и Tempo.

### Конфигурация {#real-user-monitoring-configuration}

| Переменная окружения | Описание | Обязательно | По умолчанию | Пример |
| --- | --- | --- | --- | --- |
| `TUIST_FARO_COLLECTOR_URL` | URL, на который браузер отправляет полезные нагрузки Faro | Нет | | `/-/faro` |

> [!NOTE]
> Мониторинг реальных пользователей включается только при установке `TUIST_FARO_COLLECTOR_URL`. Без него браузерная телеметрия не собирается и сторонние скрипты не загружаются.

Путь того же источника, например `/-/faro`, позволяет избежать кросс-доменных запросов и не требует изменений в политике безопасности контента (CSP) браузера. Направьте его на ваш Faro receiver через ingress.

### Что собирается {#real-user-monitoring-collected}

- **Веб-метрики**: LCP, CLS, INP, FCP и TTFB, автоматически фиксируемые браузером
- **Просмотры страниц**: записываются при загрузке и при навигации через Phoenix LiveView
- **Разделы**: каждая полезная нагрузка содержит раздел, который её сгенерировал — `marketing`, `docs`, `dashboard` или `api-docs`
- **Ошибки**: необработанные исключения и неотловленные отклонения промисов

### Вопросы конфиденциальности {#real-user-monitoring-privacy}

- Идентификация пользователя не привязывается: полезные нагрузки не содержат ID пользователя, email или аккаунт
- Сессии не сохраняются между посещениями, поэтому в хранилище браузера ничего не записывается
- Захват консоли отключён, поэтому вывод логов приложения никогда не отправляется из браузера

## Метрики Elixir {#elixir-metrics}

По умолчанию мы включаем метрики среды выполнения Elixir, BEAM, Elixir и некоторых используемых библиотек. Вот некоторые из доступных метрик:

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

Рекомендуем ознакомиться с этими страницами, чтобы узнать, какие метрики доступны и как их использовать.

## Метрики запусков {#runs-metrics}

Набор метрик, связанных с запусками Tuist.

### `tuist_runs_total` (счётчик) {#tuist_runs_total-counter}

Общее количество запусков Tuist.

#### Теги {#tuist-runs-total-tags}

| Тег | Описание |
|--- | ---- |
| `name` | Имя выполненной команды `tuist`, например `build`, `test` и т. д. |
| `is_ci` | Логическое значение, указывающее, выполнялся ли запуск в CI или на машине разработчика. |
| `status` | `0` в случае `success`, `1` в случае `failure`. |

### `tuist_runs_duration_milliseconds` (гистограмма) {#tuist_runs_duration_milliseconds-histogram}

Общая длительность каждого запуска tuist в миллисекундах.

#### Теги {#tuist-runs-duration-miliseconds-tags}

| Тег | Описание |
|--- | ---- |
| `name` | Имя выполненной команды `tuist`, например `build`, `test` и т. д. |
| `is_ci` | Логическое значение, указывающее, выполнялся ли запуск в CI или на машине разработчика. |
| `status` | `0` в случае `success`, `1` в случае `failure`. |

## Метрики кэша {#cache-metrics}

Набор метрик, связанных с кэшем Tuist.

### `tuist_cache_events_total` (счётчик) {#tuist_cache_events_total-counter}

Общее количество событий бинарного кэша.

#### Теги {#tuist-cache-events-total-tags}

| Тег | Описание |
|--- | ---- |
| `event_type` | Может быть `local_hit`, `remote_hit` или `miss`. |

### `tuist_cache_uploads_total` (счётчик) {#tuist_cache_uploads_total-counter}

Количество загрузок в бинарный кэш.

### `tuist_cache_uploaded_bytes` (сумма) {#tuist_cache_uploaded_bytes-sum}

Количество байт, загруженных в бинарный кэш.

### `tuist_cache_downloads_total` (счётчик) {#tuist_cache_downloads_total-counter}

Количество скачиваний из бинарного кэша.

### `tuist_cache_downloaded_bytes` (сумма) {#tuist_cache_downloaded_bytes-sum}

Количество байт, скачанных из бинарного кэша.

---

## Метрики превью {#previews-metrics}

Набор метрик, связанных с функцией превью.

### `tuist_previews_uploads_total` (сумма) {#tuist_previews_uploads_total-counter}

Общее количество загруженных превью.

### `tuist_previews_downloads_total` (сумма) {#tuist_previews_downloads_total-counter}

Общее количество скачанных превью.

---

## Метрики хранилища {#storage-metrics}

Набор метрик, связанных с хранением артефактов в удалённом хранилище (например, s3).

> [!TIP]
> Эти метрики полезны для понимания производительности операций хранения и выявления потенциальных узких мест.


### `tuist_storage_get_object_size_size_bytes` (гистограмма) {#tuist_storage_get_object_size_size_bytes-histogram}

Размер (в байтах) объекта, полученного из удалённого хранилища.

#### Теги {#tuist-storage-get-object-size-size-bytes-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |


### `tuist_storage_get_object_size_duration_miliseconds` (гистограмма) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

Длительность (в миллисекундах) получения размера объекта из удалённого хранилища.

#### Теги {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |


### `tuist_storage_get_object_size_count` (счётчик) {#tuist_storage_get_object_size_count-counter}

Количество запросов размера объекта из удалённого хранилища.

#### Теги {#tuist-storage-get-object-size-count-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (гистограмма) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

Длительность (в миллисекундах) удаления всех объектов из удалённого хранилища.

#### Теги {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Тег | Описание |
|--- | ---- |
| `project_slug` | Слаг проекта, объекты которого удаляются. |


### `tuist_storage_delete_all_objects_count` (счётчик) {#tuist_storage_delete_all_objects_count-counter}

Количество удалений всех объектов проекта из удалённого хранилища.

#### Теги {#tuist-storage-delete-all-objects-count-tags}

| Тег | Описание |
|--- | ---- |
| `project_slug` | Слаг проекта, объекты которого удаляются. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (гистограмма) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

Длительность (в миллисекундах) начала загрузки в удалённое хранилище.

#### Теги {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |

### `tuist_storage_multipart_start_upload_duration_count` (счётчик) {#tuist_storage_multipart_start_upload_duration_count-counter}

Количество начатых загрузок в удалённое хранилище.

#### Теги {#tuist-storage-multipart-start-upload-duration-count-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (гистограмма) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

Длительность (в миллисекундах) получения объекта в виде строки из удалённого хранилища.

#### Теги {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |

### `tuist_storage_get_object_as_string_count` (счётчик) {#tuist_storage_get_object_as_string_count-count}

Количество запросов объекта в виде строки из удалённого хранилища.

#### Теги {#tuist-storage-get-object-as-string-count-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |


### `tuist_storage_check_object_existence_duration_milliseconds` (гистограмма) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

Длительность (в миллисекундах) проверки наличия объекта в удалённом хранилище.

#### Теги {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |

### `tuist_storage_check_object_existence_count` (счётчик) {#tuist_storage_check_object_existence_count-count}

Количество проверок наличия объекта в удалённом хранилище.

#### Теги {#tuist-storage-check-object-existence-count-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (гистограмма) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

Длительность (в миллисекундах) генерации предподписанного URL для скачивания объекта из удалённого хранилища.

#### Теги {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |


### `tuist_storage_generate_download_presigned_url_count` (счётчик) {#tuist_storage_generate_download_presigned_url_count-count}

Количество сгенерированных предподписанных URL для скачивания объекта из удалённого хранилища.

#### Теги {#tuist-storage-generate-download-presigned-url-count-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (гистограмма) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

Длительность (в миллисекундах) генерации предподписанного URL для загрузки части объекта в удалённое хранилище.

#### Теги {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |
| `part_number` | Номер части загружаемого объекта. |
| `upload_id` | Идентификатор многокомпонентной загрузки. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (счётчик) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

Количество сгенерированных предподписанных URL для загрузки части объекта в удалённое хранилище.

#### Теги {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |
| `part_number` | Номер части загружаемого объекта. |
| `upload_id` | Идентификатор многокомпонентной загрузки. |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (гистограмма) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

Длительность (в миллисекундах) завершения загрузки в удалённое хранилище.

#### Теги {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |
| `upload_id` | Идентификатор многокомпонентной загрузки. |


### `tuist_storage_multipart_complete_upload_count` (счётчик) {#tuist_storage_multipart_complete_upload_count-count}

Общее количество завершённых загрузок в удалённое хранилище.

#### Теги {#tuist-storage-multipart-complete-upload-count-tags}

| Тег | Описание |
|--- | ---- |
| `object_key` | Ключ поиска объекта в удалённом хранилище. |
| `upload_id` | Идентификатор многокомпонентной загрузки. |

---

## Метрики аутентификации {#authentication-metrics}

Набор метрик, связанных с аутентификацией.

### `tuist_authentication_token_refresh_error_total` (счётчик) {#tuist_authentication_token_refresh_error_total-counter}

Общее количество ошибок обновления токена.

#### Теги {#tuist-authentication-token-refresh-error-total-tags}

| Тег | Описание |
|--- | ---- |
| `cli_version` | Версия Tuist CLI, в которой произошла ошибка. |
| `reason` | Причина ошибки обновления токена, например `invalid_token_type` или `invalid_token`. |

---

## Метрики проектов {#projects-metrics}

Набор метрик, связанных с проектами.

### `tuist_projects_total` (последнее значение) {#tuist_projects_total-last_value}

Общее количество проектов.

---

## Метрики аккаунтов {#accounts-metrics}

Набор метрик, связанных с аккаунтами (пользователями и организациями).

### `tuist_accounts_organizations_total` (последнее значение) {#tuist_accounts_organizations_total-last_value}

Общее количество организаций.

### `tuist_accounts_users_total` (последнее значение) {#tuist_accounts_users_total-last_value}

Общее количество пользователей.


## Метрики базы данных {#database-metrics}

Набор метрик, связанных с подключением к базе данных.

Метрики пула репозиториев собираются внутри каждые 100 мс и затем передаются в Prometheus по адресу `/metrics`. Метрики `last_value` ниже показывают последнее состояние пула на момент сбора. Метрики нагрузки далее представляют собой суммы, полученные из этих 100-миллисекундных выборок, что позволяет легче обнаруживать кратковременные периоды насыщения, даже если они завершаются до следующего сбора.

### `tuist_repo_pool_checkout_queue_length` (последнее значение) {#tuist_repo_pool_checkout_queue_length-last_value}

Количество запросов к базе данных, находящихся в очереди и ожидающих назначения подключения.

#### Теги {#tuist_repo_pool_checkout_queue_length-tags}

| Тег | Описание |
|--- | ---- |
| `repo` | Репозиторий, который сгенерировал метрику, например `postgres`, `clickhouse_read` или `clickhouse_write`. |
| `database` | Тип базовой базы данных, например `postgres` или `clickhouse`. |

### `tuist_repo_pool_ready_conn_count` (последнее значение) {#tuist_repo_pool_ready_conn_count-last_value}

Количество подключений к базе данных, готовых к выполнению запроса.

#### Теги {#tuist_repo_pool_ready_conn_count-tags}

| Тег | Описание |
|--- | ---- |
| `repo` | Репозиторий, который сгенерировал метрику, например `postgres`, `clickhouse_read` или `clickhouse_write`. |
| `database` | Тип базовой базы данных, например `postgres` или `clickhouse`. |

### `tuist_repo_pool_size` (последнее значение) {#tuist_repo_pool_size-last_value}

Настроенное количество подключений в пуле.

#### Теги {#tuist_repo_pool_size-tags}

| Тег | Описание |
|--- | ---- |
| `repo` | Репозиторий, который сгенерировал метрику, например `postgres`, `clickhouse_read` или `clickhouse_write`. |
| `database` | Тип базовой базы данных, например `postgres` или `clickhouse`. |

### `tuist_repo_pool_checkout_queue_total_samples_sum` (сумма) {#tuist_repo_pool_checkout_queue_total_samples_sum-sum}

Общее количество опросов пула репозиториев (увеличивается на 1 при каждом опросе). Используйте это значение как знаменатель при вычислении процентов загруженности или голодания: `rate(busy_samples) / rate(total_samples)` или `rate(starved_samples) / rate(total_samples)`.

#### Теги {#tuist_repo_pool_checkout_queue_total_samples_sum-tags}

| Тег | Описание |
|--- | ---- |
| `repo` | Репозиторий, который сгенерировал метрику, например `postgres`, `clickhouse_read` или `clickhouse_write`. |
| `database` | Тип базовой базы данных, например `postgres` или `clickhouse`. |

### `tuist_repo_pool_checkout_queue_observed_sum` (сумма) {#tuist_repo_pool_checkout_queue_observed_sum-sum}

Сумма запросов на получение подключения из очереди, наблюдаемых при опросах пула репозиториев. Это полезно для обнаружения кратковременных всплесков конкуренции за пул, которые могут быть не видны только по последнему значению длины очереди.

#### Теги {#tuist_repo_pool_checkout_queue_observed_sum-tags}

| Тег | Описание |
|--- | ---- |
| `repo` | Репозиторий, который сгенерировал метрику, например `postgres`, `clickhouse_read` или `clickhouse_write`. |
| `database` | Тип базовой базы данных, например `postgres` или `clickhouse`. |

### `tuist_repo_pool_checkout_queue_busy_samples_sum` (сумма) {#tuist_repo_pool_checkout_queue_busy_samples_sum-sum}

Количество опросов пула репозиториев, при которых хотя бы один запрос на получение подключения ожидал в очереди.

#### Теги {#tuist_repo_pool_checkout_queue_busy_samples_total-tags}

| Тег | Описание |
|--- | ---- |
| `repo` | Репозиторий, который сгенерировал метрику, например `postgres`, `clickhouse_read` или `clickhouse_write`. |
| `database` | Тип базовой базы данных, например `postgres` или `clickhouse`. |

### `tuist_repo_pool_checkout_queue_starved_samples_sum` (сумма) {#tuist_repo_pool_checkout_queue_starved_samples_sum-sum}

Количество опросов пула репозиториев, при которых запросы на получение подключения стояли в очереди и не было доступных готовых подключений. Устойчивый рост этого показателя обычно означает насыщение пула.

#### Теги {#tuist_repo_pool_checkout_queue_starved_samples_total-tags}

| Тег | Описание |
|--- | ---- |
| `repo` | Репозиторий, который сгенерировал метрику, например `postgres`, `clickhouse_read` или `clickhouse_write`. |
| `database` | Тип базовой базы данных, например `postgres` или `clickhouse`. |

### `tuist_repo_pool_db_connection_connected` (счетчик) {#tuist_repo_pool_db_connection_connected-counter}

Количество установленных подключений к базе данных.

### `tuist_repo_pool_db_connection_disconnected` (счетчик) {#tuist_repo_pool_db_connection_disconnected-counter}

Количество отключенных от базы данных подключений.

#### Теги {#tuist_repo_pool_db_connection_connected_and_disconnected-tags}

| Тег | Описание |
|--- | ---- |
| `tag` | Тег слушателя DBConnection, идентифицирующий репозиторий-источник. |

## Метрики HTTP {#http-metrics}

Набор метрик, связанных с взаимодействием Tuist с другими сервисами по HTTP.

### `tuist_http_request_count` (счетчик) {#tuist_http_request_count-last_value}

Количество исходящих HTTP-запросов.

### `tuist_http_request_duration_nanoseconds_sum` (сумма) {#tuist_http_request_duration_nanoseconds_sum-last_value}

Сумма длительности исходящих запросов (включая время ожидания назначения подключения).

### `tuist_http_request_duration_nanoseconds_bucket` (распределение) {#tuist_http_request_duration_nanoseconds_bucket-distribution}
Распределение длительности исходящих запросов (включая время ожидания назначения подключения).

### `tuist_http_queue_count` (счетчик) {#tuist_http_queue_count-counter}

Количество запросов, полученных из пула.

### `tuist_http_queue_duration_nanoseconds_sum` (сумма) {#tuist_http_queue_duration_nanoseconds_sum-sum}

Время, необходимое для получения подключения из пула.

### `tuist_http_queue_idle_time_nanoseconds_sum` (сумма) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

Время простоя подключения в ожидании получения.

### `tuist_http_queue_duration_nanoseconds_bucket` (распределение) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

Время, необходимое для получения подключения из пула.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (распределение) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

Время простоя подключения в ожидании получения.

### `tuist_http_connection_count` (счетчик) {#tuist_http_connection_count-counter}

Количество установленных подключений.

### `tuist_http_connection_duration_nanoseconds_sum` (сумма) {#tuist_http_connection_duration_nanoseconds_sum-sum}

Время, необходимое для установления подключения к хосту.

### `tuist_http_connection_duration_nanoseconds_bucket` (распределение) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

Распределение времени, необходимого для установления подключения к хосту.

### `tuist_http_send_count` (счетчик) {#tuist_http_send_count-counter}

Количество запросов, отправленных после назначения им подключения из пула.

### `tuist_http_send_duration_nanoseconds_sum` (сумма) {#tuist_http_send_duration_nanoseconds_sum-sum}

Время, необходимое для завершения запросов после назначения им подключения из пула.

### `tuist_http_send_duration_nanoseconds_bucket` (распределение) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

Распределение времени, необходимого для завершения запросов после назначения им подключения из пула.

### `tuist_http_receive_count` (счетчик) {#tuist_http_receive_count-counter}

Количество ответов, полученных на отправленные запросы.

### `tuist_http_receive_duration_nanoseconds_sum` (сумма) {#tuist_http_receive_duration_nanoseconds_sum-sum}

Время, затраченное на получение ответов.

### `tuist_http_receive_duration_nanoseconds_bucket` (распределение) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

Распределение времени, затраченного на получение ответов.

### `tuist_http_queue_available_connections` (последнее значение) {#tuist_http_queue_available_connections-last_value}

Количество доступных подключений в очереди.

### `tuist_http_queue_in_use_connections` (последнее значение) {#tuist_http_queue_in_use_connections-last_value}

Количество используемых подключений в очереди.
