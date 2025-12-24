---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# Телеметрия {#telemetry}

Вы можете получить метрики, собранные сервером Tuist, используя
[Prometheus](https://prometheus.io/) и инструмент визуализации, такой как
[Grafana](https://grafana.com/), чтобы создать пользовательскую панель,
соответствующую вашим потребностям. Метрики Prometheus обслуживаются через
конечную точку `/metrics` на порту 9091. Интервал
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
в Prometheus должен быть меньше 10_000 секунд (мы рекомендуем оставить значение
по умолчанию 15 секунд).

## Аналитика PostHog {#posthog-analytics}

Tuist интегрируется с [PostHog](https://posthog.com/) для аналитики поведения
пользователей и отслеживания событий. Это позволит вам понять, как пользователи
взаимодействуют с вашим сервером Tuist, отследить использование функций и
получить представление о поведении пользователей на маркетинговом сайте, панели
управления и в документации API.

### Конфигурация {#posthog-configuration}

Интеграция с PostHog не является обязательной и может быть включена путем
установки соответствующих переменных окружения. После настройки Tuist будет
автоматически отслеживать события, просмотры страниц и путешествия
пользователей.

| Переменная среды        | Описание                       | Требуется | По умолчанию | Пример                                            |
| ----------------------- | ------------------------------ | --------- | ------------ | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | Ваш ключ API проекта PostHog   | Нет       |              | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | URL конечной точки PostHog API | Нет       |              | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
Аналитика включается только в том случае, если настроены и
`TUIST_POSTHOG_API_KEY`, и `TUIST_POSTHOG_URL`. Если одна из переменных
отсутствует, события аналитики не будут отправляться.
<!-- -->
:::

### Характеристики {#posthog-features}

Если включен PostHog, Tuist автоматически отслеживает:

- **Идентификация пользователей**: Пользователи идентифицируются по их
  уникальному идентификатору и адресу электронной почты
- **Псевдоним пользователя**: Для облегчения идентификации пользователей они
  называются по имени учетной записи.
- **Групповая аналитика**: Пользователи группируются по выбранному проекту и
  организации для сегментированной аналитики
- **Разделы страницы**: События включают суперсвойства, указывающие, какой
  раздел приложения их породил:
  - `маркетинг` - События с маркетинговых страниц и публичного контента
  - `приборная панель` - События из основной приборной панели приложения и
    аутентифицированных областей
  - `api-docs` - События со страниц документации API
- **Просмотры страниц**: Автоматическое отслеживание навигации по странице с
  помощью Phoenix LiveView
- **Пользовательские события**: События, специфичные для приложения, для
  использования функций и взаимодействия с пользователем

### Соображения конфиденциальности {#posthog-privacy}

- Для аутентифицированных пользователей PostHog использует уникальный
  идентификатор пользователя в качестве отличительного идентификатора и включает
  его адрес электронной почты.
- Для анонимных пользователей PostHog использует постоянство только в памяти,
  чтобы не хранить данные локально.
- Все аналитические системы уважают конфиденциальность пользователей и следуют
  лучшим практикам защиты данных
- Данные PostHog обрабатываются в соответствии с политикой конфиденциальности
  PostHog и вашей конфигурацией.

## Метрики Elixir {#elixir-metrics}

По умолчанию мы включаем метрики среды выполнения Elixir, BEAM, Elixir и
некоторых используемых библиотек. Ниже перечислены некоторые метрики, которые вы
можете ожидать увидеть:

- [Приложение](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Феникс](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Экто](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Обан] (https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

Мы рекомендуем заглянуть на эти страницы, чтобы узнать, какие метрики доступны и
как их использовать.

## Метрики выполнения {#runs-metrics}

Набор метрик, связанных с Tuist Runs.

### `tuist_runs_total` (счетчик) {#tuist_runs_total-counter}

Общее количество туистских пробегов.

#### Теги {#tuist-runs-total-tags}

| Тег      | Описание                                                                                   |
| -------- | ------------------------------------------------------------------------------------------ |
| `имя`    | Имя команды `tuist`, которая была запущена, например `build`, `test`, и т. д.              |
| `is_ci`  | Булево значение, указывающее, является ли исполнитель машиной CI или машиной разработчика. |
| `статус` | `0` в случае `успеха`, `1` в случае `неудачи`.                                             |

### `tuist_runs_duration_milliseconds` (гистограмма) {#tuist_runs_duration_milliseconds-histogram}

Общая продолжительность выполнения каждого туиста в миллисекундах.

#### Теги {#tuist-runs-duration-miliseconds-tags}

| Тег      | Описание                                                                                   |
| -------- | ------------------------------------------------------------------------------------------ |
| `имя`    | Имя команды `tuist`, которая была запущена, например `build`, `test`, и т. д.              |
| `is_ci`  | Булево значение, указывающее, является ли исполнитель машиной CI или машиной разработчика. |
| `статус` | `0` в случае `успеха`, `1` в случае `неудачи`.                                             |

## Метрики кэша {#cache-metrics}

Набор метрик, связанных с кэшем Tuist Cache.

### `tuist_cache_events_total` (счетчик) {#tuist_cache_events_total-counter}

Общее количество событий двоичного кэша.

#### Теги {#tuist-cache-events-total-tags}

| Тег           | Описание                                                   |
| ------------- | ---------------------------------------------------------- |
| `тип события` | Может быть любой из `local_hit`, `remote_hit`, или `miss`. |

### `tuist_cache_uploads_total` (счетчик) {#tuist_cache_uploads_total-counter}

Количество загрузок в двоичный кэш.

### `tuist_cache_uploaded_bytes` (sum) {#tuist_cache_uploaded_bytes-sum}

Количество байт, загруженных в двоичный кэш.

### `tuist_cache_downloads_total` (счетчик) {#tuist_cache_downloads_total-counter}

Количество загрузок в двоичный кэш.

### `tuist_cache_downloaded_bytes` (sum) {#tuist_cache_downloaded_bytes-sum}

Количество байт, загруженных из двоичного кэша.

---

## Предварительные просмотры метрик {#previews-metrics}

Набор метрик, связанных с функцией предварительного просмотра.

### `tuist_previews_uploads_total` (sum) {#tuist_previews_uploads_total-counter}

Общее количество загруженных превью.

### `tuist_previews_downloads_total` (sum) {#tuist_previews_downloads_total-counter}

Общее количество загруженных превью.

---

## Показатели хранения {#storage-metrics}

Набор метрик, связанных с хранением артефактов в удаленном хранилище (например,
s3).

::: tip
<!-- -->
Эти показатели полезны для понимания производительности операций хранения и
выявления потенциальных узких мест.
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (гистограмма) {#tuist_storage_get_object_size_size_bytes-histogram}

Размер (в байтах) объекта, полученного из удаленного хранилища.

#### Теги {#tuist-storage-get-object-size-size-bytes-tags}

| Тег            | Описание                                   |
| -------------- | ------------------------------------------ |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище. |


### `tuist_storage_get_object_size_duration_miliseconds` (гистограмма) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

Продолжительность (в миллисекундах) получения размера объекта из удаленного
хранилища.

#### Теги {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Тег            | Описание                                   |
| -------------- | ------------------------------------------ |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище. |


### `tuist_storage_get_object_size_count` (counter) {#tuist_storage_get_object_size_count-counter}

Количество раз, когда размер объекта был получен из удаленного хранилища.

#### Теги {#tuist-storage-get-object-size-count-tags}

| Тег            | Описание                                   |
| -------------- | ------------------------------------------ |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (гистограмма) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

Продолжительность (в миллисекундах) удаления всех объектов из удаленного
хранилища.

#### Теги {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Тег             | Описание                                   |
| --------------- | ------------------------------------------ |
| `метка проекта` | Метка проекта, объекты которого удаляются. |


### `tuist_storage_delete_all_objects_count` (счетчик) {#tuist_storage_delete_all_objects_count-counter}

Количество удалений всех объектов проекта из удаленного хранилища.

#### Теги {#tuist-storage-delete-all-objects-count-tags}

| Тег             | Описание                                   |
| --------------- | ------------------------------------------ |
| `метка проекта` | Метка проекта, объекты которого удаляются. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (гистограмма) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

Продолжительность (в миллисекундах) начала загрузки в удаленное хранилище.

#### Теги {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Тег            | Описание                                   |
| -------------- | ------------------------------------------ |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище. |

### `tuist_storage_multipart_start_upload_duration_count` (счетчик) {#tuist_storage_multipart_start_upload_duration_count-counter}

Количество запущенных загрузок в удаленное хранилище.

#### Теги {#tuist-storage-multipart-start-upload-duration-count-tags}

| Тег            | Описание                                   |
| -------------- | ------------------------------------------ |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (гистограмма) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

Продолжительность (в миллисекундах) получения объекта в виде строки из
удаленного хранилища.

#### Теги {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Тег            | Описание                                   |
| -------------- | ------------------------------------------ |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище. |

### `tuist_storage_get_object_as_string_count` (count) {#tuist_storage_get_object_as_string_count-count}

Количество раз, когда объект был получен в виде строки из удаленного хранилища.

#### Теги {#tuist-storage-get-object-as-string-count-tags}

| Тег            | Описание                                   |
| -------------- | ------------------------------------------ |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище. |


### `tuist_storage_check_object_existence_duration_milliseconds` (гистограмма) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

Длительность (в миллисекундах) проверки существования объекта в удаленном
хранилище.

#### Теги {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Тег            | Описание                                   |
| -------------- | ------------------------------------------ |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище. |

### `tuist_storage_check_object_existence_count` (count) {#tuist_storage_check_object_existence_count-count}

Количество раз, когда существование объекта проверялось в удаленном хранилище.

#### Теги {#tuist-storage-check-object-existence-count-tags}

| Тег            | Описание                                   |
| -------------- | ------------------------------------------ |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (гистограмма) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

Длительность (в миллисекундах) генерации URL-адреса с предварительным
назначением загрузки для объекта в удаленном хранилище.

#### Теги {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Тег            | Описание                                   |
| -------------- | ------------------------------------------ |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище. |


### `tuist_storage_generate_download_presigned_url_count` (count) {#tuist_storage_generate_download_presigned_url_count-count}

Количество раз, когда для объекта в удаленном хранилище был сгенерирован URL с
предварительным назначением загрузки.

#### Теги {#tuist-storage-generate-download-presigned-url-count-tags}

| Тег            | Описание                                   |
| -------------- | ------------------------------------------ |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (гистограмма) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

Длительность (в миллисекундах) генерации URL-адреса выгрузки части для объекта в
удаленном хранилище.

#### Теги {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Тег            | Описание                                           |
| -------------- | -------------------------------------------------- |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище.         |
| `номер_детали` | Номер детали загружаемого объекта.                 |
| `upload_id`    | Идентификатор загрузки многокомпонентной загрузки. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

Количество раз, когда для объекта в удаленном хранилище был сгенерирован URL с
предварительным назначением части выгрузки.

#### Теги {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Тег            | Описание                                           |
| -------------- | -------------------------------------------------- |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище.         |
| `номер_детали` | Номер детали загружаемого объекта.                 |
| `upload_id`    | Идентификатор загрузки многокомпонентной загрузки. |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (гистограмма) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

Продолжительность (в миллисекундах) завершения загрузки в удаленное хранилище.

#### Теги {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Тег            | Описание                                           |
| -------------- | -------------------------------------------------- |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище.         |
| `upload_id`    | Идентификатор загрузки многокомпонентной загрузки. |


### `tuist_storage_multipart_complete_upload_count` (count) {#tuist_storage_multipart_complete_upload_count-count}

Общее количество загрузок в удаленное хранилище.

#### Теги {#tuist-storage-multipart-complete-upload-count-tags}

| Тег            | Описание                                           |
| -------------- | -------------------------------------------------- |
| `ключ объекта` | Ключ поиска объекта в удаленном хранилище.         |
| `upload_id`    | Идентификатор загрузки многокомпонентной загрузки. |

---

## Метрики аутентификации {#authentication-metrics}

Набор метрик, связанных с аутентификацией.

### `tuist_authentication_token_refresh_error_total` (счетчик) {#tuist_authentication_token_refresh_error_total-counter}

Общее количество ошибок обновления маркера.

#### Теги {#tuist-authentication-token-refresh-error-total-tags}

| Тег           | Описание                                                                             |
| ------------- | ------------------------------------------------------------------------------------ |
| `cli_version` | Версия Tuist CLI, в которой возникла ошибка.                                         |
| `причина`     | Причина ошибки обновления токена, например `invalid_token_type` или `invalid_token`. |

---

## Метрики проектов {#projects-metrics}

Набор метрик, связанных с проектами.

### `tuist_projects_total` (last_value) {#tuist_projects_total-last_value}

Общее количество проектов.

---

## Показатели счетов {#accounts-metrics}

Набор метрик, связанных с учетными записями (пользователями и организациями).

### `tuist_accounts_organizations_total` (last_value) {#tuist_accounts_organizations_total-last_value}

Общее количество организаций.

### `tuist_accounts_users_total` (last_value) {#tuist_accounts_users_total-last_value}

Общее количество пользователей.


## Метрики базы данных {#database-metrics}

Набор метрик, связанных с подключением к базе данных.

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

Количество запросов к базе данных, которые находятся в очереди и ожидают
назначения на соединение с базой данных.

### `tuist_repo_pool_ready_conn_count` (last_value) {#tuist_repo_pool_ready_conn_count-last_value}

Количество соединений с базой данных, готовых к назначению на запрос базы
данных.


### `tuist_repo_pool_db_connection_connected` (счетчик) {#tuist_repo_pool_db_connection_connected-counter}

Количество установленных соединений с базой данных.

### `tuist_repo_pool_db_connection_disconnected` (счетчик) {#tuist_repo_pool_db_connection_disconnected-counter}

Количество соединений, которые были отключены от базы данных.

## HTTP-метрики {#http-metrics}

Набор метрик, связанных с взаимодействием Tuist с другими сервисами через HTTP.

### `tuist_http_request_count` (счетчик) {#tuist_http_request_count-last_value}

Количество исходящих HTTP-запросов.

### `tuist_http_request_duration_nanosecond_sum` (sum) {#tuist_http_request_duration_nanosecond_sum-last_value}

Сумма длительностей исходящих запросов (включая время ожидания назначения
соединения).

### `tuist_http_request_duration_nanosecond_bucket` (распределение) {#tuist_http_request_duration_nanosecond_bucket-distribution}
Распределение длительности исходящих запросов (включая время, которое они
потратили на ожидание назначения соединения).

### `tuist_http_queue_count` (счетчик) {#tuist_http_queue_count-counter}

Количество запросов, которые были получены из пула.

### `tuist_http_queue_duration_nanoseconds_sum` (sum) {#tuist_http_queue_duration_nanoseconds_sum-sum}

Время, необходимое для получения соединения из пула.

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

Время, в течение которого соединение простаивало в ожидании получения.

### `tuist_http_queue_duration_nanoseconds_bucket` (распределение) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

Время, необходимое для получения соединения из пула.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (распределение) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

Время, в течение которого соединение простаивало в ожидании получения.

### `tuist_http_connection_count` (счетчик) {#tuist_http_connection_count-counter}

Количество установленных соединений.

### `tuist_http_connection_duration_nanoseconds_sum` (sum) {#tuist_http_connection_duration_nanoseconds_sum-sum}

Время, необходимое для установления соединения с хостом.

### `tuist_http_connection_duration_nanoseconds_bucket` (распределение) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

Распределение времени, необходимого для установления соединения с хостом.

### `tuist_http_send_count` (счетчик) {#tuist_http_send_count-counter}

Количество запросов, которые были отправлены после назначения соединения из
пула.

### `tuist_http_send_duration_nanoseconds_sum` (sum) {#tuist_http_send_duration_nanoseconds_sum-sum}

Время, которое требуется для выполнения запросов после назначения соединения из
пула.

### `tuist_http_send_duration_nanoseconds_bucket` (распределение) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

Распределение времени, которое требуется для выполнения запросов после
назначения соединения из пула.

### `tuist_http_receive_count` (счетчик) {#tuist_http_receive_count-counter}

Количество ответов, полученных на отправленные запросы.

### `tuist_http_receive_duration_nanoseconds_sum` (sum) {#tuist_http_receive_duration_nanoseconds_sum-sum}

Время, затраченное на получение ответов.

### `tuist_http_receive_duration_nanoseconds_bucket` (распределение) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

Распределение времени, затраченного на получение ответов.

### `tuist_http_queue_available_connections` (last_value) {#tuist_http_queue_available_connections-last_value}

Количество соединений, доступных в очереди.

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

Количество используемых соединений очереди.
