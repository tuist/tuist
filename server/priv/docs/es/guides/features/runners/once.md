---
{
  "title": "Ejecución remota de Once",
  "titleTemplate": ":title · Runners · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta acciones de comandos del grafo de Once elegibles en los trabajadores de ejecución remota de Linux de Tuist."
}
---
# Ejecución remota de Once {#once-remote-execution}

La caché compartida evita repetir trabajo que otra máquina ya ha completado. La ejecución remota también traslada los fallos de caché elegibles fuera de tu equipo: Once programa las acciones de comandos del grafo en workers Linux de un solo uso de Tuist y recupera sus resultados a través de la misma caché del proyecto.

> [!IMPORTANT]
> **Requisitos**
>
> - Una cuenta de Tuist con la ejecución remota habilitada y capacidad de ejecución disponible.
> - Una versión de Once con soporte para la ejecución remota de Tuist.
> - Un servidor compatible que anuncie la imagen del worker, el endpoint de la caché, la concurrencia y un directorio de ejecución absoluto. Los servidores que omiten el directorio no son compatibles con el cliente actual de Once; Once se detiene antes de subir el trabajo.
> - Comandos y toolchains que puedan ejecutarse en `linux/amd64` dentro de la imagen del worker anunciada.

Esto ejecuta acciones del grafo, no un trabajo completo de CI. Configurar Once no instala la orquestación de flujos de trabajo de GitHub ni de GitLab.

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
- Resuelve las herramientas dentro de la imagen del worker, no en rutas absolutas del equipo iniciador.
- Usa acciones que sean seguras para repetir: un fallo del worker o un reinicio del servicio puede provocar otra ejecución.
- Mantén los tiempos de espera dentro del límite de diez minutos por acción del servicio. Los requisitos no compatibles, incluida la denegación de red, fallan en lugar de ejecutarse localmente de forma silenciosa.

Once respeta la concurrencia de acciones anunciada por la cuenta y reduce la carga cuando la cola del servicio está llena. Cambiar la imagen separa la configuración de compilación y los resultados almacenados en caché, evitando su reutilización entre imágenes de worker incompatibles.

Consulta la [guía de ejecución remota de Once](https://buildonce.dev/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers) para obtener información sobre la puesta en cola, la actualización de la autenticación y las anulaciones del endpoint de la caché. Sigue las <.localized_link href="/guides/features/build-insights/once">métricas de compilación de Once</.localized_link> para inspeccionar las ejecuciones resultantes.
