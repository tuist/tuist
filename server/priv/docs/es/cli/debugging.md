---
{
  "title": "Depuración",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Aprende a depurar problemas con Tuist mediante registros y grabaciones de red."
}
---
# Depuración {#debugging}

Tuist ofrece varias herramientas para ayudarte a diagnosticar problemas cuando los comandos no se comportan como se espera.

> [!WARNING]
> Los datos de sesión pueden contener información sensible, como rutas de archivos, nombres de proyectos y cuerpos de solicitudes/respuestas. Aunque las cabeceras sensibles (como Authorization) se ocultan, ten cuidado al compartir los datos de sesión con otras personas.


## Datos de sesión {#session-data}

Si la invocación de un comando no produce los resultados esperados, puedes diagnosticar el problema inspeccionando los datos de sesión. La CLI envía los registros a [OSLog](https://developer.apple.com/documentation/os/oslog) y al sistema de archivos.

En cada ejecución, crea un directorio de sesión en `$XDG_STATE_HOME/tuist/sessions/{uuid}/`, donde `$XDG_STATE_HOME` toma el valor `~/.local/state` si la variable de entorno no está definida. También puedes usar `$TUIST_XDG_STATE_HOME` para establecer un directorio de estado específico de Tuist, que tiene prioridad sobre `$XDG_STATE_HOME`.

Cada directorio de sesión contiene:
- **`logs.txt`**: registros de texto de la sesión de la CLI
- **`network.har`**: archivo [HTTP Archive (HAR)](https://w3c.github.io/web-performance/specs/HAR/Overview.html) que contiene todas las solicitudes y respuestas de red realizadas durante la sesión

### Visualización de archivos HAR {#visualizing-har-files}

El archivo HAR registra todas las solicitudes y respuestas HTTP realizadas durante la sesión, lo que resulta útil para depurar problemas de comunicación con el servidor. Puedes abrir archivos HAR con varias herramientas:

- **[Proxyman](https://proxyman.io/)**: una aplicación nativa de macOS para ver y analizar el tráfico HTTP. Importa el archivo HAR mediante Archivo > Importar.
- **Herramientas para desarrolladores del navegador**: Chrome, Firefox y Safari permiten importar archivos HAR en su pestaña Red.
- **[HAR Viewer](http://www.softwareishard.com/har/viewer/)**: un visor web de archivos HAR.

> [!TIP]
> Obtén más información sobre la organización de directorios de Tuist y cómo configurar directorios personalizados en la <.localized_link href="/cli/directories">documentación de Directorios</.localized_link>.


De forma predeterminada, la CLI muestra la ruta de la sesión cuando la ejecución finaliza de manera inesperada. Si no lo hace, puedes encontrar los datos de sesión en la ruta mencionada anteriormente (es decir, el directorio de sesión más reciente).

Los directorios de sesión con más de 5 días de antigüedad se eliminan automáticamente. Tuist también mantiene como máximo 50 directorios de sesión inactivos de forma predeterminada, mientras preserva las sesiones propiedad de procesos de Tuist que se están ejecutando actualmente. En entornos de CI que ejecutan muchos comandos de Tuist con el mismo directorio de estado, puedes aumentar el límite de sesiones inactivas con `TUIST_SESSION_MAX_SESSIONS`, por ejemplo `TUIST_SESSION_MAX_SESSIONS=200`. Los valores no válidos, cero y los valores negativos se ignoran y Tuist vuelve al valor predeterminado de 50.

### Integración continua {#diagnose-issues-using-logs-ci}

En CI, donde los entornos son efímeros, es posible que quieras configurar tu pipeline de CI para exportar los datos de sesión de Tuist. La exportación de artefactos es una funcionalidad común en los servicios de CI y la configuración depende del servicio que utilices. Por ejemplo, en GitHub Actions, puedes usar la acción `actions/upload-artifact` para subir los datos de sesión como un artefacto:

```yaml
name: Node CI

on: [push]

env:
  TUIST_XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist session data
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-sessions
          path: /tmp/tuist/sessions/
```

### Depuración de la caché de Xcode {#cache-daemon-debugging}

Para depurar problemas de la caché de Xcode, establece `TUIST_CAS_LOG` en una ruta de archivo tanto al ejecutar `tuist setup cache` como al compilar. Tuist añade estadísticas y errores de la caché a ese archivo:

```bash
export TUIST_CAS_LOG=$HOME/.local/state/tuist/cas.log
tuist setup cache
xcodebuild build -scheme YourScheme
```

En CI, Tuist escribe este registro en `~/.local/state/tuist/cas.log` sin necesidad de configuración adicional.

## Ajuste de tiempos de espera y reintentos de red {#tuning-network-timeouts}

Todo el tráfico [HTTP (Hypertext Transfer Protocol)](https://developer.mozilla.org/en-US/docs/Web/HTTP) de Tuist, incluidas las llamadas al servidor, el registro, las vistas previas y las transferencias de artefactos de caché, pasa por una `URLSession` compartida con valores predeterminados razonables. En rutas de red lentas o congestionadas (por ejemplo, una configuración autoalojada que accede al almacenamiento de objetos a través de un proxy corporativo), una solicitud individual puede agotarse y alcanzar el tiempo de espera del recurso antes de completarse. En el caso de las descargas de caché, alcanzar el tiempo de espera hace que Tuist vuelva a compilar el módulo desde el código fuente, lo cual es mucho más costoso que esperar un poco más por el binario almacenado en caché. Puedes ajustar la configuración subyacente mediante variables de entorno; los valores predeterminados se aplican cuando no están definidas o tienen un valor no válido:

```bash
# Maximum time (in seconds) a single resource transfer can take before it's cancelled
# (default: 90, or 600 for whole-file transfers such as test-product shard artifacts)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE=600

# Maximum time (in seconds) to wait for new data on an existing request (default: 120)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST=300

# Maximum number of simultaneous connections per host (default: 20)
export TUIST_HTTP_MAXIMUM_CONNECTIONS_PER_HOST=40

# Maximum retries after the initial attempt (default: 3, maximum: 10)
export TUIST_HTTP_MAXIMUM_RETRY_COUNT=1

# Initial exponential backoff delay in milliseconds (default: 100, maximum: 30000)
export TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS=250
```

El tiempo de espera del recurso es un límite de reloj real para toda la transferencia, no un protector contra bloqueos, por lo que debe ser lo suficientemente grande para el artefacto más grande que transfieras. Las transferencias de archivos completos, como los productos de prueba que descarga un fragmento, tienen un valor predeterminado de 10 minutos en lugar de 90 segundos, y una transferencia bloqueada sigue fallando después de `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST` sin nuevos datos. Esas transferencias leen `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE` solo para aumentar su límite, nunca para reducirlo por debajo de 10 minutos, de modo que un valor elegido para que las solicitudes de caché fallen rápido tampoco cancela la descarga de los productos de prueba de un fragmento. Aumentar `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE` permite que una descarga lenta pero recuperable termine en lugar de agotar el tiempo de espera. Para las descargas de caché, eso significa obtener un acierto de caché en lugar de volver a compilar desde el código fuente, así que ajústalo deliberadamente: el mismo valor que mantiene activa una descarga lenta de caché también retrasa la vuelta a la compilación desde el código fuente. Reducir `TUIST_HTTP_MAXIMUM_RETRY_COUNT` puede evitar que un tiempo de espera más largo multiplique la peor espera posible entre varios intentos. Los retrasos de reintento se duplican tras cada fallo, incluyen hasta un retraso base de aleatoriedad y nunca superan los 30 segundos.

## Confianza en un certificado CA personalizado {#trusting-a-custom-ca-certificate}

De forma predeterminada, Tuist valida los certificados TLS frente al almacén raíz del sistema operativo. Cuando ejecutas un servidor Tuist o Kura autoalojado que utiliza una autoridad de certificación privada, Tuist también debe confiar en esa CA. Instalar la raíz en el llavero del sistema (y marcarla como confiable para SSL) es el enfoque estándar, pero suele ser poco práctico en hosts de CI sin interfaz gráfica, donde no hay una sesión GUI ni gestión de dispositivos móviles (MDM) para establecer el bit de confianza.

En esos casos, puedes indicar directamente a Tuist un paquete de certificados CA. El paquete puede estar en formato PEM (uno o más bloques concatenados `-----BEGIN CERTIFICATE-----`) o ser un único archivo DER. El almacén raíz del sistema sigue siendo de confianza junto con él, por lo que los certificados públicos siguen validándose con normalidad y la evaluación de certificados nunca se omite.

```bash
# Path to a PEM/DER CA bundle to trust on top of the system root store (default: unset)
export TUIST_CA_CERTIFICATE=/etc/ssl/certs/self-hosted-ca.pem
```

También puedes declararlo en tu <.localized_link href="/references/tuist-toml">archivo de configuración</.localized_link>:

```toml
[network]
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

La variable de entorno `TUIST_CA_CERTIFICATE` tiene prioridad sobre el archivo de configuración, lo que facilita proporcionarla como secreto de CI sin modificar el manifiesto confirmado.
