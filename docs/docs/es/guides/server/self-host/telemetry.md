---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# Telemetría {#telemetry}

Puede incorporar las métricas recopiladas por el servidor Tuist utilizando
[Prometheus](https://prometheus.io/) y una herramienta de visualización como
[Grafana](https://grafana.com/) para crear un panel personalizado que se adapte
a sus necesidades. Las métricas de Prometheus se sirven a través del punto final
`/metrics` en el puerto 9091. El
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
de Prometheus debe establecerse en menos de 10 000 segundos (recomendamos
mantener el valor predeterminado de 15 segundos).

## Análisis de PostHog. {#posthog-analytics}

Tuist se integra con [PostHog](https://posthog.com/) para el análisis del
comportamiento de los usuarios y el seguimiento de eventos. Esto le permite
comprender cómo interactúan los usuarios con su servidor Tuist, realizar un
seguimiento del uso de las funciones y obtener información sobre el
comportamiento de los usuarios en el sitio de marketing, el panel de control y
la documentación de la API.

### Configuración {#posthog-configuration}

La integración con PostHog es opcional y se puede habilitar configurando las
variables de entorno adecuadas. Una vez configurado, Tuist realizará un
seguimiento automático de los eventos de los usuarios, las visitas a las páginas
y los recorridos de los usuarios.

| Variable de entorno     | Descripción                              | Requerido | Por defecto | Ejemplo                                           |
| ----------------------- | ---------------------------------------- | --------- | ----------- | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | Tu clave API del proyecto PostHog.       | No        |             | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | URL del punto final de la API de PostHog | No        |             | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
Las analíticas solo se habilitan cuando se configuran tanto
`TUIST_POSTHOG_API_KEY` como `TUIST_POSTHOG_URL`. Si falta alguna de las
variables, no se enviarán eventos analíticos.
<!-- -->
:::

### Características {#posthog-features}

Cuando PostHog está habilitado, Tuist realiza un seguimiento automático de:

- **Identificación de usuario**: Los usuarios se identifican mediante su ID
  único y su dirección de correo electrónico.
- **Alias de usuario**: Los usuarios reciben un alias con su nombre de cuenta
  para facilitar su identificación.
- **Análisis de grupos**: Los usuarios se agrupan por el proyecto y la
  organización seleccionados para realizar análisis segmentados.
- **Secciones de página**: Los eventos incluyen superpropiedades que indican qué
  sección de la aplicación los generó:
  - `marketing` - Eventos de páginas de marketing y contenido público.
  - `Panel de control` - Eventos del panel de control de la aplicación principal
    y áreas autenticadas.
  - `api-docs` - Eventos de las páginas de documentación de la API.
- **Páginas vistas**: seguimiento automático de la navegación por la página
  mediante Phoenix LiveView.
- **Eventos personalizados**: Eventos específicos de la aplicación para el uso
  de funciones y las interacciones del usuario.

### Consideraciones sobre la privacidad {#posthog-privacy}

- Para los usuarios autenticados, PostHog utiliza el ID único del usuario como
  identificador distintivo e incluye su dirección de correo electrónico.
- Para los usuarios anónimos, PostHog utiliza la persistencia solo en memoria
  para evitar almacenar datos localmente.
- Todos los análisis respetan la privacidad del usuario y siguen las mejores
  prácticas de protección de datos.
- Los datos de PostHog se procesan de acuerdo con la política de privacidad de
  PostHog y su configuración.

## Métricas de Elixir {#elixir-metrics}

De forma predeterminada, incluimos métricas del tiempo de ejecución de Elixir,
BEAM, Elixir y algunas de las bibliotecas que utilizamos. A continuación se
muestran algunas de las métricas que puede esperar ver:

- [Aplicación](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

Recomendamos consultar esas páginas para saber qué métricas están disponibles y
cómo utilizarlas.

## Ejecuta métricas. {#runs-metrics}

Un conjunto de métricas relacionadas con Tuist Runs.

### `tuist_runs_total` (contador) {#tuist_runs_total-counter}

El número total de carreras de Tuist.

#### Etiquetas {#tuist-runs-total-tags}

| Etiqueta | Descripción                                                                              |
| -------- | ---------------------------------------------------------------------------------------- |
| `nombre` | El nombre del comando `tuist` que se ejecutó, como `build`, `test`, etc.                 |
| `is_ci`  | Un valor booleano que indica si el ejecutor era una máquina de CI o de un desarrollador. |
| `estado` | `0` en caso de éxito `` , `1` en caso de fallo `` .                                      |

### `tuist_runs_duration_milliseconds` (histograma) {#tuist_runs_duration_milliseconds-histogram}

La duración total de cada ejecución de tuist en milisegundos.

#### Etiquetas {#tuist-runs-duration-miliseconds-tags}

| Etiqueta | Descripción                                                                              |
| -------- | ---------------------------------------------------------------------------------------- |
| `nombre` | El nombre del comando `tuist` que se ejecutó, como `build`, `test`, etc.                 |
| `is_ci`  | Un valor booleano que indica si el ejecutor era una máquina de CI o de un desarrollador. |
| `estado` | `0` en caso de éxito `` , `1` en caso de fallo `` .                                      |

## Métricas de caché {#cache-metrics}

Un conjunto de métricas relacionadas con la caché de Tuist.

### `tuist_cache_events_total` (contador) {#tuist_cache_events_total-counter}

El número total de eventos de caché binaria.

#### Etiquetas {#tuist-cache-events-total-tags}

| Etiqueta     | Descripción                                                                  |
| ------------ | ---------------------------------------------------------------------------- |
| `event_type` | Puede ser cualquiera de los siguientes: `local_hit`, `remote_hit`, o `miss`. |

### `tuist_cache_uploads_total` (contador) {#tuist_cache_uploads_total-counter}

El número de cargas en la caché binaria.

### `tuist_cache_uploaded_bytes` (sum) {#tuist_cache_uploaded_bytes-sum}

El número de bytes cargados en la caché binaria.

### `tuist_cache_downloads_total` (contador) {#tuist_cache_downloads_total-counter}

El número de descargas a la caché binaria.

### `tuist_cache_downloaded_bytes` (sum) {#tuist_cache_downloaded_bytes-sum}

El número de bytes descargados desde la caché binaria.

---

## Métricas de vista previa {#previews-metrics}

Un conjunto de métricas relacionadas con la función de vista previa.

### `tuist_previews_uploads_total` (sum) {#tuist_previews_uploads_total-counter}

Número total de vistas previas subidas.

### `tuist_previews_downloads_total` (sum) {#tuist_previews_downloads_total-counter}

El número total de vistas previas descargadas.

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

| Etiqueta     | Descripción                                                  |
| ------------ | ------------------------------------------------------------ |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_get_object_size_duration_miliseconds` (histograma) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

La duración (en milisegundos) de la obtención del tamaño de un objeto desde el
almacenamiento remoto.

#### Etiquetas {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Etiqueta     | Descripción                                                  |
| ------------ | ------------------------------------------------------------ |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_get_object_size_count` (contador) {#tuist_storage_get_object_size_count-counter}

El número de veces que se ha recuperado el tamaño de un objeto del
almacenamiento remoto.

#### Etiquetas {#tuist-storage-get-object-size-count-tags}

| Etiqueta     | Descripción                                                  |
| ------------ | ------------------------------------------------------------ |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (histograma) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

La duración (en milisegundos) de la eliminación de todos los objetos del
almacenamiento remoto.

#### Etiquetas {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Etiqueta       | Descripción                                             |
| -------------- | ------------------------------------------------------- |
| `project_slug` | El slug del proyecto cuyos objetos se están eliminando. |


### `tuist_storage_delete_all_objects_count` (contador) {#tuist_storage_delete_all_objects_count-counter}

El número de veces que se han eliminado todos los objetos del proyecto del
almacenamiento remoto.

#### Etiquetas {#tuist-storage-delete-all-objects-count-tags}

| Etiqueta       | Descripción                                             |
| -------------- | ------------------------------------------------------- |
| `project_slug` | El slug del proyecto cuyos objetos se están eliminando. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (histograma) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

La duración (en milisegundos) del inicio de una carga en el almacenamiento
remoto.

#### Etiquetas {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Etiqueta     | Descripción                                                  |
| ------------ | ------------------------------------------------------------ |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_multipart_start_upload_duration_count` (contador) {#tuist_storage_multipart_start_upload_duration_count-counter}

El número de veces que se inició una carga en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-start-upload-duration-count-tags}

| Etiqueta     | Descripción                                                  |
| ------------ | ------------------------------------------------------------ |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histograma) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

La duración (en milisegundos) de la recuperación de un objeto como cadena desde
el almacenamiento remoto.

#### Etiquetas {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Etiqueta     | Descripción                                                  |
| ------------ | ------------------------------------------------------------ |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_get_object_as_string_count` (count) {#tuist_storage_get_object_as_string_count-count}

El número de veces que se ha recuperado un objeto como cadena desde el
almacenamiento remoto.

#### Etiquetas {#tuist-storage-get-object-as-string-count-tags}

| Etiqueta     | Descripción                                                  |
| ------------ | ------------------------------------------------------------ |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_check_object_existence_duration_milliseconds` (histograma) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

La duración (en milisegundos) de la comprobación de la existencia de un objeto
en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Etiqueta     | Descripción                                                  |
| ------------ | ------------------------------------------------------------ |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_check_object_existence_count` (count) {#tuist_storage_check_object_existence_count-count}

El número de veces que se comprobó la existencia de un objeto en el
almacenamiento remoto.

#### Etiquetas {#tuist-storage-check-object-existence-count-tags}

| Etiqueta     | Descripción                                                  |
| ------------ | ------------------------------------------------------------ |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histograma) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

La duración (en milisegundos) de la generación de una URL de descarga presignada
para un objeto en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Etiqueta     | Descripción                                                  |
| ------------ | ------------------------------------------------------------ |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |


### `tuist_storage_generate_download_presigned_url_count` (count) {#tuist_storage_generate_download_presigned_url_count-count}

El número de veces que se generó una URL de descarga prefirmada para un objeto
en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-generate-download-presigned-url-count-tags}

| Etiqueta     | Descripción                                                  |
| ------------ | ------------------------------------------------------------ |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histograma) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

La duración (en milisegundos) de la generación de una URL presignada de carga
parcial para un objeto en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Etiqueta      | Descripción                                                  |
| ------------- | ------------------------------------------------------------ |
| `object_key`  | La clave de búsqueda del objeto en el almacenamiento remoto. |
| `part_number` | El número de pieza del objeto que se está cargando.          |
| `upload_id`   | El ID de carga de la carga multiparte.                       |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

El número de veces que se generó una URL presignada de carga parcial para un
objeto en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Etiqueta      | Descripción                                                  |
| ------------- | ------------------------------------------------------------ |
| `object_key`  | La clave de búsqueda del objeto en el almacenamiento remoto. |
| `part_number` | El número de pieza del objeto que se está cargando.          |
| `upload_id`   | El ID de carga de la carga multiparte.                       |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histograma) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

La duración (en milisegundos) de completar una carga en el almacenamiento
remoto.

#### Etiquetas {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Etiqueta     | Descripción                                                  |
| ------------ | ------------------------------------------------------------ |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |
| `upload_id`  | El ID de carga de la carga multiparte.                       |


### `tuist_storage_multipart_complete_upload_count` (count) {#tuist_storage_multipart_complete_upload_count-count}

El número total de veces que se completó una carga en el almacenamiento remoto.

#### Etiquetas {#tuist-storage-multipart-complete-upload-count-tags}

| Etiqueta     | Descripción                                                  |
| ------------ | ------------------------------------------------------------ |
| `object_key` | La clave de búsqueda del objeto en el almacenamiento remoto. |
| `upload_id`  | El ID de carga de la carga multiparte.                       |

---

## Métricas de autenticación {#authentication-metrics}

Conjunto de métricas relacionadas con la autenticación.

### `tuist_authentication_token_refresh_error_total` (contador) {#tuist_authentication_token_refresh_error_total-counter}

El número total de errores de actualización de tokens.

#### Etiquetas {#tuist-authentication-token-refresh-error-total-tags}

| Etiqueta      | Descripción                                                                                  |
| ------------- | -------------------------------------------------------------------------------------------- |
| `cli_version` | La versión de Tuist CLI que encontró el error.                                               |
| `razón`       | El motivo del error de actualización del token, como `invalid_token_type` o `invalid_token`. |

---

## Métricas de los proyectos {#projects-metrics}

Un conjunto de métricas relacionadas con los proyectos.

### `tuist_projects_total` (last_value) {#tuist_projects_total-last_value}

El número total de proyectos.

---

## Métricas de cuentas {#accounts-metrics}

Conjunto de métricas relacionadas con las cuentas (usuarios y organizaciones).

### `tuist_accounts_organizations_total` (last_value) {#tuist_accounts_organizations_total-last_value}

El número total de organizaciones.

### `tuist_accounts_users_total` (last_value) {#tuist_accounts_users_total-last_value}

El número total de usuarios.


## Métricas de la base de datos {#database-metrics}

Conjunto de métricas relacionadas con la conexión a la base de datos.

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

El número de consultas de base de datos que se encuentran en una cola a la
espera de ser asignadas a una conexión de base de datos.

### `tuist_repo_pool_ready_conn_count` (last_value) {#tuist_repo_pool_ready_conn_count-last_value}

El número de conexiones de base de datos que están listas para ser asignadas a
una consulta de base de datos.


### `tuist_repo_pool_db_connection_connected` (contador) {#tuist_repo_pool_db_connection_connected-counter}

El número de conexiones que se han establecido con la base de datos.

### `tuist_repo_pool_db_connection_disconnected` (contador) {#tuist_repo_pool_db_connection_disconnected-counter}

El número de conexiones que se han desconectado de la base de datos.

## Métricas HTTP {#http-metrics}

Conjunto de métricas relacionadas con las interacciones de Tuist con otros
servicios a través de HTTP.

### `tuist_http_request_count` (contador) {#tuist_http_request_count-last_value}

El número de solicitudes HTTP salientes.

### `tuist_http_request_duration_nanosecond_sum` (sum) {#tuist_http_request_duration_nanosecond_sum-last_value}

La suma de la duración de las solicitudes salientes (incluido el tiempo que han
pasado esperando a ser asignadas a una conexión).

### `tuist_http_request_duration_nanosecond_bucket` (distribución) {#tuist_http_request_duration_nanosecond_bucket-distribution}
La distribución de la duración de las solicitudes salientes (incluido el tiempo
que pasaron esperando a ser asignadas a una conexión).

### `tuist_http_queue_count` (contador) {#tuist_http_queue_count-counter}

El número de solicitudes que se han recuperado del grupo.

### `tuist_http_queue_duration_nanoseconds_sum` (sum) {#tuist_http_queue_duration_nanoseconds_sum-sum}

El tiempo que se tarda en recuperar una conexión del grupo.

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

El tiempo que una conexión ha estado inactiva esperando a ser recuperada.

### `tuist_http_queue_duration_nanoseconds_bucket` (distribución) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

El tiempo que se tarda en recuperar una conexión del grupo.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (distribución) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

El tiempo que una conexión ha estado inactiva esperando a ser recuperada.

### `tuist_http_connection_count` (contador) {#tuist_http_connection_count-counter}

El número de conexiones que se han establecido.

### `tuist_http_connection_duration_nanoseconds_sum` (sum) {#tuist_http_connection_duration_nanoseconds_sum-sum}

El tiempo que se tarda en establecer una conexión con un host.

### `tuist_http_connection_duration_nanoseconds_bucket` (distribución) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

Distribución del tiempo que se tarda en establecer una conexión con un host.

### `tuist_http_send_count` (contador) {#tuist_http_send_count-counter}

El número de solicitudes que se han enviado una vez asignadas a una conexión del
grupo.

### `tuist_http_send_duration_nanoseconds_sum` (sum) {#tuist_http_send_duration_nanoseconds_sum-sum}

El tiempo que tardan en completarse las solicitudes una vez asignadas a una
conexión del grupo.

### `tuist_http_send_duration_nanoseconds_bucket` (distribución) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

La distribución del tiempo que tardan en completarse las solicitudes una vez
asignadas a una conexión del grupo.

### `tuist_http_receive_count` (contador) {#tuist_http_receive_count-counter}

El número de respuestas que se han recibido de las solicitudes enviadas.

### `tuist_http_receive_duration_nanoseconds_sum` (sum) {#tuist_http_receive_duration_nanoseconds_sum-sum}

El tiempo dedicado a recibir respuestas.

### `tuist_http_receive_duration_nanoseconds_bucket` (distribución) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

Distribución del tiempo dedicado a recibir respuestas.

### `tuist_http_queue_available_connections` (last_value) {#tuist_http_queue_available_connections-last_value}

El número de conexiones disponibles en la cola.

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

El número de conexiones de cola que están en uso.
