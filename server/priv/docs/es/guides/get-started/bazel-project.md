---
{
  "title": "Proyecto Bazel",
  "titleTemplate": ":title · Primeros pasos · Guías · Tuist",
  "description": "Conecta un espacio de trabajo de Bazel a Tuist para obtener una caché remota compartida y análisis de compilación y tests en CI, sin modificar ningún archivo BUILD."
}
---
# Proyecto de Bazel {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

Sigue esta guía para integrar un espacio de trabajo de Bazel existente en Tuist. Tuist expone una caché basada en la [API de ejecución remota](https://github.com/bazelbuild/remote-apis) a la que Bazel se conecta como caché remota, y un flujo del servicio de eventos de compilación que convierte cada compilación y test en datos visibles en el panel.

Cada sección a continuación comienza explicando qué falta hoy y luego te guía por la funcionalidad que cubre esa carencia.

## Requisitos previos

- Un espacio de trabajo de Bazel (con un `WORKSPACE` o `MODULE.bazel` en su raíz) y Bazel disponible en tu `PATH`.
- La <.localized_link href="/guides/install-tuist">interfaz de línea de comandos de Tuist</.localized_link>.

## Conectar el espacio de trabajo

Desde la raíz del espacio de trabajo de Bazel, ejecuta `tuist init`. Tuist detecta el `WORKSPACE` / `MODULE.bazel` y ofrece **Integrar un espacio de trabajo de Bazel**. Autentícate en el navegador y selecciona la cuenta que debe ser propietaria del proyecto.

```bash
tuist init
```

Si lo haces desde un agente de programación o un script, ejecuta primero `tuist auth login` (el flujo del navegador espera a que pulses Intro) y luego usa la forma no interactiva:

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

Cuando finaliza init, Tuist:

1. Escribe un `tuist.toml` en la raíz del espacio de trabajo con el identificador del proyecto.
2. Escribe un `.bazelrc.tuist` junto a tu `.bazelrc`, configurado para la región de caché de Tuist más cercana y autenticado mediante un asistente de credenciales por espacio de trabajo.
3. Añade una línea `try-import %workspace%/.bazelrc.tuist` a tu `.bazelrc`.

Confirma la línea `try-import`. Es idéntica en todas las máquinas. Añade `.bazelrc.tuist` a tu `.gitignore`. La ruta del asistente de credenciales es por usuario y la región de caché es por ubicación, por lo que no deben compartirse.

Todo lo siguiente se activa automáticamente una vez conectado el espacio de trabajo.

## Caché remota

La caché local en disco propia de Bazel reside en `~/.cache/bazel` (o donde apunte `--disk_cache`). Un acierto en la máquina de un desarrollador no llega a los demás, y los contenedores de trabajos de CI comienzan cada ejecución con una caché vacía.

La [API de ejecución remota](https://github.com/bazelbuild/remote-apis) de Bazel es el protocolo para extender esa misma caché a un extremo compartido. Tuist la soporta. Una vez que `.bazelrc.tuist` está configurado, Bazel omite acciones cuyas salidas ya están en la caché compartida y las descarga en su lugar. El trabajo de una máquina beneficia a todas las demás que compilan la misma revisión.

Verifícalo con dos compilaciones limpias contra la misma revisión (localmente, o una local + una de CI):

```bash
bazel clean
bazel build //...
```

El resumen de la segunda ejecución debería informar de aciertos de caché. Abre **Caché** en el panel para ver las tasas de acierto a lo largo del tiempo.

## Análisis de compilaciones y tests

El flujo de eventos de compilación de Bazel y los informes XML por test se emiten por invocación. Comparar duraciones a nivel de objetivo a lo largo de una semana, o detectar un test que se ha vuelto inestable en varias ejecuciones de CI, implica recoger y agregar esos eventos en algún lugar.

El protocolo Build Event Service que Bazel ya emite está diseñado precisamente para eso. El `.bazelrc.tuist` que escribió `tuist init` configura el flujo BES hacia Tuist, así que los análisis de compilaciones y tests comienzan a fluir en la siguiente `bazel build` y `bazel test`. No hay nada más que configurar. Abre **Compilaciones** y **Tests** en el panel para ver los datos.

## Involucra al equipo

Los aciertos de caché y los análisis se potencian con el número de personas conectadas al proyecto. Invita a tus compañeros a la organización desde la configuración de la cuenta en el panel y configura <.localized_link href="/guides/integrations/authentication/sso">Inicio de sesión único</.localized_link> (Google, Okta, Microsoft) para que la incorporación sea un clic en lugar de un `tuist auth login` por persona.
