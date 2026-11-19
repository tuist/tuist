---
{
  "title": "Proyecto Struo",
  "titleTemplate": ":title · Primeros pasos · Guías · Tuist",
  "description": "Conecta Struo a Tuist para compartir caché, obtener análisis en tiempo real de compilaciones y tests, distribuir tests y previsualizar aplicaciones."
}
---
# Proyecto Struo {#struo-project}

<a id="once-project"></a>

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/struo-project
```

:::

[Struo](https://struo.run) ejecuta scripts y grafos de compilación cacheables. Conéctalo a Tuist para compartir trabajo en caché entre máquinas, seguir las ejecuciones en directo y publicar aplicaciones para que tu equipo las pruebe. Mantén las fuentes de tu proyecto y las definiciones de compilación; la integración se configura en `struo.toml`.

## Requisitos previos

- [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) o posterior instalado, junto con un workspace o un script cacheable. Sigue la [guía de instalación](https://struo.run/docs/guide/getting-started) o fíjalo con mise:

  ```bash
  mise use -g github:tuist/struo@1.0.0
  ```

- Una cuenta de Tuist. La CLI de Tuist no es necesaria para la integración con Struo.

## Actualización desde Once {#upgrading-from-once}

Struo es el nuevo nombre de Once. Cambia el nombre de los archivos `once.toml` a `struo.toml`, actualiza las referencias de mise de `github:tuist/once` a `github:tuist/struo` y sustituye los comandos `once` por `struo`. Actualiza las cabeceras de los scripts de `# once` a `# struo` y los shebangs a `#!/usr/bin/env -S struo exec -- bash`. Renombra las variables de entorno `ONCE_*` a `STRUO_*`, como `STRUO_CACHE_PROVIDER`; las credenciales de Tuist siguen usando `TUIST_TOKEN`.

Cambia las entradas `.once/` en los archivos de ignorados por `.struo/`. Las salidas ahora se guardan en `.struo/out/` y la caché local compartida de contenido usa `$XDG_CACHE_HOME/struo/cas` (por defecto `~/.cache/struo/cas`). Las claves de caché y el almacenamiento local usan el nuevo nombre, así que espera una caché local fría tras la actualización en lugar de migrar las entradas antiguas. Vuelve a iniciar sesión con `struo auth login --provider tuist`.

El cambio de nombre no afecta a los endpoints de compatibilidad de Tuist: los informes en tiempo real siguen usando `once.events.v1` y las rutas existentes `/api/.../once` continúan siendo compatibles. Consulta la [guía de cambio de nombre upstream](https://struo.run/changelog/2026-11-18-once-is-now-struo).

## Conectar el proyecto {#connect-the-project}

Desde la raíz de tu repositorio, ejecuta:

```bash
struo connect --provider tuist --create
```

Struo inicia sesión cuando es necesario, crea un proyecto de Tuist en tu cuenta personal y escribe la vinculación del proveedor en `struo.toml`. Consulta [Conectar un proyecto](https://struo.run/docs/guide/infrastructure/connect) para elegir otra cuenta o un proyecto existente.

Para un proyecto de Tuist ya existente, configura tú mismo el proveedor y la vinculación de caché:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

Sustituye `acme` y `app` por los identificadores de tu cuenta y proyecto, luego autentícate:

```bash
struo auth login --provider tuist
```

Confirma `struo.toml` para que tus compañeros y la CI compartan el destino, no tus credenciales. Cada desarrollador inicia sesión en su propia máquina.

## Caché compartida

Una caché local solo beneficia a la máquina que la pobló. Con Tuist configurado, Struo puede restaurar resultados coincidentes generados por otro desarrollador o por la CI en lugar de volver a ejecutar el mismo trabajo.

Ejecuta tu script cacheable o un objetivo del grafo como de costumbre:

```bash
struo build MyApplication
```

Abre **Struo Cache** en el panel para inspeccionar la actividad de la caché remota. Consulta <.localized_link href="/guides/features/cache/struo">Caché de Struo</.localized_link> para ver la configuración y comprobar la reutilización entre máquinas.

## Análisis de compilaciones

Struo imprime un enlace al panel cuando comienza una ejecución. Ábrelo para seguir el grafo, el estado de las acciones y las decisiones de caché mientras avanza la ejecución. Usa **Compilaciones** para comparar el rendimiento local y de la CI e investigar acciones fallidas. Conserva los registros de la CI para obtener la salida completa del proceso; la ingesta de registros crudos de acciones no está disponible actualmente.

Consulta <.localized_link href="/guides/features/build-insights/struo">Análisis de compilaciones de Struo</.localized_link> para saber qué se registra y cómo acceder desde agentes de programación o Grafana.

## Análisis de tests y sharding

Ejecuta tus objetivos de test de Struo:

```bash
struo test
```

Abre **Tests** para inspeccionar suites, casos, duraciones y fallos reportados. Los resultados dependen de las capacidades de reporting del objetivo de test; una acción que ejecuta un proceso de test no genera automáticamente un informe por caso.

Cuando la suite supera la capacidad de una sola máquina, crea un plan de sharding alojado y distribuye sus lotes entre los workers de la CI. Consulta <.localized_link href="/guides/features/test-insights/struo">Análisis de tests de Struo</.localized_link> y <.localized_link href="/guides/features/test-sharding/struo">Sharding de tests de Struo</.localized_link>.

## Previews y tamaño del paquete

Añade una vinculación de artefactos al mismo proveedor para publicar aplicaciones compatibles de Android, simulador de Apple y macOS:

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
struo artifact publish MyApplication --track review
```

El enlace devuelto abre las previews de tu proyecto; el procesamiento puede tardar un momento. Consulta <.localized_link href="/guides/features/previews/struo">Previews de Struo</.localized_link> para conocer los requisitos de firma y la publicación opcional tras las compilaciones.

Para hacer seguimiento del tamaño del paquete, usa la CLI de Tuist por separado sobre un `.app`, `.ipa`, `.xcarchive`, `.apk` o `.aab` compilado. Sigue la <.localized_link href="/guides/features/bundle-insights">guía de análisis de paquetes para Apple o Android</.localized_link>; publicar un artefacto de Struo no sube automáticamente un informe de tamaño del paquete.

## Integración continua

Usa un token de cuenta autorizado para las operaciones del proyecto en `TUIST_TOKEN` o autentícate mediante la identidad OpenID Connect de un proveedor de CI compatible:

```bash
struo auth login --provider tuist --no-browser
struo build MyApplication
struo test
```

En GitHub Actions, concede al job `id-token: write` y `contents: read`. Consulta <.localized_link href="/guides/integrations/continuous-integration#struo">Struo en integración continua</.localized_link> para ver un ejemplo. El inicio de sesión personal de un desarrollador no es una credencial de CI.

## Ejecución remota

Las cuentas con ejecución remota habilitada también pueden ejecutar acciones de comandos del grafo elegibles en los workers Linux de Tuist. Esto es independiente de compartir resultados en caché y de ejecutar un flujo completo de CI. Consulta <.localized_link href="/guides/features/runners/struo">Ejecución remota de Struo</.localized_link> para conocer los requisitos y la configuración de los workers.
