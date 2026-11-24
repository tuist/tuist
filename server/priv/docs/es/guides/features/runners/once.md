---
{
  "title": "Ejecución remota de Once",
  "titleTemplate": ":title · Runners · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta acciones de comandos del grafo de Once elegibles en los trabajadores de ejecución remota de Linux de Tuist."
}
---
# Ejecución remota de Once {#once-remote-execution}

La caché compartida evita repetir trabajo que otra máquina ya ha completado. La ejecución remota también traslada fuera de tu ordenador los fallos de caché elegibles: Once programa las acciones de comandos del grafo en workers Linux de un solo uso de Tuist y recupera sus resultados a través de la misma caché del proyecto.

> [!NOTE]
> La ejecución remota está disponible actualmente solo por invitación. [Contacta con nosotros](mailto:contact@tuist.dev) para solicitar acceso para tu cuenta.

> [!IMPORTANT]
> **Requisitos**
>
> - Una cuenta de Tuist con la ejecución remota habilitada y capacidad de ejecución disponible.
> - Una versión de Once con soporte para la ejecución remota de Tuist.
> - Un servidor compatible que anuncie la imagen del worker, el extremo de caché, la concurrencia y un directorio de ejecución absoluto. Los servidores que omiten el directorio no son compatibles con el cliente actual de Once; Once se detiene antes de subir el trabajo.
> - Comandos y toolchains que puedan ejecutarse en `linux/amd64` dentro de la imagen del worker anunciada.

Esto ejecuta acciones del grafo, no un trabajo completo de CI. Configurar Once no instala la orquestación de flujos de trabajo de GitHub o GitLab.

## Configuración {#setup}

Completa <.localized_link href="/guides/get-started/once-project">Primeros pasos con Once</.localized_link>. Selecciona el mismo proveedor de Tuist para la caché y la ejecución, y fija la imagen del worker anunciada por el servicio:

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

Autentícate con credenciales que puedan leer y escribir en la caché del proyecto y, a continuación, solicita la ejecución remota:

```bash
once build --remote MyTarget
```

Sustituye el target y la etiqueta de la imagen por los tuyos. Once comprueba la imagen anunciada, el directorio de ejecución, el destino de la caché y la capacidad de la cuenta antes de subir el trabajo. La caché y la ejecución deben apuntar al mismo proyecto.

## Preparar acciones para los workers {#prepare-actions-for-workers}

- Declara las entradas y las salidas. Las salidas deben permanecer dentro del directorio de trabajo de la acción.
- Resuelve las herramientas dentro de la imagen del worker, no en rutas absolutas del ordenador iniciador.
- Utiliza acciones que sean seguras de repetir: un fallo del worker o un reinicio del servicio pueden provocar otra ejecución.
- Mantén los tiempos de espera dentro del límite de diez minutos por acción del servicio. Los requisitos no admitidos, incluida la denegación de red, fallan en lugar de ejecutarse localmente de forma silenciosa.

Once respeta la concurrencia de acciones anunciada por la cuenta y reduce la carga cuando la cola del servicio está llena. Cambiar la imagen separa la configuración de compilación y los resultados almacenados en caché, lo que impide la reutilización entre imágenes de worker incompatibles.

## Inspeccionar la ejecución remota {#inspect-remote-execution}

La barra lateral del proyecto tiene una página de **Ejecución remota**. Su tarjeta de **Análisis** muestra las ejecuciones y el tiempo total de ejecución del periodo seleccionado, como se describe en <.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">Ejecutar acciones y uso</.localized_link>. La telemetría de ejecuciones de Once aún no distingue la ejecución remota de las acciones locales, por lo que la página no ofrece tiempos remotos por ejecución ni ejecuciones en curso. Explica esta carencia y enlaza a **Ejecuciones de compilación** para ver los detalles de las acciones registradas. Las acciones remotas que se están ejecutando y las que están en cola ahora mismo están disponibles a través de la herramienta MCP `get_remote_execution_activity` y su extremo REST. Ambas proceden del servicio de ejecución, no de los carriles de workers.

Consulta la [guía de ejecución remota de Once](https://buildonce.dev/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers) para obtener información sobre la puesta en cola, la actualización de la autenticación y las anulaciones del extremo de caché. Sigue las <.localized_link href="/guides/features/build-insights/once">métricas de compilación de Once</.localized_link> para inspeccionar las ejecuciones resultantes.
