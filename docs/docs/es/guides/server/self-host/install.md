---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# Instalación de autoalojamiento {#self-host-installation}

Ofrecemos una versión autoalojada del servidor Tuist para organizaciones que
requieren un mayor control sobre su infraestructura. Esta versión te permite
alojar Tuist en tu propia infraestructura, garantizando que tus datos
permanezcan seguros y privados.

> [IMPORTANTE] LICENCIA REQUERIDA El autoalojamiento de Tuist requiere una
> licencia de pago legalmente válida. La versión local de Tuist sólo está
> disponible para organizaciones con el plan Enterprise. Si estás interesado en
> esta versión, ponte en contacto con
> [contact@tuist.dev](mailto:contact@tuist.dev).

## Liberar cadencia {#release-cadence}

Publicamos nuevas versiones de Tuist continuamente, a medida que nuevos cambios
liberables aterrizan en main. Seguimos [semantic
versioning](https://semver.org/) para asegurar un versionado y compatibilidad
predecibles.

El componente principal se utiliza para señalar cambios de última hora en el
servidor Tuist que requerirán coordinación con los usuarios locales. No esperes
que lo utilicemos, y en caso de que fuera necesario, ten por seguro que
trabajaremos contigo para que la transición sea fluida.

## Despliegue continuo {#continuous-deployment}

Te recomendamos encarecidamente que configures un sistema de despliegue continuo
que despliegue automáticamente la última versión de Tuist todos los días. De
este modo, siempre tendrás acceso a las últimas funciones, mejoras y
actualizaciones de seguridad.

Este es un ejemplo de flujo de trabajo de Acciones de GitHub que comprueba y
despliega nuevas versiones diariamente:

```yaml
name: Update Tuist Server
on:
  schedule:
    - cron: '0 3 * * *' # Run daily at 3 AM UTC
  workflow_dispatch: # Allow manual runs

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - name: Check and deploy latest version
        run: |
          # Your deployment commands here
          # Example: docker pull ghcr.io/tuist/tuist:latest
          # Deploy to your infrastructure
```

## Requisitos de tiempo de ejecución {#runtime-requirements}

Esta sección describe los requisitos para alojar el servidor Tuist en tu
infraestructura.

### Ejecutar imágenes virtualizadas con Docker {#running-dockervirtualized-images}

Distribuimos el servidor como una imagen [Docker](https://www.docker.com/) a
través del [Registro de contenedores de
GitHub](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

Para ejecutarlo, su infraestructura debe soportar la ejecución de imágenes
Docker. Tenga en cuenta que la mayoría de los proveedores de infraestructura lo
admiten porque se ha convertido en el contenedor estándar para distribuir y
ejecutar software en entornos de producción.

### Base de datos Postgres {#postgres-database}

Además de ejecutar las imágenes Docker, necesitarás una [base de datos
Postgres](https://www.postgresql.org/) para almacenar datos relacionales. La
mayoría de los proveedores de infraestructura incluyen bases de datos Posgres en
su oferta (por ejemplo, [AWS](https://aws.amazon.com/rds/postgresql/) y [Google
Cloud](https://cloud.google.com/sql/docs/postgres)).

Para realizar análisis de alto rendimiento, utilizamos una [extensión de
Timescale Postgres](https://www.timescale.com/). Debe asegurarse de que
TimescaleDB está instalado en la máquina que ejecuta la base de datos Postgres.
Siga las instrucciones de instalación
[aquí](https://docs.timescale.com/self-hosted/latest/install/) para obtener más
información. Si no puede instalar la extensión Timescale, puede configurar su
propio panel de control utilizando las métricas de Prometheus.

> [El punto de entrada de la imagen Docker ejecuta automáticamente cualquier
> migración de esquema pendiente antes de iniciar el servicio.

### Base de datos ClickHouse {#clickhouse-database}

Para almacenar grandes cantidades de datos, utilizamos
[ClickHouse](https://clickhouse.com/). Algunas características, como la
información de construcción, sólo funcionarán con ClickHouse activado. Con el
tiempo, ClickHouse sustituirá a la extensión Postgres de Timescale. Puedes
elegir entre alojar ClickHouse tú mismo o utilizar su servicio alojado.

> [INFO] MIGRACIONES El punto de entrada de la imagen Docker ejecuta
> automáticamente cualquier migración de esquema ClickHouse pendiente antes de
> iniciar el servicio.

### Almacenamiento {#storage}

También necesitarás una solución para almacenar archivos (p. ej., binarios de
frameworks y bibliotecas). Actualmente admitimos cualquier almacenamiento
compatible con S3.

## Configuración {#configuration}

La configuración del servicio se realiza en tiempo de ejecución a través de
variables de entorno. Dada la naturaleza sensible de estas variables,
aconsejamos encriptarlas y almacenarlas en soluciones seguras de gestión de
contraseñas. Ten por seguro que Tuist maneja estas variables con sumo cuidado,
asegurándose de que nunca se muestren en los registros.

> [Las variables necesarias se verifican en el arranque. Si falta alguna, el
> lanzamiento fallará y el mensaje de error detallará las variables ausentes.

### Configuración de la licencia {#license-configuration}

Como usuario local, recibirás una clave de licencia que deberás exponer como
variable de entorno. Esta clave se utiliza para validar la licencia y garantizar
que el servicio se ejecuta dentro de los términos del acuerdo.

| Variable de entorno                 | Descripción                                                                                                                                                                                                                                                                              | Requerido | Por defecto | Ejemplos                                  |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- | ----------- | ----------------------------------------- |
| `TUIST_LICENSE`                     | La licencia proporcionada tras la firma del acuerdo de nivel de servicio                                                                                                                                                                                                                 | Sí.       |             | `******`                                  |
| `TUIST_LICENCIA_CERTIFICADO_BASE64` | **Alternativa excepcional a `TUIST_LICENSE`**. Certificado público codificado en base64 para la validación de licencias offline en entornos con cortafuegos donde el servidor no puede contactar con servicios externos. Utilizar únicamente cuando `TUIST_LICENSE` no pueda utilizarse. | Sí.       |             | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* Se debe proporcionar `TUIST_LICENSE` o `TUIST_LICENSE_CERTIFICATE_BASE64`,
pero no ambos. Utilice `TUIST_LICENSE` para implementaciones estándar.

> [IMPORTANTE] FECHA DE CADUCIDAD Las licencias tienen una fecha de caducidad.
> Los usuarios recibirán un aviso al utilizar los comandos de Tuist que
> interactúan con el servidor si la licencia caduca en menos de 30 días. Si
> estás interesado en renovar tu licencia, ponte en contacto con
> [contact@tuist.dev](mailto:contact@tuist.dev).

### Configuración del entorno base {#base-environment-configuration}

| Variable de entorno                   | Descripción                                                                                                                                                                                                                                                | Requerido | Por defecto                       | Ejemplos                                                                          |                                                                                                                                    |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- | --------------------------------- | --------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | La URL base para acceder a la instancia desde Internet                                                                                                                                                                                                     | Sí        |                                   | https://tuist.dev                                                                 |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`               | La clave que se utilizará para cifrar la información (por ejemplo, las sesiones en una cookie)                                                                                                                                                             | Sí        |                                   |                                                                                   | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`           | Pepper para generar contraseñas hash                                                                                                                                                                                                                       | No        | `$TUIST_SECRET_KEY_BASE`          |                                                                                   |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`             | Clave secreta para generar fichas aleatorias                                                                                                                                                                                                               | No        | `$TUIST_SECRET_KEY_BASE`          |                                                                                   |                                                                                                                                    |
| `TUIST_SECRET_KEY_ENCRYPTION`         | Clave de 32 bytes para el cifrado AES-GCM de datos confidenciales                                                                                                                                                                                          | No        | `$TUIST_SECRET_KEY_BASE`          |                                                                                   |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | Cuando `1` configura la aplicación para utilizar direcciones IPv6                                                                                                                                                                                          | No        | `0`                               | `1`                                                                               |                                                                                                                                    |
| `TUIST_LOG_LEVEL`                     | Nivel de registro de la aplicación                                                                                                                                                                                                                         | No        | `información`                     | [Niveles de registro](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | La clave privada codificada en base64 utilizada para que la aplicación de GitHub desbloquee funciones adicionales como la publicación automática de comentarios de relaciones públicas.                                                                    | No        | `LS0tLS1CRUdJTiBSU0EgUFJVkFUR...` |                                                                                   |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY`        | La clave privada utilizada por la aplicación de GitHub para desbloquear funciones adicionales como la publicación automática de comentarios PR. **Recomendamos utilizar la versión codificada en base64 para evitar problemas con caracteres especiales.** | No        | `-----BEGIN RSA...`               |                                                                                   |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`              | Una lista separada por comas de los nombres de usuario que tienen acceso a las URL de las operaciones.                                                                                                                                                     | No        |                                   | `usuario1,usuario2`                                                               |                                                                                                                                    |
| `TUIST_WEB`                           | Habilitar el punto final del servidor web                                                                                                                                                                                                                  | No        | `1`                               | `1` o `0`                                                                         |                                                                                                                                    |

### Configuración de la base de datos {#database-configuration}

Las siguientes variables de entorno se utilizan para configurar la conexión a la
base de datos:

| Variable de entorno                     | Descripción                                                                                                                                                                                                                       | Requerido | Por defecto | Ejemplos                                                               |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- | ----------- | ---------------------------------------------------------------------- |
| `URL_BASE_DE_DATOS`                     | La URL para acceder a la base de datos Postgres. Tenga en cuenta que la URL debe contener la información de autenticación                                                                                                         | Sí        |             | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`                  | La URL para acceder a la base de datos de ClickHouse. Tenga en cuenta que la URL debe contener la información de autenticación                                                                                                    | No        |             | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_UTILIZAR_SSL_PARA_BASE_DE_DATOS` | Cuando es verdadero, utiliza [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) para conectarse a la base de datos                                                                                                     | No        | `1`         | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`              | El número de conexiones a mantener abiertas en el pool de conexiones.                                                                                                                                                             | No        | `10`        | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`           | El intervalo (en milisegundos) para comprobar si todas las conexiones retiradas del pool tardaron más que el intervalo de cola [(Más información)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)  | No        | `300`       | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL`         | El tiempo umbral (en milisegundos) en la cola que el pool utiliza para determinar si debe empezar a descartar nuevas conexiones [(Más información)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | No        | `1000`      | `1000`                                                                 |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS`    | Intervalo de tiempo en milisegundos entre las descargas del búfer ClickHouse                                                                                                                                                      | No        | `5000`      | `5000`                                                                 |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE`      | Tamaño máximo del búfer ClickHouse en bytes antes de forzar un vaciado                                                                                                                                                            | No        | `1000000`   | `1000000`                                                              |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE`     | Número de procesos de buffer ClickHouse a ejecutar                                                                                                                                                                                | No        | `5`         | `5`                                                                    |

### Configuración del entorno de autenticación {#authentication-environment-configuration}

Facilitamos la autenticación a través de [proveedores de identidad
(IdP)](https://en.wikipedia.org/wiki/Identity_provider). Para utilizarlo,
asegúrate de que todas las variables de entorno necesarias para el proveedor
elegido están presentes en el entorno del servidor. **Si faltan variables,**
hará que Tuist eluda a ese proveedor.

#### GitHub {#github}

Recomendamos autenticarse usando una [GitHub
App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)
pero también puedes usar la [OAuth
App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app).
Asegúrate de incluir todas las variables de entorno esenciales especificadas por
GitHub en el entorno del servidor. La ausencia de variables hará que Tuist pase
por alto la autenticación de GitHub. Para configurar correctamente la app de
GitHub:
- En la configuración general de la aplicación GitHub:
    - Copie el `Client ID` y establézcalo como `TUIST_GITHUB_APP_CLIENT_ID`
    - Crea y copia un nuevo `secreto de cliente` y establécelo como
      `TUIST_GITHUB_APP_CLIENT_SECRET`
    - Establezca la URL de devolución de llamada `` como
      `http://YOUR_APP_URL/users/auth/github/callback`. `YOUR_APP_URL` también
      puede ser la dirección IP de su servidor.
- Se requieren los siguientes permisos:
  - Repositorios:
    - Pull requests: Lectura y escritura
  - Cuentas:
    - Direcciones de correo electrónico: Sólo lectura

En la sección `Permisos y eventos`'s `Permisos de cuenta`, establezca el permiso
`Direcciones de correo electrónico` en `Sólo lectura`.

A continuación, tendrás que exponer las siguientes variables de entorno en el
entorno donde se ejecuta el servidor Tuist:

| Variable de entorno              | Descripción                            | Requerido | Por defecto | Ejemplos                                   |
| -------------------------------- | -------------------------------------- | --------- | ----------- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | ID de cliente de la aplicación GitHub  | Sí        |             | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | El secreto de cliente de la aplicación | Sí        |             | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google {#google}

Puedes configurar la autenticación con Google utilizando [OAuth
2](https://developers.google.com/identity/protocols/oauth2). Para ello,
necesitarás crear una nueva credencial de tipo OAuth client ID. Cuando crees las
credenciales, selecciona "Aplicación Web" como tipo de aplicación, nómbrala
`Tuist`, y establece el URI de redirección en
`{base_url}/users/auth/google/callback` donde `base_url` es la URL en la que se
ejecuta tu servicio alojado. Una vez creada la aplicación, copia el ID y el
secreto del cliente y establécelos como variables de entorno `GOOGLE_CLIENT_ID`
y `GOOGLE_CLIENT_SECRET` respectivamente.

> [Puede que necesites crear una pantalla de consentimiento. Cuando lo haga,
> asegúrese de añadir los ámbitos `userinfo.email` y `openid` y marque la
> aplicación como interna.

#### Okta {#okta}

Puedes habilitar la autenticación con Okta a través del protocolo [OAuth
2.0](https://oauth.net/2/). Tendrás que [crear una
app](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)
en Okta siguiendo <LocalizedLink href="/guides/integrations/sso#okta">estas
instrucciones</LocalizedLink>.

Deberá configurar las siguientes variables de entorno una vez que obtenga el id
de cliente y el secreto durante la configuración de la aplicación Okta:

| Variable de entorno          | Descripción                                                                                 | Requerido | Por defecto | Ejemplos |
| ---------------------------- | ------------------------------------------------------------------------------------------- | --------- | ----------- | -------- |
| `TUIST_OKTA_1_CLIENT_ID`     | El ID de cliente para autenticarse contra Okta. El número debe ser el ID de su organización | Sí        |             |          |
| `TUIST_OKTA_1_CLIENT_SECRET` | El secreto del cliente para autenticarse contra Okta                                        | Sí        |             |          |

El número `1` debe sustituirse por el ID de su organización. Normalmente será el
1, pero compruébelo en su base de datos.

### Configuración del entorno de almacenamiento {#storage-environment-configuration}

Tuist necesita almacenamiento para albergar los artefactos cargados a través de
la API. **Para que Tuist funcione con eficacia, es esencial configurar una de
las soluciones de almacenamiento compatibles,**.

#### Almacenes compatibles con S3 {#s3compliant-storages}

Puede utilizar cualquier proveedor de almacenamiento compatible con S3 para
almacenar artefactos. Las siguientes variables de entorno son necesarias para
autenticar y configurar la integración con el proveedor de almacenamiento:

| Variable de entorno                                 | Descripción                                                                                                                                              | Requerido | Por defecto                         | Ejemplos                                   |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- | ----------------------------------- | ------------------------------------------ |
| `TUIST_ACCESS_KEY_ID` o `AWS_ACCESS_KEY_ID`         | El ID de la clave de acceso para autenticar contra el proveedor de almacenamiento                                                                        | Sí        |                                     | `AKIAIOSFOD`                               |
| `TUIST_SECRET_ACCESS_KEY` o `AWS_SECRET_ACCESS_KEY` | La clave de acceso secreta para autenticarse contra el proveedor de almacenamiento                                                                       | Sí        |                                     | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` o `AWS_REGION`                    | La región donde se encuentra el cubo                                                                                                                     | No        | `auto`                              | `us-oeste-2`                               |
| `TUIST_S3_ENDPOINT` o `AWS_ENDPOINT`                | El punto final del proveedor de almacenamiento                                                                                                           | Sí        |                                     | `https://s3.us-west-2.amazonaws.com`       |
| `TUIST_S3_BUCKET_NAME`                              | El nombre del cubo donde se almacenarán los artefactos                                                                                                   | Sí        |                                     | `tuist-artifacts`                          |
| `TUIST_S3_CONNECT_TIMEOUT`                          | El tiempo de espera (en milisegundos) para establecer una conexión con el proveedor de almacenamiento.                                                   | No        | `3000`                              | `3000`                                     |
| `TUIST_S3_RECEIVE_TIMEOUT`                          | El tiempo de espera (en milisegundos) para recibir datos del proveedor de almacenamiento.                                                                | No        | `5000`                              | `5000`                                     |
| `TUIST_S3_POOL_TIMEOUT`                             | El tiempo de espera (en milisegundos) para el grupo de conexiones al proveedor de almacenamiento. Utilice `infinity` para no tener tiempo de espera.     | No        | `5000`                              | `5000`                                     |
| `TUIST_S3_POOL_MAX_IDLE_TIME`                       | El tiempo máximo de inactividad (en milisegundos) para las conexiones en el pool. Utilice `infinity` para mantener las conexiones vivas indefinidamente. | No        | `infinito`                          | `60000`                                    |
| `TUIST_S3_POOL_SIZE`                                | Número máximo de conexiones por pool                                                                                                                     | No        | `500`                               | `500`                                      |
| `TUIST_S3_POOL_COUNT`                               | Número de grupos de conexiones que se van a utilizar                                                                                                     | No        | Número de programadores del sistema | `4`                                        |
| `TUIST_S3_PROTOCOLO`                                | El protocolo a utilizar cuando se conecta al proveedor de almacenamiento (`http1` o `http2`)                                                             | No        | `http1`                             | `http1`                                    |
| `TUIST_S3_VIRTUAL_HOST`                             | Si la URL debe construirse con el nombre del cubo como subdominio (host virtual).                                                                        | No        | `falso`                             | `1`                                        |

> [NOTA] Autenticación AWS con Web Identity Token desde variables de entorno Si
> tu proveedor de almacenamiento es AWS y quieres autenticarte usando un token
> de identidad web, puedes establecer la variable de entorno
> `TUIST_S3_AUTHENTICATION_METHOD` a `aws_web_identity_token_from_env_vars`, y
> Tuist usará ese método usando las variables de entorno AWS convencionales.

#### Almacenamiento en la nube de Google {#google-cloud-storage}
Para Google Cloud Storage, siga [estos
documentos](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)
para obtener el par `AWS_ACCESS_KEY_ID` y `AWS_SECRET_ACCESS_KEY`. El
`AWS_ENDPOINT` debe establecerse en `https://storage.googleapis.com`. Otras
variables de entorno son las mismas que para cualquier otro almacenamiento
compatible con S3.

### Configuración de la plataforma Git {#git-platform-configuration}

Tuist puede <LocalizedLink href="/guides/server/authentication">integrarse con
plataformas Git</LocalizedLink> para proporcionar funciones extra como la
publicación automática de comentarios en tus pull requests.

#### GitHub {#plataforma-github}

Necesitarás [crear una app
GitHub](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps).
Puedes reutilizar la que creaste para la autenticación, a menos que hayas creado
una app GitHub OAuth. En la sección `Permisos y eventos`'s `Permisos de
repositorio`, necesitarás establecer adicionalmente el permiso `Pull requests` a
`Lectura y escritura`.

Además de `TUIST_GITHUB_APP_CLIENT_ID` y `TUIST_GITHUB_APP_CLIENT_SECRET`,
necesitarás las siguientes variables de entorno:

| Variable de entorno            | Descripción                              | Requerido | Por defecto | Ejemplos                                 |
| ------------------------------ | ---------------------------------------- | --------- | ----------- | ---------------------------------------- |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | La clave privada de la aplicación GitHub | Sí        |             | `-----EMPEZAR CLAVE PRIVADA RSA-----...` |

## Despliegue {#deployment}

La imagen Docker oficial de Tuist está disponible en:
```
ghcr.io/tuist/tuist
```

### Extracción de la imagen Docker {#pulling-the-docker-image}

Puede recuperar la imagen ejecutando el siguiente comando:

```bash
docker pull ghcr.io/tuist/tuist:latest
```

O sacar una versión específica:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Despliegue de la imagen Docker {#deploying-the-docker-image}

El proceso de despliegue de la imagen Docker variará en función del proveedor de
nube elegido y del enfoque de despliegue continuo de su organización. Dado que
la mayoría de las soluciones y herramientas en la nube, como
[Kubernetes](https://kubernetes.io/), utilizan imágenes Docker como unidades
fundamentales, los ejemplos de esta sección deberían ajustarse bien a su
configuración actual.

> [IMPORTANTE] Si su proceso de despliegue necesita validar que el servidor está
> en funcionamiento, puede enviar una petición HTTP `GET` a `/ready` y confirmar
> un código de estado `200` en la respuesta.

#### Fly {#fly}

Para desplegar la aplicación en [Fly](https://fly.io/), necesitará un archivo de
configuración `fly.toml`. Considere la posibilidad de generarlo dinámicamente
dentro de su canal de despliegue continuo (CD). A continuación se muestra un
ejemplo de referencia para su uso:

```toml
app = "tuist"
primary_region = "fra"
kill_signal = "SIGINT"
kill_timeout = "5s"

[experimental]
  auto_rollback = true

[env]
  # Your environment configuration goes here
  # Or exposed through Fly secrets

[processes]
  app = "/usr/local/bin/hivemind /app/Procfile"

[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = false
  processes = ["app"]
  http_options = { h2_backend = true }

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
  [services.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

  [[services.http_checks]]
    interval = 10000
    grace_period = "10s"
    method = "get"
    path = "/ready"
    protocol = "http"
    timeout = 2000
    tls_skip_verify = false
    [services.http_checks.headers]

[[statics]]
  guest_path = "/app/public"
  url_prefix = "/"
```

A continuación, puede ejecutar `fly launch --local-only --no-deploy` para lanzar
la aplicación. En despliegues posteriores, en lugar de ejecutar `fly launch
--local-only`, tendrás que ejecutar `fly deploy --local-only`. Fly.io no permite
extraer imágenes Docker privadas, por lo que necesitamos usar la bandera
`--local-only`.

### Docker Compose {#docker-compose}

A continuación se muestra un ejemplo de un archivo `docker-compose.yml` que
puede utilizar como referencia para desplegar el servicio:

```yaml
version: '3.8'
services:
  db:
    image: timescale/timescaledb-ha:pg16
    restart: always
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - PGDATA=/var/lib/postgresql/data/pgdata
    ports:
      - '5432:5432'
    volumes:
      - db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  pgweb:
    container_name: pgweb
    restart: always
    image: sosedoff/pgweb
    ports:
      - "8081:8081"
    links:
      - db:db
    environment:
      PGWEB_DATABASE_URL: postgres://postgres:postgres@db:5432/postgres?sslmode=disable
    depends_on:
      - db

  tuist:
    image: ghcr.io/tuist/tuist:latest
    container_name: tuist
    depends_on:
      - db
    ports:
      - "80:80"
      - "8080:8080"
      - "443:443"
    expose:
      - "80"
      - "8080"
      - "443:443"
    environment:
      # Base Tuist Env - https://docs.tuist.io/en/guides/dashboard/on-premise/install#base-environment-configuration
      TUIST_USE_SSL_FOR_DATABASE: "0"
      TUIST_LICENSE:  # ...
      DATABASE_URL: postgres://postgres:postgres@db:5432/postgres?sslmode=disable
      TUIST_APP_URL: https://localhost:8080
      TUIST_SECRET_KEY_BASE: # ...
      WEB_CONCURRENCY: 80

      # Auth - one method
      # GitHub Auth - https://docs.tuist.io/en/guides/dashboard/on-premise/install#github
      TUIST_GITHUB_OAUTH_ID:
      TUIST_GITHUB_APP_CLIENT_SECRET:

      # Okta Auth - https://docs.tuist.io/en/guides/dashboard/on-premise/install#okta
      TUIST_OKTA_SITE:
      TUIST_OKTA_CLIENT_ID:
      TUIST_OKTA_CLIENT_SECRET:
      TUIST_OKTA_AUTHORIZE_URL: # Optional
      TUIST_OKTA_TOKEN_URL: # Optional
      TUIST_OKTA_USER_INFO_URL: # Optional
      TUIST_OKTA_EVENT_HOOK_SECRET: # Optional

      # Storage
      AWS_ACCESS_KEY_ID: # ...
      AWS_SECRET_ACCESS_KEY: # ...
      AWS_S3_REGION: # ...
      AWS_ENDPOINT: # https://amazonaws.com
      TUIST_S3_BUCKET_NAME: # ...

      # Other

volumes:
  db:
    driver: local
```

## Métricas de Prometheus {#prometheus-metrics}

Tuist expone las métricas de Prometheus en `/metrics` para ayudarte a
monitorizar tu instancia autoalojada. Estas métricas incluyen:

### Métricas del cliente HTTP de Finch {#finch-metrics}

Tuist utiliza [Finch](https://github.com/sneako/finch) como cliente HTTP y
expone métricas detalladas sobre las peticiones HTTP:

#### Solicitar métricas
- `tuist_prom_ex_finch_request_count_total` - Número total de solicitudes de
  Finch (contador)
  - Etiquetas: `finch_name`, `método`, `esquema`, `host`, `puerto`, `estado`
- `tuist_prom_ex_finch_request_duration_milliseconds` - Duración de las
  solicitudes HTTP (histograma)
  - Etiquetas: `finch_name`, `método`, `esquema`, `host`, `puerto`, `estado`
  - Cubos: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
- `tuist_prom_ex_finch_request_exception_count_total` - Número total de
  excepciones de solicitud de Finch (contador)
  - Etiquetas: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`,
    `reason`

#### Métricas de cola de la agrupación de conexiones
- `tuist_prom_ex_finch_queue_duration_milliseconds` - Tiempo de espera en la
  cola del pool de conexiones (histograma)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Cubos: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - Tiempo que la conexión
  pasó inactiva antes de ser utilizada (histograma)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Cubos: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 5s, 10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Número total de
  excepciones en la cola de Finch (contador)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### Métricas de conexión
- `tuist_prom_ex_finch_connect_duration_milliseconds` - Tiempo empleado en
  establecer una conexión (histograma)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`, `error`
  - Cubos: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s
- `tuist_prom_ex_finch_connect_count_total` - Número total de intentos de
  conexión (contador)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`

#### Enviar métricas
- `tuist_prom_ex_finch_send_duration_milliseconds` - Tiempo empleado en enviar
  la solicitud (histograma)
  - Etiquetas: `finch_name`, `método`, `esquema`, `host`, `puerto`, `error`
  - Cubos: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - Tiempo de inactividad de
  la conexión antes del envío (histograma)
  - Etiquetas: `finch_name`, `método`, `esquema`, `host`, `puerto`, `error`
  - Cubos: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms

Todas las métricas de histograma ofrecen las variantes `_bucket`, `_sum`, y
`_count` para un análisis detallado.

### Otras métricas

Además de las métricas de Finch, Tuist expone métricas para:
- Rendimiento de la máquina virtual BEAM
- Métricas de lógica empresarial personalizadas (almacenamiento, cuentas,
  proyectos, etc.)
- Rendimiento de la base de datos (cuando se utiliza la infraestructura alojada
  en Tuist)

## Operaciones {#operations}

Tuist proporciona un conjunto de utilidades en `/ops/` que puedes utilizar para
gestionar tu instancia.

> [IMPORTANTE] Autorización Sólo las personas cuyos handles aparecen en la lista
> de la variable de entorno `TUIST_OPS_USER_HANDLES` pueden acceder a los
> endpoints `/ops/`.

- **Errores (`/ops/errors`):** Puedes ver errores inesperados que ocurrieron en
  la aplicación. Esto es útil para depurar y entender lo que salió mal y
  podríamos pedirle que comparta esta información con nosotros si se enfrenta a
  problemas.
- **Panel de control (`/ops/dashboard`):** Puedes ver un panel de control que
  proporciona información sobre el rendimiento y la salud de la aplicación (por
  ejemplo, consumo de memoria, procesos en ejecución, número de peticiones).
  Este panel puede ser muy útil para saber si el hardware que estás utilizando
  es suficiente para soportar la carga.
