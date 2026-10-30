---
{
  "title": "Telemetría",
  "titleTemplate": ":title | Autoalojamiento | Servidor | Guías | Tuist",
  "description": "Monitoriza tu servidor de Tuist con métricas de Prometheus, trazas de OpenTelemetry y reenvío de registros."
}
---
# Telemetría {#telemetry}

Tuist ofrece tres señales de observabilidad complementarias: **métricas** (Prometheus), **trazas** (OpenTelemetry) y **registros** (compatibles con Loki). Las tres son opcionales y pueden activarse de forma independiente.

## Trazado distribuido (OpenTelemetry) {#opentelemetry}

Tuist admite [OpenTelemetry](https://opentelemetry.io/) para el trazado distribuido. Cuando está activado, el servidor emite trazas para las solicitudes HTTP (Phoenix y Bandit), las consultas a la base de datos (Ecto), las llamadas HTTP salientes (Finch) y el procesamiento de mensajes de Broadway. Estas trazas te permiten comprender la latencia de las solicitudes, identificar consultas lentas y seguir las solicitudes entre servicios.

### Configuración {#opentelemetry-configuration}

Define la siguiente variable de entorno para habilitar la exportación de trazas:

| Variable de entorno | Descripción | Obligatorio | Predeterminado | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | El extremo gRPC de un recopilador de OpenTelemetry (por ejemplo, Grafana Alloy, Jaeger o cualquier recopilador compatible con OTLP) | No | | `http://localhost:4317` |

Cuando esta variable no está definida, el trazado está desactivado y no añade sobrecarga.

### Bibliotecas instrumentadas {#opentelemetry-instrumented-libraries}

Las siguientes bibliotecas se instrumentan automáticamente cuando el trazado está activado:

- **Bandit**: spans de conexión del servidor HTTP
- **Phoenix**: spans del ciclo de vida de las solicitudes (acciones del controlador, LiveView)
- **Ecto**: spans de consultas a la base de datos con metadatos de la consulta
- **Finch**: spans de solicitudes HTTP salientes del cliente
- **Broadway**: spans de la canalización de procesamiento de mensajes

### Ejemplo de configuración con Grafana Alloy {#opentelemetry-alloy-example}

Si usas [Grafana Alloy](https://grafana.com/docs/alloy/latest/) como tu recopilador, configúralo para recibir trazas OTLP y reenviarlas a tu backend de trazado (por ejemplo, Grafana Cloud Tempo):

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

Luego define `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` para que apunte a la instancia de Alloy, por ejemplo `http://alloy:4317`.

## Reenvío de registros (Loki) {#log-forwarding}

Tuist puede reenviar los registros de la aplicación a un extremo compatible con [Loki](https://grafana.com/oss/loki/). Esto te permite centralizar los registros junto con tus métricas y trazas para tener una visión completa de la observabilidad. Los registros se envían mediante la API HTTP push de Loki (`/loki/api/v1/push`) e incluyen etiquetas para `app`, `env` y `level`.

### Configuración {#log-forwarding-configuration}

| Variable de entorno | Descripción | Obligatorio | Predeterminado | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_LOKI_URL` | La URL base de un extremo de API push compatible con Loki | No | | `http://localhost:3100` |

Cuando esta variable no está definida, el reenvío de registros está desactivado.

### Ejemplo de configuración con Grafana Alloy {#log-forwarding-alloy-example}

Grafana Alloy puede actuar como un relé local de registros usando su componente [`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/):

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

Luego define `TUIST_LOKI_URL=http://alloy:3100`.

También puedes apuntar `TUIST_LOKI_URL` directamente a una instancia de Loki si expone la API push.

## Métricas de Prometheus {#prometheus-metrics}

Puedes ingerir las métricas recopiladas por el servidor de Tuist usando [Prometheus](https://prometheus.io/) y una herramienta de visualización como [Grafana](https://grafana.com/) para crear un panel personalizado adaptado a tus necesidades. Las métricas de Prometheus se sirven a través del extremo `/metrics` en el puerto 9091. El [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) de Prometheus debe configurarse en menos de 10_000 segundos (recomendamos 30 segundos para equilibrar la observabilidad con los costes de ingesta de métricas).

## Monitorización de usuarios reales {#real-user-monitoring}

Tuist puede informar sobre el rendimiento del navegador desde el sitio de marketing, la documentación y el panel usando el SDK web de [Grafana Faro](https://grafana.com/oss/faro/), que viene integrado en el JavaScript servido. Captura Core Web Vitals (incluido Largest Contentful Paint), errores no capturados y vistas de página, y los envía a un [receptor de Faro](https://grafana.com/docs/alloy/latest/reference/components/faro/faro.receiver/) que ejecutes —por ejemplo, el componente `faro.receiver` en Grafana Alloy, que reenvía a Loki y Tempo.

### Configuración {#real-user-monitoring-configuration}

| Variable de entorno | Descripción | Obligatorio | Predeterminado | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_FARO_COLLECTOR_URL` | URL a la que el navegador envía las cargas de Faro | No | | `/-/faro` |

> [!NOTE]
> La monitorización de usuarios reales solo está activada cuando `TUIST_FARO_COLLECTOR_URL` está definida. Sin ella, no se recopila telemetría del navegador ni se carga ningún script de terceros.

Una ruta del mismo origen como `/-/faro` evita solicitudes entre orígenes y mantiene inalterada la Política de Seguridad de Contenido del navegador. Apúntala a tu receptor de Faro a través de tu ingress.

### Qué se recopila {#real-user-monitoring-collected}

- **Métricas web**: LCP, CLS, INP, FCP y TTFB, capturadas automáticamente por el navegador
- **Vistas de página**: registradas al cargar y durante la navegación de Phoenix LiveView
- **Vistas**: cada carga incluye la sección que la generó: `marketing`, `docs`, `dashboard` o `api-docs`
- **Errores**: excepciones no capturadas y rechazos de promesas no manejados

### Consideraciones de privacidad {#real-user-monitoring-privacy}

- No se adjunta identidad de usuario: las cargas no incluyen ID de usuario, correo electrónico ni cuenta
- Las sesiones no se persisten entre visitas, por lo que no se escribe nada en el almacenamiento del navegador
- La captura de consola está desactivada, por lo que la salida de registros de la aplicación nunca se envía desde el navegador

## Métricas de Elixir {#elixir-metrics}

Por defecto incluimos métricas del runtime de Elixir, BEAM, Elixir y algunas de las bibliotecas que usamos. Estas son algunas de las métricas que puedes esperar ver:

- [Aplicación](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

Recomendamos consultar esas páginas para saber qué métricas están disponibles y cómo usarlas.

## Métricas de ejecuciones {#runs-metrics}

Un conjunto de métricas relacionadas con las ejecuciones de Tuist.

### `tuist_runs_total` (contador) {#tuist_runs_total-counter}

El número total de ejecuciones de Tuist.

#### Etiquetas {#tuist-runs-total-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `name` | El nombre del comando `tuist` que se ejecutó, como `build`, `test`, etc. |
| `is_ci` | Un valor booleano que indica si el ejecutor era un entorno de CI o la máquina de un desarrollador. |
| `status` | `0` en caso de `success`, `1` en caso de `failure`. |

### `tuist_runs_duration_milliseconds` (histograma) {#tuist_runs_duration_milliseconds-histogram}

La duración total de cada ejecución de tuist en milisegundos.

#### Etiquetas {#tuist-runs-duration-miliseconds-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `name` | El nombre del comando `tuist` que se ejecutó, como `build`, `test`, etc. |
| `is_ci` | Un valor booleano que indica si el ejecutor era un entorno de CI o la máquina de un desarrollador. |
| `status` | `0` en caso de `success`, `1` en caso de `failure`. |

## Métricas de caché {#cache-metrics}

Un conjunto de métricas relacionadas con la caché de Tuist.

### `tuist_cache_events_total` (contador) {#tuist_cache_events_total-counter}

El número total de eventos de la caché binaria.

#### Etiquetas {#tuist-cache-events-total-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `event_type` | Puede ser `local_hit`, `remote_hit` o `miss`. |

### `tuist_cache_uploads_total` (contador) {#tuist_cache_uploads_total-counter}

El número de subidas a la caché binaria.

### `tuist_cache_uploaded_bytes` (suma) {#tuist_cache_uploaded_bytes-sum}

El número de bytes subidos a la caché binaria.

### `tuist_cache_downloads_total` (contador) {#tuist_cache_downloads_total-counter}

El número de descargas de la caché binaria.

### `tuist_cache_downloaded_bytes` (suma) {#tuist_cache_downloaded_bytes-sum}

El número de bytes descargados de la caché binaria.

---

## Métricas de Previews {#previews-metrics}

Un conjunto de métricas relacionadas con la funcionalidad de previsualizaciones.

### `tuist_previews_uploads_total` (suma) {#tuist_previews_uploads_total-counter}

El número total de previsualizaciones subidas.

### `tuist_previews_downloads_total` (suma) {#tuist_previews_downloads_total-counter}

El número total de previsualizaciones descargadas.

---

## Métricas de almacenamiento {#storage-metrics}

Un conjunto de métricas relacionadas con el almacenamiento de artefactos en un almacenamiento remoto (por ejemplo, s3).

> [!TIP]
> Estas métricas son útiles para comprender el rendimiento de las operaciones de almacenamiento e identificar posibles cuellos de botella.


### `tuist_storage_get_object_size_size_bytes` (histograma) {#tuist_storage_get_object_size_size_bytes-histogram}

El tamaño (en bytes) de un objeto obtenido del almacenamiento remoto.

#### Etiquetas {#tuist-storage-get-object-size-size-bytes-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_get_object_size_duration_miliseconds` (histograma) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

La duración (en milisegundos) de obtener el tamaño de un objeto desde el almacenamiento remoto.

#### Etiquetas {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_get_object_size_count` (contador) {#tuist_storage_get_object_size_count-counter}

El número de veces que se obtuvo el tamaño de un objeto desde el almacenamiento remoto.

#### Etiquetas {#tuist-storage-get-object-size-count-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (histograma) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

La duración (en milisegundos) de eliminar todos los objetos del almacenamiento remoto.

#### Etiquetas {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `project_slug` | El slug del proyecto cuyos objetos se están eliminando. |


### `tuist_storage_delete_all_objects_count` (contador) {#tuist_storage_delete_all_objects_count-counter}

El número de veces que se eliminaron todos los objetos del proyecto del almacenamiento remoto.

#### Etiquetas {#tuist-storage-delete-all-objects-count-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `project_slug` | El slug del proyecto cuyos objetos se están eliminando. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (histograma) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

La duración (en milisegundos) de iniciar una subida al almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_multipart_start_upload_duration_count` (contador) {#tuist_storage_multipart_start_upload_duration_count-counter}

El número de veces que se inició una subida al almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-start-upload-duration-count-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histograma) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

La duración (en milisegundos) de obtener un objeto como cadena desde el almacenamiento remoto.

#### Etiquetas {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_get_object_as_string_count` (contador) {#tuist_storage_get_object_as_string_count-count}

El número de veces que se obtuvo un objeto como cadena desde el almacenamiento remoto.

#### Etiquetas {#tuist-storage-get-object-as-string-count-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_check_object_existence_duration_milliseconds` (contador) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

La duración (en milisegundos) de comprobar la existencia de un objeto en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_check_object_existence_count` (contador) {#tuist_storage_check_object_existence_count-count}

El número de veces que se comprobó la existencia de un objeto en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-check-object-existence-count-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histograma) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

La duración (en milisegundos) de generar una URL prefirmada de descarga para un objeto en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_generate_download_presigned_url_count` (contador) {#tuist_storage_generate_download_presigned_url_count-count}

El número de veces que se generó una URL prefirmada de descarga para un objeto en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-generate-download-presigned-url-count-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histograma) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

La duración (en milisegundos) de generar una URL prefirmada de subida de parte para un objeto en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |
| `part_number` | El número de parte del objeto que se está subiendo. |
| `upload_id` | El ID de subida de la subida multipart. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (contador) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

El número de veces que se generó una URL prefirmada de subida de parte para un objeto en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |
| `part_number` | El número de parte del objeto que se está subiendo. |
| `upload_id` | El ID de subida de la subida multipart. |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histograma) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

La duración (en milisegundos) de completar una subida al almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |
| `upload_id` | El ID de subida de la subida multipart. |


### `tuist_storage_multipart_complete_upload_count` (contador) {#tuist_storage_multipart_complete_upload_count-count}

El número total de veces que se completó una subida al almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-complete-upload-count-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |
| `upload_id` | El ID de subida de la subida multipart. |

---

## Métricas de autenticación {#authentication-metrics}

Un conjunto de métricas relacionadas con la autenticación.

### `tuist_authentication_token_refresh_error_total` (contador) {#tuist_authentication_token_refresh_error_total-counter}

El número total de errores de actualización de token.

#### Etiquetas {#tuist-authentication-token-refresh-error-total-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `cli_version` | La versión de Tuist CLI que encontró el error. |
| `reason` | El motivo del error de actualización de token, como `invalid_token_type` o `invalid_token`. |

---

## Métricas de proyectos {#projects-metrics}

Un conjunto de métricas relacionadas con los proyectos.

### `tuist_projects_total` (último_valor) {#tuist_projects_total-last_value}

El número total de proyectos.

---

## Métricas de cuentas {#accounts-metrics}

Un conjunto de métricas relacionadas con las cuentas (usuarios y organizaciones).

### `tuist_accounts_organizations_total` (último_valor) {#tuist_accounts_organizations_total-last_value}

El número total de organizaciones.

### `tuist_accounts_users_total` (último_valor) {#tuist_accounts_users_total-last_value}

El número total de usuarios.


## Métricas de base de datos {#database-metrics}

Un conjunto de métricas relacionadas con la conexión a la base de datos.

Las métricas del pool de repositorios se muestrean internamente cada 100 ms y luego se exponen a Prometheus en `/metrics`. Las métricas `last_value` que aparecen a continuación muestran el estado más reciente del pool en el momento del sondeo. Las métricas de presión que aparecen más abajo son sumas derivadas de esas muestras de 100 ms, lo que facilita detectar ventanas cortas de saturación incluso cuando se recuperan antes del siguiente sondeo.

### `tuist_repo_pool_checkout_queue_length` (último_valor) {#tuist_repo_pool_checkout_queue_length-last_value}

El número de consultas a la base de datos que están en cola esperando ser asignadas a una conexión de base de datos.

#### Etiquetas {#tuist_repo_pool_checkout_queue_length-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `repo` | El repositorio que emitió la métrica, como `postgres`, `clickhouse_read` o `clickhouse_write`. |
| `database` | El tipo de base de datos subyacente, como `postgres` o `clickhouse`. |

### `tuist_repo_pool_ready_conn_count` (último_valor) {#tuist_repo_pool_ready_conn_count-last_value}

El número de conexiones a la base de datos que están listas para ser asignadas a una consulta de base de datos.

#### Etiquetas {#tuist_repo_pool_ready_conn_count-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `repo` | El repositorio que emitió la métrica, como `postgres`, `clickhouse_read` o `clickhouse_write`. |
| `database` | El tipo de base de datos subyacente, como `postgres` o `clickhouse`. |

### `tuist_repo_pool_size` (último_valor) {#tuist_repo_pool_size-last_value}

El número configurado de conexiones en el pool.

#### Etiquetas {#tuist_repo_pool_size-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `repo` | El repositorio que emitió la métrica, como `postgres`, `clickhouse_read` o `clickhouse_write`. |
| `database` | El tipo de base de datos subyacente, como `postgres` o `clickhouse`. |

### `tuist_repo_pool_checkout_queue_total_samples_sum` (suma) {#tuist_repo_pool_checkout_queue_total_samples_sum-sum}

El número total de sondeos del pool de repositorios realizados (se incrementa en 1 en cada sondeo). Úsalo como denominador al calcular porcentajes de ocupación o inanición: `rate(busy_samples) / rate(total_samples)` o `rate(starved_samples) / rate(total_samples)`.

#### Etiquetas {#tuist_repo_pool_checkout_queue_total_samples_sum-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `repo` | El repositorio que emitió la métrica, como `postgres`, `clickhouse_read` o `clickhouse_write`. |
| `database` | El tipo de base de datos subyacente, como `postgres` o `clickhouse`. |

### `tuist_repo_pool_checkout_queue_observed_sum` (suma) {#tuist_repo_pool_checkout_queue_observed_sum-sum}

La suma de las solicitudes de checkout en cola observadas durante los sondeos del pool de repositorios. Esto es útil para detectar ráfagas breves de contención del pool que pueden no ser visibles solo con la última muestra de longitud de cola.

#### Etiquetas {#tuist_repo_pool_checkout_queue_observed_sum-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `repo` | El repositorio que emitió la métrica, como `postgres`, `clickhouse_read` o `clickhouse_write`. |
| `database` | El tipo de base de datos subyacente, como `postgres` o `clickhouse`. |

### `tuist_repo_pool_checkout_queue_busy_samples_sum` (suma) {#tuist_repo_pool_checkout_queue_busy_samples_sum-sum}

El número de sondeos del pool de repositorios en los que al menos una solicitud de checkout a la base de datos estaba esperando en la cola.

#### Etiquetas {#tuist_repo_pool_checkout_queue_busy_samples_total-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `repo` | El repositorio que emitió la métrica, como `postgres`, `clickhouse_read` o `clickhouse_write`. |
| `database` | El tipo de base de datos subyacente, como `postgres` o `clickhouse`. |

### `tuist_repo_pool_checkout_queue_starved_samples_sum` (suma) {#tuist_repo_pool_checkout_queue_starved_samples_sum-sum}

El número de sondeos del pool de repositorios en los que las solicitudes de checkout estaban en cola y no había conexiones listas disponibles. Un aumento sostenido aquí suele indicar que el pool está saturado.

#### Etiquetas {#tuist_repo_pool_checkout_queue_starved_samples_total-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `repo` | El repositorio que emitió la métrica, como `postgres`, `clickhouse_read` o `clickhouse_write`. |
| `database` | El tipo de base de datos subyacente, como `postgres` o `clickhouse`. |

### `tuist_repo_pool_db_connection_connected` (contador) {#tuist_repo_pool_db_connection_connected-counter}

El número de conexiones que se han establecido con la base de datos.

### `tuist_repo_pool_db_connection_disconnected` (contador) {#tuist_repo_pool_db_connection_disconnected-counter}

El número de conexiones que se han desconectado de la base de datos.

#### Etiquetas {#tuist_repo_pool_db_connection_connected_and_disconnected-tags}

| Etiqueta | Descripción |
|--- | ---- |
| `tag` | La etiqueta del listener de DBConnection que identifica el repositorio emisor. |

## Métricas HTTP {#http-metrics}

Un conjunto de métricas relacionadas con las interacciones de Tuist con otros servicios a través de HTTP.

### `tuist_http_request_count` (contador) {#tuist_http_request_count-last_value}

El número de solicitudes HTTP salientes.

### `tuist_http_request_duration_nanosecond_sum` (suma) {#tuist_http_request_duration_nanosecond_sum-last_value}

La suma de la duración de las solicitudes salientes (incluido el tiempo que pasaron esperando ser asignadas a una conexión).

### `tuist_http_request_duration_nanosecond_bucket` (distribución) {#tuist_http_request_duration_nanosecond_bucket-distribution}
La distribución de la duración de las solicitudes salientes (incluido el tiempo que pasaron esperando ser asignadas a una conexión).

### `tuist_http_queue_count` (contador) {#tuist_http_queue_count-counter}

El número de solicitudes que se han recuperado del pool.

### `tuist_http_queue_duration_nanoseconds_sum` (suma) {#tuist_http_queue_duration_nanoseconds_sum-sum}

El tiempo que tarda en recuperarse una conexión del pool.

### `tuist_http_queue_idle_time_nanoseconds_sum` (suma) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

El tiempo que una conexión ha estado inactiva esperando ser recuperada.

### `tuist_http_queue_duration_nanoseconds_bucket` (distribución) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

El tiempo que tarda en recuperarse una conexión del pool.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (distribución) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

El tiempo que una conexión ha estado inactiva esperando ser recuperada.

### `tuist_http_connection_count` (contador) {#tuist_http_connection_count-counter}

El número de conexiones que se han establecido.

### `tuist_http_connection_duration_nanoseconds_sum` (suma) {#tuist_http_connection_duration_nanoseconds_sum-sum}

El tiempo que tarda en establecerse una conexión con un host.

### `tuist_http_connection_duration_nanoseconds_bucket` (distribución) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

La distribución del tiempo que tarda en establecerse una conexión con un host.

### `tuist_http_send_count` (contador) {#tuist_http_send_count-counter}

El número de solicitudes que se han enviado una vez asignadas a una conexión del pool.

### `tuist_http_send_duration_nanoseconds_sum` (suma) {#tuist_http_send_duration_nanoseconds_sum-sum}

El tiempo que tardan las solicitudes en completarse una vez asignadas a una conexión del pool.

### `tuist_http_send_duration_nanoseconds_bucket` (distribución) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

La distribución del tiempo que tardan las solicitudes en completarse una vez asignadas a una conexión del pool.

### `tuist_http_receive_count` (contador) {#tuist_http_receive_count-counter}

El número de respuestas recibidas de las solicitudes enviadas.

### `tuist_http_receive_duration_nanoseconds_sum` (suma) {#tuist_http_receive_duration_nanoseconds_sum-sum}

El tiempo dedicado a recibir respuestas.

### `tuist_http_receive_duration_nanoseconds_bucket` (distribución) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

La distribución del tiempo dedicado a recibir respuestas.

### `tuist_http_queue_available_connections` (último valor) {#tuist_http_queue_available_connections-last_value}

El número de conexiones disponibles en la cola.

### `tuist_http_queue_in_use_connections` (último valor) {#tuist_http_queue_in_use_connections-last_value}

El número de conexiones de la cola que están en uso.
