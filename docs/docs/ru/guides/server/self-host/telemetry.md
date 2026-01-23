---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# Телеметрия {#telemetry}

Вы можете импортировать метрики, собранные сервером Tuist, с помощью
[Prometheus](https://prometheus.io/) и инструмента визуализации, такого как
[Grafana](https://grafana.com/), чтобы создать настраиваемую панель
инструментов, адаптированную к вашим потребностям. Метрики Prometheus
обслуживаются через конечную точку `/metrics` на порту 9091.
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
Prometheus должен быть установлен на значение менее 10_000 секунд (мы
рекомендуем оставить значение по умолчанию 15 секунд).

## Аналитика PostHog {#posthog-analytics}

Tuist интегрирован с [PostHog](https://posthog.com/) для анализа поведения
пользователей и отслеживания событий. Это позволяет вам понять, как пользователи
взаимодействуют с вашим сервером Tuist, отслеживать использование функций и
получать информацию о поведении пользователей на маркетинговом сайте, в панели
управления и в документации по API.

### Настройка {#posthog-configuration}

Интеграция с PostHog является опциональной и может быть включена путем настройки
соответствующих переменных среды. После настройки Tuist будет автоматически
отслеживать события пользователей, просмотры страниц и пути пользователей.

| Переменная среды        | Описание                             | Обязательно | По умолчанию | Пример                                            |
| ----------------------- | ------------------------------------ | ----------- | ------------ | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | Ваш ключ API проекта PostHog         | Нет         |              | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | URL-адрес конечной точки API PostHog | Нет         |              | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
Аналитика включается только в том случае, если настроены оба параметра:
`TUIST_POSTHOG_API_KEY` и `TUIST_POSTHOG_URL`. Если один из параметров
отсутствует, события аналитики не будут отправляться.
<!-- -->
:::

### Особенности {#posthog-features}

Когда PostHog включен, Tuist автоматически отслеживает:

- **Идентификация пользователя**: Пользователи идентифицируются по своему
  уникальному ID и адресу электронной почты.
- **Псевдонимы пользователей**: Пользователи получают псевдонимы по имени своей
  учетной записи для облегчения идентификации.
- **Групповая аналитика**: Пользователи группируются по выбранному проекту и
  организации для сегментированной аналитики.
- **Разделы страницы**: События включают в себя суперсвойства, указывающие,
  какой раздел приложения их сгенерировал:
  - `маркетинг` - События с маркетинговых страниц и общедоступного контента
  - `панель управления` - События с панели управления основного приложения и
    аутентифицированных областей
  - `api-docs` - События со страниц документации API
- **Просмотры страниц**: автоматическое отслеживание навигации по страницам с
  помощью Phoenix LiveView
- **Пользовательские события**: события, специфичные для приложения, связанные с
  использованием функций и взаимодействием с пользователем.

### Соображения конфиденциальности {#posthog-privacy}

- Для авторизованных пользователей PostHog использует уникальный ID пользователя
  в качестве отличительного идентификатора и включает их адрес электронной
  почты.
- Для анонимных пользователей PostHog использует только память для хранения
  данных, чтобы избежать их локального хранения.
- Все аналитические инструменты уважают конфиденциальность пользователей и
  следуют лучшим практикам защиты данных.
- Данные PostHog обрабатываются в соответствии с политикой конфиденциальности
  PostHog и вашими настройками.

## Метрики Elixir {#elixir-metrics}

По умолчанию мы включаем метрики среды выполнения Elixir, BEAM, Elixir и
некоторых библиотек, которые мы используем. Ниже приведены некоторые из метрик,
которые вы можете увидеть:

- [Приложение](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

Мы рекомендуем ознакомиться с этими страницами, чтобы узнать, какие метрики
доступны и как их использовать.

## Запускает метрики {#runs-metrics}

Набор показателей, связанных с Tuist Runs.

### `tuist_runs_total` (счетчик) {#tuist_runs_total-counter}

Общее количество пробежек Tuist.

#### Теги {#tuist-runs-total-tags}

| Теги     | Описание                                                                         |
| -------- | -------------------------------------------------------------------------------- |
| `имя`    | Название запущенной команды `tuist`, например `build`, `test` и т. д.            |
| `is_ci`  | Булево значение, указывающее, был ли исполнителем CI или компьютер разработчика. |
| `статус` | `0` в случае успеха `` , `1` в случае неудачи `` .                               |

### `tuist_runs_duration_milliseconds` (гистограмма) {#tuist_runs_duration_milliseconds-histogram}

Общая продолжительность каждого цикла tuist в миллисекундах.

#### Теги {#tuist-runs-duration-miliseconds-tags}

| Теги     | Описание                                                                         |
| -------- | -------------------------------------------------------------------------------- |
| `имя`    | Название запущенной команды `tuist`, например `build`, `test` и т. д.            |
| `is_ci`  | Булево значение, указывающее, был ли исполнителем CI или компьютер разработчика. |
| `статус` | `0` в случае успеха `` , `1` в случае неудачи `` .                               |

## Метрики кэша {#cache-metrics}

Набор метрик, связанных с Tuist Cache.

### `tuist_cache_events_total` (счетчик) {#tuist_cache_events_total-counter}

Общее количество событий двоичного кэша.

#### Теги {#tuist-cache-events-total-tags}

| Теги         | Описание                                                                        |
| ------------ | ------------------------------------------------------------------------------- |
| `event_type` | Может быть одним из следующих вариантов: `local_hit`, `remote_hit`, или `miss`. |

### `tuist_cache_uploads_total` (счетчик) {#tuist_cache_uploads_total-counter}

Количество загрузок в бинарный кэш.

### `tuist_cache_uploaded_bytes` (сумма) {#tuist_cache_uploaded_bytes-sum}

Количество байтов, загруженных в двоичный кэш.

### `tuist_cache_downloads_total` (счетчик) {#tuist_cache_downloads_total-counter}

Количество загрузок в бинарный кэш.

### `tuist_cache_downloaded_bytes` (сумма) {#tuist_cache_downloaded_bytes-sum}

Количество байтов, загруженных из бинарного кэша.

---

## Показатели предварительного просмотра {#previews-metrics}

Набор метрик, связанных с функцией предварительного просмотра.

### `tuist_previews_uploads_total` (сумма) {#tuist_previews_uploads_total-counter}

Общее количество загруженных предварительных просмотров.

### `tuist_previews_downloads_total` (сумма) {#tuist_previews_downloads_total-counter}

Общее количество загруженных предварительных просмотров.

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

| Теги         | Описание                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Ключ поиска объекта в удаленном хранилище. |


### `tuist_storage_get_object_size_duration_miliseconds` (гистограмма) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

Продолжительность (в миллисекундах) извлечения размера объекта из удаленного
хранилища.

#### Теги {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Теги         | Описание                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Ключ поиска объекта в удаленном хранилище. |


### `tuist_storage_get_object_size_count` (счетчик) {#tuist_storage_get_object_size_count-counter}

Количество раз, когда размер объекта был получен из удаленного хранилища.

#### Теги {#tuist-storage-get-object-size-count-tags}

| Теги         | Описание                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Ключ поиска объекта в удаленном хранилище. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (гистограмма) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

Продолжительность (в миллисекундах) удаления всех объектов из удаленного
хранилища.

#### Теги {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Теги           | Описание                                  |
| -------------- | ----------------------------------------- |
| `project_slug` | Слаг проекта, объекты которого удаляются. |


### `tuist_storage_delete_all_objects_count` (счетчик) {#tuist_storage_delete_all_objects_count-counter}

Количество раз, когда все объекты проекта были удалены из удаленного хранилища.

#### Теги {#tuist-storage-delete-all-objects-count-tags}

| Теги           | Описание                                  |
| -------------- | ----------------------------------------- |
| `project_slug` | Слаг проекта, объекты которого удаляются. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (гистограмма) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

Продолжительность (в миллисекундах) начала загрузки в удаленное хранилище.

#### Теги {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Теги         | Описание                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Ключ поиска объекта в удаленном хранилище. |

### `tuist_storage_multipart_start_upload_duration_count` (счетчик) {#tuist_storage_multipart_start_upload_duration_count-counter}

Количество раз, когда запускалась загрузка в удаленное хранилище.

#### Теги {#tuist-storage-multipart-start-upload-duration-count-tags}

| Теги         | Описание                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Ключ поиска объекта в удаленном хранилище. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (гистограмма) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

Продолжительность (в миллисекундах) извлечения объекта в виде строки из
удаленного хранилища.

#### Теги {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Теги         | Описание                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Ключ поиска объекта в удаленном хранилище. |

### `tuist_storage_get_object_as_string_count` (count) {#tuist_storage_get_object_as_string_count-count}

Количество раз, когда объект был извлечен в виде строки из удаленного хранилища.

#### Теги {#tuist-storage-get-object-as-string-count-tags}

| Теги         | Описание                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Ключ поиска объекта в удаленном хранилище. |


### `tuist_storage_check_object_existence_duration_milliseconds` (гистограмма) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

Продолжительность (в миллисекундах) проверки наличия объекта в удаленном
хранилище.

#### Теги {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Теги         | Описание                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Ключ поиска объекта в удаленном хранилище. |

### `tuist_storage_check_object_existence_count` (count) {#tuist_storage_check_object_existence_count-count}

Количество раз, когда проверялось наличие объекта в удаленном хранилище.

#### Теги {#tuist-storage-check-object-existence-count-tags}

| Теги         | Описание                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Ключ поиска объекта в удаленном хранилище. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (гистограмма) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

Продолжительность (в миллисекундах) генерации предварительно подписанного
URL-адреса для загрузки объекта в удаленном хранилище.

#### Теги {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Теги         | Описание                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Ключ поиска объекта в удаленном хранилище. |


### `tuist_storage_generate_download_presigned_url_count` (count) {#tuist_storage_generate_download_presigned_url_count-count}

Количество раз, когда был сгенерирован URL-адрес с предварительной подписью для
объекта в удаленном хранилище.

#### Теги {#tuist-storage-generate-download-presigned-url-count-tags}

| Теги         | Описание                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Ключ поиска объекта в удаленном хранилище. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (гистограмма) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

Продолжительность (в миллисекундах) генерации URL-адреса для частичной загрузки
предварительно подписанного объекта в удаленном хранилище.

#### Теги {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Теги          | Описание                                   |
| ------------- | ------------------------------------------ |
| `object_key`  | Ключ поиска объекта в удаленном хранилище. |
| `part_number` | Номер детали загружаемого объекта.         |
| `upload_id`   | Идентификатор многочастной загрузки.       |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

Количество раз, когда был сгенерирован URL с предварительной подписью для
объекта в удаленном хранилище.

#### Теги {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Теги          | Описание                                   |
| ------------- | ------------------------------------------ |
| `object_key`  | Ключ поиска объекта в удаленном хранилище. |
| `part_number` | Номер детали загружаемого объекта.         |
| `upload_id`   | Идентификатор многочастной загрузки.       |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (гистограмма) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

Продолжительность (в миллисекундах) завершения загрузки в удаленное хранилище.

#### Теги {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Теги         | Описание                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Ключ поиска объекта в удаленном хранилище. |
| `upload_id`  | Идентификатор многочастной загрузки.       |


### `tuist_storage_multipart_complete_upload_count` (count) {#tuist_storage_multipart_complete_upload_count-count}

Общее количество раз, когда загрузка была завершена в удаленное хранилище.

#### Теги {#tuist-storage-multipart-complete-upload-count-tags}

| Теги         | Описание                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Ключ поиска объекта в удаленном хранилище. |
| `upload_id`  | Идентификатор многочастной загрузки.       |

---

## Показатели аутентификации {#authentication-metrics}

Набор метрик, связанных с аутентификацией.

### `tuist_authentication_token_refresh_error_total` (счетчик) {#tuist_authentication_token_refresh_error_total-counter}

Общее количество ошибок обновления токенов.

#### Теги {#tuist-authentication-token-refresh-error-total-tags}

| Теги          | Описание                                                                             |
| ------------- | ------------------------------------------------------------------------------------ |
| `cli_version` | Версия Tuist CLI, в которой возникла ошибка.                                         |
| `причина`     | Причина ошибки обновления токена, например `invalid_token_type` или `invalid_token`. |

---

## Показатели проектов {#projects-metrics}

Набор показателей, связанных с проектами.

### `tuist_projects_total` (last_value) {#tuist_projects_total-last_value}

Общее количество проектов.

---

## Показатели учетных записей {#accounts-metrics}

Набор метрик, связанных с учетными записями (пользователями и организациями).

### `tuist_accounts_organizations_total` (last_value) {#tuist_accounts_organizations_total-last_value}

Общее количество организаций.

### `tuist_accounts_users_total` (last_value) {#tuist_accounts_users_total-last_value}

Общее количество пользователей.


## Показатели базы данных {#database-metrics}

Набор метрик, связанных с подключением к базе данных.

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

Количество запросов к базе данных, которые находятся в очереди в ожидании
назначения к подключению к базе данных.

### `tuist_repo_pool_ready_conn_count` (last_value) {#tuist_repo_pool_ready_conn_count-last_value}

Количество подключений к базе данных, готовых к назначению для запроса к базе
данных.


### `tuist_repo_pool_db_connection_connected` (счетчик) {#tuist_repo_pool_db_connection_connected-counter}

Количество подключений, установленных к базе данных.

### `tuist_repo_pool_db_connection_disconnected` (счетчик) {#tuist_repo_pool_db_connection_disconnected-counter}

Количество соединений, которые были отключены от базы данных.

## HTTP-метрики {#http-metrics}

Набор метрик, связанных с взаимодействием Tuist с другими сервисами через HTTP.

### `tuist_http_request_count` (счетчик) {#tuist_http_request_count-last_value}

Количество исходящих HTTP-запросов.

### `tuist_http_request_duration_nanosecond_sum` (сумма) {#tuist_http_request_duration_nanosecond_sum-last_value}

Сумма продолжительности исходящих запросов (включая время, которое они провели в
ожидании назначения соединения).

### `tuist_http_request_duration_nanosecond_bucket` (распределение) {#tuist_http_request_duration_nanosecond_bucket-distribution}
Распределение продолжительности исходящих запросов (включая время, которое они
провели в ожидании назначения соединения).

### `tuist_http_queue_count` (счетчик) {#tuist_http_queue_count-counter}

Количество запросов, которые были извлечены из пула.

### `tuist_http_queue_duration_nanoseconds_sum` (сумма) {#tuist_http_queue_duration_nanoseconds_sum-sum}

Время, необходимое для извлечения соединения из пула.

### `tuist_http_queue_idle_time_nanoseconds_sum` (сумма) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

Время, в течение которого соединение находилось в режиме ожидания, пока не было
выполнено извлечение.

### `tuist_http_queue_duration_nanoseconds_bucket` (distribution) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

Время, необходимое для извлечения соединения из пула.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (распределение) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

Время, в течение которого соединение находилось в режиме ожидания, пока не было
выполнено извлечение.

### `tuist_http_connection_count` (счетчик) {#tuist_http_connection_count-counter}

Количество установленных соединений.

### `tuist_http_connection_duration_nanoseconds_sum` (сумма) {#tuist_http_connection_duration_nanoseconds_sum-sum}

Время, необходимое для установления соединения с хостом.

### `tuist_http_connection_duration_nanoseconds_bucket` (распределение) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

Распределение времени, необходимого для установления соединения с хостом.

### `tuist_http_send_count` (счетчик) {#tuist_http_send_count-counter}

Количество запросов, отправленных после назначения соединения из пула.

### `tuist_http_send_duration_nanoseconds_sum` (сумма) {#tuist_http_send_duration_nanoseconds_sum-sum}

Время, необходимое для выполнения запросов после их назначения соединению из
пула.

### `tuist_http_send_duration_nanoseconds_bucket` (распределение) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

Распределение времени, необходимого для выполнения запросов после их назначения
соединению из пула.

### `tuist_http_receive_count` (счетчик) {#tuist_http_receive_count-counter}

Количество ответов, полученных на отправленные запросы.

### `tuist_http_receive_duration_nanoseconds_sum` (сумма) {#tuist_http_receive_duration_nanoseconds_sum-sum}

Время, затраченное на получение ответов.

### `tuist_http_receive_duration_nanoseconds_bucket` (распределение) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

Распределение времени, затраченного на получение ответов.

### `tuist_http_queue_available_connections` (last_value) {#tuist_http_queue_available_connections-last_value}

Количество доступных соединений в очереди.

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

Количество используемых соединений в очереди.
