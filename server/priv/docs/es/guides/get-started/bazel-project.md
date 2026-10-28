---
{
  "title": "Bazel project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect a Bazel workspace to Tuist for a shared remote cache and build and test insights across CI, without changing any BUILD file."
}
---
# Proyecto Bazel {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

Sigue esta ruta para integrar un espacio de trabajo de Bazel existente en Tuist. Tuist expone una caché de la [API de ejecución remota](https://github.com/bazelbuild/remote-apis) a la que Bazel se conecta como caché remota, y un flujo del servicio de eventos de compilación que convierte cada compilación y test en datos visibles en el panel.

Cada sección a continuación comienza con lo que falta hoy y luego te guía a través de la funcionalidad que cubre esa carencia.

## Requisitos previos

- Un espacio de trabajo de Bazel (un `WORKSPACE` o `MODULE.bazel` en su raíz) y Bazel en tu `PATH`.
- La <.localized_link href="/guides/install-tuist">interfaz de línea de comandos de Tuist</.localized_link>.

## Conectar el espacio de trabajo

> [!NOTE]
> El flujo de trabajo de Bazel dentro de `tuist init` requiere una versión de la CLI de Tuist que viene con ella. En versiones anteriores, `tuist init` no mostrará "Integrate a Bazel workspace" como opción. Como alternativa, ejecuta `tuist auth login` seguido de `tuist bazel setup` desde la raíz del espacio de trabajo, lo cual te guiará por los mismos pasos que se indican a continuación.

Desde la raíz del espacio de trabajo de Bazel, ejecuta `tuist init`. Tuist detecta el `WORKSPACE` / `MODULE.bazel` y ofrece **Integrar un espacio de trabajo de Bazel**. Autentícate en el navegador y selecciona la cuenta que debe ser propietaria del proyecto.

```bash
tuist init
```

Si estás ejecutando esto desde un agente de codificación o un script, ejecuta primero `tuist auth login` (el flujo del navegador espera a que presiones Enter), luego usa la forma no interactiva:

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

Cuando finaliza init, Tuist:

1. Escribe un `tuist.toml` en la raíz del espacio de trabajo con el identificador del proyecto.
2. Escribe un `.bazelrc.tuist` junto a tu `.bazelrc`, conectado a la región de caché de Tuist más cercana y autenticado mediante un ayudante de credenciales por espacio de trabajo.
3. Añade una línea `try-import %workspace%/.bazelrc.tuist` a tu `.bazelrc`.

Confirma la línea `try-import`. Es idéntica en cada máquina. Añade `.bazelrc.tuist` a tu `.gitignore`. La ruta del ayudante de credenciales es por usuario y la región de caché es por ubicación, por lo que no debe compartirse.

Todo lo siguiente se activa automáticamente una vez que el espacio de trabajo está conectado.

## Caché remota

La caché de disco local propia de Bazel reside en `~/.cache/bazel` (o dondequiera que apunte `--disk_cache`). Un acierto en la máquina de un desarrollador no llega a nadie más, y los contenedores de trabajos de CI comienzan con una caché vacía en cada ejecución.

La [API de ejecución remota](https://github.com/bazelbuild/remote-apis) de Bazel es el protocolo para extender esa misma caché a un punto final compartido. Tuist lo admite. Una vez que `.bazelrc.tuist` está configurado, Bazel omite las acciones cuyos resultados ya están en la caché compartida y los descarga en su lugar. El trabajo de una máquina beneficia a todas las demás que compilan la misma revisión.

Verifica con dos compilaciones limpias contra la misma revisión (localmente, o una local + una de CI):

```bash
bazel clean
bazel build //...
```

El resumen de la segunda ejecución debería reportar aciertos de caché. Abre **Caché** en el panel para ver las tasas de acierto a lo largo del tiempo.

## Información de compilaciones y tests

El flujo de eventos de compilación de Bazel y los informes XML por test se emiten por invocación. Comparar duraciones a nivel de objetivo durante una semana, o detectar un test que se ha vuelto inestable en varias ejecuciones de CI, implica recopilar y agregar esos eventos en algún lugar.

El protocolo del servicio de eventos de compilación que Bazel ya emite está diseñado exactamente para eso. El `.bazelrc.tuist` que escribió `tuist init` configura el flujo BES hacia Tuist, por lo que la información de compilaciones y tests comienza a fluir en la siguiente `bazel build` y `bazel test`. No hay nada extra que configurar. Abre **Compilaciones** y **Tests** en el panel para ver los datos.

## Involucra al equipo

Los aciertos de caché y la información se multiplican con el número de personas conectadas al proyecto. Invita a tus compañeros a la organización desde la configuración de cuenta en el panel, y configura <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) para que la incorporación sea un clic en lugar de un `tuist auth login` por persona.
