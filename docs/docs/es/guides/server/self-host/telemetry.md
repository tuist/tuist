---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# Telemetría {#telemetry}

Puedes ingerir las métricas recopiladas por el servidor Tuist utilizando
[Prometheus](https://prometheus.io/) y una herramienta de visualización como
[Grafana](https://grafana.com/) para crear un panel personalizado adaptado a tus
necesidades. Las métricas de Prometheus se sirven a través del endpoint
`/metrics` en el puerto 9091. El
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
de Prometheus debe establecerse en menos de 10_000 segundos (recomendamos
mantener el valor predeterminado de 15 segundos).

## PostAnálisis de cerdos {#posthog-analytics}

Tuist se integra con [PostHog](https://posthog.com/) para el análisis del
comportamiento del usuario y el seguimiento de eventos. Esto te permite
comprender cómo interactúan los usuarios con tu servidor de Tuist, realizar un
seguimiento del uso de las funciones y obtener información sobre el
comportamiento de los usuarios en el sitio de marketing, el panel de control y
la documentación de la API.

### Configuración {#posthog-configuration}

La integración de PostHog es opcional y puede activarse configurando las
variables de entorno adecuadas. Una vez configurado, Tuist rastreará
automáticamente los eventos de usuario, las páginas vistas y los recorridos de
los usuarios.

| Variable de entorno     | Descripción                           | Requerido | Por defecto | Ejemplo                                           |
| ----------------------- | ------------------------------------- | --------- | ----------- | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | Su clave API del proyecto PostHog     | No        |             | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | URL del punto final de la API PostHog | No        |             | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
Los análisis sólo se activan cuando se configuran tanto `TUIST_POSTHOG_API_KEY`
como `TUIST_POSTHOG_URL`. Si falta alguna de las dos variables, no se enviarán
eventos de análisis.
<!-- -->
:::

### Características {#posthog-features}

Cuando PostHog está activado, Tuist rastrea automáticamente:

- **Identificación de usuarios**: Los usuarios se identifican por su ID único y
  su dirección de correo electrónico
- **Alias de usuario**: Los usuarios se identifican por su nombre de cuenta para
  facilitar su identificación.
- **Análisis por grupos**: Los usuarios se agrupan por su proyecto y
  organización seleccionados para realizar análisis segmentados.
- **Secciones de la página**: Los eventos incluyen superpropiedades que indican
  qué sección de la aplicación los ha generado:
  - `marketing` - Eventos de páginas de marketing y contenido público
  - `salpicadero` - Eventos del salpicadero principal de la aplicación y de las
    áreas autenticadas.
  - `api-docs` - Eventos de las páginas de documentación de la API
- **Páginas vistas**: Seguimiento automático de la navegación por la página
  mediante Phoenix LiveView
- **Eventos personalizados**: Eventos específicos de la aplicación para el uso
  de funciones y las interacciones del usuario.

### Protección de datos {#posthog-privacy}

- Para los usuarios autenticados, PostHog utiliza el ID único del usuario como
  identificador distintivo e incluye su dirección de correo electrónico
- Para los usuarios anónimos, PostHog utiliza la persistencia en memoria para
  evitar el almacenamiento local de datos.
- Todos los análisis respetan la privacidad del usuario y siguen las mejores
  prácticas de protección de datos
- Los datos de PostHog se procesan de acuerdo con la política de privacidad de
  PostHog y su configuración

## Métricas del elixir {#elixir-metrics}

Por defecto, incluimos métricas del tiempo de ejecución de Elixir, BEAM, Elixir
y algunas de las bibliotecas que utilizamos. Las siguientes son algunas de las
métricas que puedes esperar ver:

- [Aplicación](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [RAYO](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

Recomendamos consultar esas páginas para saber qué métricas están disponibles y
cómo utilizarlas.

## Métricas de ejecución {#runs-metrics}

Un conjunto de métricas relacionadas con Tuist Runs.

### `tuist_runs_total` (contador) {#tuist_runs_total-counter}

El número total de carreras de Tuist.

#### Etiquetas {#tuist-runs-total-tags}

| Etiqueta | Descripción                                                                     |
| -------- | ------------------------------------------------------------------------------- |
| `nombre` | El nombre del comando `tuist` que se ejecutó, como `build`, `test`, etc.        |
| `is_ci`  | Un booleano que indica si el ejecutor era un CI o una máquina de desarrollador. |
| `estado` | `0` en caso de `éxito`, `1` en caso de `fracaso`.                               |

### `tuist_runs_duration_milliseconds` (histograma) {#tuist_runs_duration_milliseconds-histogram}

La duración total de cada ejecución de tuist en milisegundos.

#### Etiquetas {#tuist-runs-duration-miliseconds-tags}

| Etiqueta | Descripción                                                                     |
| -------- | ------------------------------------------------------------------------------- |
| `nombre` | El nombre del comando `tuist` que se ejecutó, como `build`, `test`, etc.        |
| `is_ci`  | Un booleano que indica si el ejecutor era un CI o una máquina de desarrollador. |
| `estado` | `0` en caso de `éxito`, `1` en caso de `fracaso`.                               |

## Métricas de caché {#cache-metrics}

Conjunto de métricas relacionadas con la caché de Tuist.

### `tuist_cache_events_total` (contador) {#tuist_cache_events_total-counter}

El número total de eventos binarios de caché.

#### Etiquetas {#tuist-cache-events-total-tags}

| Etiqueta      | Descripción                                                                  |
| ------------- | ---------------------------------------------------------------------------- |
| `tipo_evento` | Puede ser cualquiera de los siguientes: `local_hit`, `remote_hit`, o `miss`. |

### `tuist_cache_uploads_total` (contador) {#tuist_cache_uploads_total-counter}

El número de subidas a la caché binaria.

### `tuist_cache_uploaded_bytes` (suma) {#tuist_cache_uploaded_bytes-sum}

El número de bytes cargados en la caché binaria.

### `tuist_cache_downloads_total` (contador) {#tuist_cache_downloads_total-counter}

El número de descargas a la caché binaria.

### `tuist_cache_downloaded_bytes` (suma) {#tuist_cache_downloaded_bytes-sum}

El número de bytes descargados de la caché binaria.

---

## Previsión de métricas {#previews-metrics}

Conjunto de métricas relacionadas con la función de previsualización.

### `tuist_previews_uploads_total` (suma) {#tuist_previews_uploads_total-counter}

El número total de vistas previas cargadas.

### `tuist_previews_downloads_total` (suma) {#tuist_previews_downloads_total-counter}

El número total de previsualizaciones descargadas.

---

## Métricas de almacenamiento {#storage-metrics}

Conjunto de métricas relacionadas con el almacenamiento de artefactos en un
almacenamiento remoto (por ejemplo, s3).

::: consejo
<!-- -->
Estas métricas son útiles para comprender el rendimiento de las operaciones de
almacenamiento e identificar posibles cuellos de botella.
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (histograma) {#tuist_storage_get_object_size_size_bytes-histogram}

El tamaño (en bytes) de un objeto obtenido del almacenamiento remoto.

#### Etiquetas {#tuist-storage-get-object-size-size-bytes-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_get_object_size_duration_miliseconds` (histograma) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

La duración (en milisegundos) de la obtención de un tamaño de objeto del
almacenamiento remoto.

#### Etiquetas {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_get_object_size_count` (contador) {#tuist_storage_get_object_size_count-counter}

El número de veces que se ha obtenido el tamaño de un objeto del almacenamiento
remoto.

#### Etiquetas {#tuist-storage-get-object-size-count-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (histograma) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

La duración (en milisegundos) de la eliminación de todos los objetos del
almacenamiento remoto.

#### Etiquetas {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Etiqueta          | Descripción                                             |
| ----------------- | ------------------------------------------------------- |
| `babosa_proyecto` | El slug del proyecto cuyos objetos se están eliminando. |


### `tuist_storage_delete_all_objects_count` (contador) {#tuist_storage_delete_all_objects_count-counter}

El número de veces que se borraron todos los objetos del proyecto del
almacenamiento remoto.

#### Etiquetas {#tuist-storage-delete-all-objects-count-tags}

| Etiqueta          | Descripción                                             |
| ----------------- | ------------------------------------------------------- |
| `babosa_proyecto` | El slug del proyecto cuyos objetos se están eliminando. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (histograma) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

La duración (en milisegundos) del inicio de una carga al almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_multipart_start_upload_duration_count` (contador) {#tuist_storage_multipart_start_upload_duration_count-counter}

El número de veces que se inició una subida al almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-start-upload-duration-count-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histograma) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

La duración (en milisegundos) de la obtención de un objeto como cadena desde el
almacenamiento remoto.

#### Etiquetas {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_get_object_as_string_count` (count) {#tuist_storage_get_object_as_string_count-count}

Número de veces que se ha obtenido un objeto como cadena desde el almacenamiento
remoto.

#### Etiquetas {#tuist-storage-get-object-as-string-count-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_check_object_existence_duration_milliseconds` (histograma) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

La duración (en milisegundos) de la comprobación de la existencia de un objeto
en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_check_object_existence_count` (count) {#tuist_storage_check_object_existence_count-count}

Número de veces que se ha comprobado la existencia de un objeto en el
almacenamiento remoto.

#### Etiquetas {#tuist-storage-check-object-existence-count-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histograma) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

La duración (en milisegundos) de la generación de una URL preasignada de
descarga para un objeto en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_generate_download_presigned_url_count` (count) {#tuist_storage_generate_download_presigned_url_count-count}

El número de veces que se generó una URL de descarga preasignada para un objeto
en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-generate-download-presigned-url-count-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histograma) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

La duración (en milisegundos) de la generación de una URL preasignada de carga
parcial para un objeto en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |
| `número_parte` | El número de pieza del objeto que se está cargando.          |
| `upload_id`    | El ID de subida de la subida multiparte.                     |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

El número de veces que se generó una URL presignada de carga parcial para un
objeto en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |
| `número_parte` | El número de pieza del objeto que se está cargando.          |
| `upload_id`    | El ID de subida de la subida multiparte.                     |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histograma) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

La duración (en milisegundos) de completar una carga al almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |
| `upload_id`    | El ID de subida de la subida multiparte.                     |


### `tuist_storage_multipart_complete_upload_count` (count) {#tuist_storage_multipart_complete_upload_count-count}

El número total de veces que se completó una subida al almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-complete-upload-count-tags}

| Etiqueta       | Descripción                                                  |
| -------------- | ------------------------------------------------------------ |
| `clave_objeto` | La clave de búsqueda del objeto en el almacenamiento remoto. |
| `upload_id`    | El ID de subida de la subida multiparte.                     |

---

## Métricas de autenticación {#authentication-metrics}

Conjunto de métricas relacionadas con la autenticación.

### `tuist_authentication_token_refresh_error_total` (contador) {#tuist_authentication_token_refresh_error_total-counter}

Número total de errores de actualización de fichas.

#### Etiquetas {#tuist-authentication-token-refresh-error-total-tags}

| Etiqueta      | Descripción                                                                                  |
| ------------- | -------------------------------------------------------------------------------------------- |
| `versión_cli` | La versión de la CLI de Tuist que ha encontrado el error.                                    |
| `motivo`      | El motivo del error de actualización del token, como `invalid_token_type` o `invalid_token`. |

---

## Métricas de los proyectos {#projects-metrics}

Un conjunto de métricas relacionadas con los proyectos.

### `tuist_projects_total` (last_value) {#tuist_projects_total-last_value}

El número total de proyectos.

---

## Métricas de las cuentas {#accounts-metrics}

Conjunto de métricas relacionadas con las cuentas (usuarios y organizaciones).

### `tuist_accounts_organizations_total` (last_value) {#tuist_accounts_organizations_total-last_value}

El número total de organizaciones.

### `tuist_accounts_users_total` (last_value) {#tuist_accounts_users_total-last_value}

El número total de usuarios.


## Métricas de la base de datos {#database-metrics}

Conjunto de métricas relacionadas con la conexión a la base de datos.

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

Número de consultas a la base de datos que están en cola a la espera de ser
asignadas a una conexión a la base de datos.

### `tuist_repo_pool_ready_conn_count` (último_valor) {#tuist_repo_pool_ready_conn_count-last_value}

El número de conexiones de base de datos que están listas para ser asignadas a
una consulta de base de datos.


### `tuist_repo_pool_db_connection_connected` (contador) {#tuist_repo_pool_db_connection_connected-counter}

El número de conexiones que se han establecido con la base de datos.

### `tuist_repo_pool_db_connection_disconnected` (contador) {#tuist_repo_pool_db_connection_disconnected-counter}

Número de conexiones que se han desconectado de la base de datos.

## Métricas HTTP {#http-metrics}

Conjunto de métricas relacionadas con las interacciones de Tuist con otros
servicios a través de HTTP.

### `tuist_http_request_count` (contador) {#tuist_http_request_count-last_value}

El número de peticiones HTTP salientes.

### `tuist_http_request_duration_nanosecond_sum` (suma) {#tuist_http_request_duration_nanosecond_sum-last_value}

La suma de la duración de las solicitudes salientes (incluido el tiempo que
pasaron esperando a ser asignadas a una conexión).

### `tuist_http_request_duration_nanosecond_bucket` (distribución) {#tuist_http_request_duration_nanosecond_bucket-distribution}
La distribución de la duración de las solicitudes salientes (incluido el tiempo
que pasaron esperando a ser asignadas a una conexión).

### `tuist_http_queue_count` (contador) {#tuist_http_queue_count-counter}

Número de solicitudes que se han recuperado del pool.

### `tuist_http_queue_duration_nanoseconds_sum` (suma) {#tuist_http_queue_duration_nanoseconds_sum-sum}

El tiempo que se tarda en recuperar una conexión del pool.

### `tuist_http_queue_idle_time_nanoseconds_sum` (suma) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

El tiempo que una conexión ha estado inactiva esperando a ser recuperada.

### `tuist_http_queue_duration_nanoseconds_bucket` (distribución) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

El tiempo que se tarda en recuperar una conexión del pool.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (distribución) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

El tiempo que una conexión ha estado inactiva esperando a ser recuperada.

### `tuist_http_connection_count` (contador) {#tuist_http_connection_count-counter}

El número de conexiones que se han establecido.

### `tuist_http_connection_duration_nanoseconds_sum` (suma) {#tuist_http_connection_duration_nanoseconds_sum-sum}

El tiempo que se tarda en establecer una conexión contra un host.

### `tuist_http_connection_duration_nanoseconds_bucket` (distribución) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

La distribución del tiempo que se tarda en establecer una conexión contra un
host.

### `tuist_http_send_count` (contador) {#tuist_http_send_count-counter}

Número de solicitudes que se han enviado una vez asignadas a una conexión del
pool.

### `tuist_http_send_duration_nanoseconds_sum` (suma) {#tuist_http_send_duration_nanoseconds_sum-sum}

Tiempo que tardan en completarse las peticiones una vez asignadas a una conexión
del pool.

### `tuist_http_send_duration_nanoseconds_bucket` (distribución) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

La distribución del tiempo que tardan en completarse las peticiones una vez
asignadas a una conexión del pool.

### `tuist_http_receive_count` (contador) {#tuist_http_receive_count-counter}

El número de respuestas que se han recibido de las solicitudes enviadas.

### `tuist_http_receive_duration_nanoseconds_sum` (suma) {#tuist_http_receive_duration_nanoseconds_sum-sum}

El tiempo empleado en recibir respuestas.

### `tuist_http_receive_duration_nanoseconds_bucket` (distribución) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

La distribución del tiempo dedicado a recibir respuestas.

### `tuist_http_queue_available_connections` (último_valor) {#tuist_http_queue_available_connections-last_value}

El número de conexiones disponibles en la cola.

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

El número de conexiones de cola que están en uso.
