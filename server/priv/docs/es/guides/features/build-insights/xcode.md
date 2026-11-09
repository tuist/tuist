---
{
  "title": "Análisis de compilaciones de Xcode",
  "titleTemplate": ":title · Análisis de compilaciones · Funcionalidades · Guías · Tuist",
  "description": "Realiza un seguimiento de las métricas de compilación de Xcode en el panel de Tuist para monitorizar el rendimiento de las compilaciones locales y de CI."
}
---
# Análisis de compilaciones de Xcode {#xcode-build-insights}

Trabajar en proyectos grandes no debería obligarte a recompilar el mismo código una y otra vez. Tuist Build Insights te permite hacer seguimiento de las analíticas de compilación para que identifiques tendencias antes de que los tiempos de compilación local y de CI se conviertan en cuellos de botella.

Los análisis de compilaciones se generan con el comando `tuist inspect build`, que normalmente se añade a la acción posterior del esquema.

Para empezar a hacer seguimiento de los tiempos de compilación local, puedes aprovechar el comando `tuist inspect build` añadiéndolo a la acción posterior del esquema:

![Acción posterior para inspeccionar compilaciones](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> Establece el campo "Provide build settings from" en el ejecutable o en tu objetivo de compilación principal para capturar la configuración de compilación.

> [!NOTE]
> La acción posterior del esquema no se ejecuta cuando la compilación falla.
>
> Puedes ejecutarla en ese caso estableciendo `runPostActionsOnFailure` en `YES` en el elemento `<BuildAction>` del archivo `.xcscheme` del esquema:
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

Para [Mise](https://mise.jdx.dev/), activa `tuist` en el entorno de la acción posterior:

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Resolución de rutas de Mise**
>
> El `PATH` de tu entorno no se hereda en la acción posterior del esquema, así que usa la ruta absoluta de Mise. Esto depende de cómo hayas instalado Mise. La configuración de compilación debería heredarse desde un objetivo para que `mise` pueda ejecutarse desde `$SRCROOT`.

Para [Homebrew](https://brew.sh/), añade las rutas de Homebrew al entorno de la acción posterior:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

Una vez iniciada la sesión, las compilaciones locales se rastrean y están disponibles desde el panel de control de Tuist:

> [!TIP]
> Para acceder rápidamente al panel de control, ejecuta `tuist project show --web` desde la CLI.

![Panel de control con análisis de compilaciones](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
