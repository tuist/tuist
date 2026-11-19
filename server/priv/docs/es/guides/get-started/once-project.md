---
{
  "title": "Once project",
  "titleTemplate": ":title · Primeros pasos · Guías · Tuist",
  "description": "Conecta Once a Tuist para aprovechar la caché compartida, análisis en tiempo real de compilaciones y tests, distribución de tests y vistas previas de aplicaciones."
}
---
# Proyecto Once {#once-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/once-project
```

:::

[Once](https://buildonce.dev) ejecuta scripts y grafos de compilación cacheables. Conéctalo a Tuist para compartir trabajo en caché entre máquinas, seguir las ejecuciones en directo y publicar aplicaciones para que tu equipo las pruebe. Mantén las fuentes de tu proyecto y las definiciones de compilación existentes; la integración se configura en `once.toml`.

## Requisitos previos

- [Once](https://buildonce.dev/docs/guide/getting-started) instalado y un espacio de trabajo o un script cacheable.
- Una cuenta de Tuist. La CLI de Tuist no es necesaria para la integración con Once.

## Conectar el proyecto {#connect-the-project}

Desde la raíz de tu repositorio, ejecuta:

```bash
once connect --provider tuist --create
```

Once inicia sesión cuando es necesario, crea un proyecto de Tuist bajo tu cuenta personal y escribe la vinculación del proveedor en `once.toml`. Consulta [Connect a project](https://buildonce.dev/docs/guide/infrastructure/connect) para seleccionar otra cuenta o un proyecto existente.

Para un proyecto de Tuist existente, configura tú mismo el proveedor y la vinculación de caché:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

Sustituye `acme` y `app` por los identificadores de tu cuenta y proyecto, y luego autentícate:

```bash
once auth login --provider tuist
```

Confirma `once.toml` en el control de versiones para que tus compañeros y la CI compartan el destino, no tus credenciales. Cada desarrollador inicia sesión en su propia máquina.

## Caché compartida

Una caché local solo ayuda a la máquina que la pobló. Con Tuist configurado, Once puede restaurar resultados coincidentes generados por otro desarrollador o por la CI en lugar de volver a ejecutar el mismo trabajo.

Ejecuta tu script cacheable o un objetivo del grafo como de costumbre:

```bash
once build MyApplication
```

Abre **Once Cache** en el panel para inspeccionar la actividad de la caché remota. Consulta <.localized_link href="/guides/features/cache/once">Once cache</.localized_link> para ver la configuración y comprobar la reutilización entre máquinas.

## Análisis de compilaciones

Once imprime un enlace al panel cuando comienza una ejecución. Ábrelo para seguir el grafo, el estado de las acciones y las decisiones de caché mientras avanza la ejecución. Usa **Builds** para comparar el rendimiento local y de la CI e investigar acciones fallidas. Conserva los registros de la CI para obtener la salida completa del proceso; la ingesta de registros brutos de acción no está disponible actualmente.

Consulta <.localized_link href="/guides/features/build-insights/once">Once build insights</.localized_link> para saber qué se registra y cómo acceder a ello desde agentes de programación o Grafana.

## Análisis de tests y sharding

Ejecuta tus objetivos de test de Once:

```bash
once test
```

Abre **Tests** para inspeccionar las suites, casos, duraciones y fallos reportados. Los resultados dependen de las capacidades de reporting del objetivo de test; una acción que ejecuta un proceso de test no genera automáticamente un informe por caso.

Cuando la suite supera la capacidad de una sola máquina, crea un plan de sharding alojado y distribuye sus lotes entre los workers de la CI. Consulta <.localized_link href="/guides/features/test-insights/once">Once test insights</.localized_link> y <.localized_link href="/guides/features/test-sharding/once">Once test sharding</.localized_link>.

## Previews y tamaño del paquete

Añade una vinculación de artefactos al mismo proveedor para publicar aplicaciones compatibles de Android, simulador de Apple y macOS:

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
once artifact publish MyApplication --track review
```

El enlace devuelto abre las previews de tu proyecto; el procesamiento puede tardar un momento. Consulta <.localized_link href="/guides/features/previews/once">Once previews</.localized_link> para conocer los requisitos de firma y la publicación opcional tras las compilaciones.

Para rastrear el tamaño del paquete, usa la CLI de Tuist por separado sobre un `.app`, `.ipa`, `.xcarchive`, `.apk` o `.aab` compilado. Sigue la <.localized_link href="/guides/features/bundle-insights">guía de análisis de paquetes de Apple o Android</.localized_link>; publicar un artefacto de Once no sube automáticamente un informe de tamaño del paquete.

## Integración continua

Usa un token de cuenta autorizado para las operaciones del proyecto en `TUIST_TOKEN`, o autentícate a través de la identidad OpenID Connect de un proveedor de CI compatible:

```bash
once auth login --provider tuist --no-browser
once build MyApplication
once test
```

En GitHub Actions, concede al job `id-token: write` y `contents: read`. Consulta <.localized_link href="/guides/integrations/continuous-integration#once">Once on continuous integration</.localized_link> para ver un ejemplo. El inicio de sesión personal de un desarrollador no es una credencial de CI.

## Ejecución remota

Las cuentas con ejecución remota habilitada también pueden ejecutar acciones elegibles de comandos del grafo en los workers de Linux de Tuist. Esto es independiente de compartir resultados en caché y de ejecutar un flujo completo de CI. Consulta <.localized_link href="/guides/features/runners/once">Once remote execution</.localized_link> para conocer los requisitos y la configuración de los workers.
