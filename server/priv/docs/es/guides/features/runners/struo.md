---
{
  "title": "Ejecución remota de Struo",
  "titleTemplate": ":title · Runners · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta acciones de comandos del grafo de Struo elegibles en los trabajadores de ejecución remota de Linux de Tuist."
}
---
# Ejecución remota de Struo {#struo-remote-execution}

<a id="once-remote-execution"></a>

La caché compartida evita repetir trabajo que otra máquina ya ha completado. La ejecución remota también traslada los fallos de caché elegibles fuera de tu equipo: Struo programa acciones de comandos del grafo en workers Linux de un solo uso de Tuist y recupera sus salidas a través de la misma caché del proyecto.

> [!NOTE]
> La ejecución remota está disponible solo por invitación. [Contáctanos](mailto:contact@tuist.dev) para solicitar acceso para tu cuenta.

> [!IMPORTANT]
> **Requisitos**
>
> - Una cuenta de Tuist con la ejecución remota habilitada y capacidad de ejecución disponible.
> - Una versión de Struo con soporte para la ejecución remota de Tuist.
> - Un servidor compatible que anuncie la imagen del worker, el extremo de caché, la concurrencia y un directorio de ejecución absoluto. Los servidores que omiten el directorio no son compatibles con el cliente actual de Struo; Struo se detiene antes de subir el trabajo.
> - Comandos y toolchains que puedan ejecutarse en `linux/amd64` dentro de la imagen del worker anunciada.

Esto ejecuta acciones del grafo, no un trabajo completo de CI. Configurar Struo no instala la orquestación de flujos de trabajo de GitHub ni de GitLab.

## Configuración {#setup}

Completa <.localized_link href="/guides/get-started/struo-project">Primeros pasos con Struo</.localized_link>. Selecciona el mismo proveedor de Tuist para la caché y la ejecución, y fija la imagen del worker anunciada por el servicio:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
execution_image = "sha-REPLACE_WITH_THE_IMAGE_TAG"

[infrastructure.cache]
provider = "tuist"

[infrastructure.execution]
provider = "tuist"
```

Autentícate con credenciales que puedan leer y escribir la caché del proyecto y, a continuación, solicita la ejecución remota:

```bash
struo build --remote MyTarget
```

Sustituye el target y la etiqueta de la imagen por los tuyos. Struo comprueba la imagen anunciada, el directorio de ejecución, el destino de la caché y la capacidad de la cuenta antes de subir el trabajo. La caché y la ejecución deben apuntar al mismo proyecto.

## Preparar acciones para los workers {#prepare-actions-for-workers}

- Declara las entradas y las salidas. Las salidas deben permanecer dentro del directorio de trabajo de la acción.
- Resuelve las herramientas dentro de la imagen del worker, no en rutas absolutas del equipo iniciador.
- Usa acciones seguras para repetirse: un fallo del worker o un reinicio del servicio puede provocar otra ejecución.
- Mantén los tiempos de espera dentro del límite de diez minutos por acción del servicio. Los requisitos no admitidos, incluida la denegación de red, fallan en lugar de ejecutarse localmente de forma silenciosa.

Struo respeta la concurrencia de acciones anunciada por la cuenta y reduce la carga cuando la cola del servicio está llena. Cambiar la imagen separa la configuración de compilación y los resultados almacenados en caché, lo que impide su reutilización entre imágenes de worker incompatibles.

## Inspeccionar la ejecución remota {#inspect-remote-execution}

La barra lateral del proyecto tiene una página de **Ejecución remota**. Su tarjeta de **Análisis** muestra las ejecuciones y el tiempo total de ejecución del periodo seleccionado, como se describe en <.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">Ejecutar acciones y uso</.localized_link>. En las versiones de Struo posteriores a la 2.19.0, cada acción remota indica el run de Struo al que pertenece, por lo que la página también grafica los tiempos de cola y de ejecución y enumera los runs con sus acciones remotas, resultados y cronometrías, mostrando primero los runs en ejecución. Un run abre su página en **Runs de compilación**. Los runs de clientes antiguos y las acciones respondidas desde la caché remota no se cuentan allí. Las acciones remotas que se están ejecutando y encolando ahora mismo están disponibles a través de la herramienta MCP `get_remote_execution_activity` y su extremo REST. Ambos provienen del servicio de ejecución, no de los carriles de workers.

Consulta la [guía de ejecución remota de Struo](https://struo.run/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers) para obtener información sobre el encolamiento, la actualización de la autenticación y las anulaciones del extremo de caché. Sigue las <.localized_link href="/guides/features/build-insights/struo">métricas de compilación de Struo</.localized_link> para inspeccionar los runs resultantes.
