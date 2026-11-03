---
{
  "title": "Mejores prácticas",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Conoce las mejores prácticas para trabajar con proyectos generados por Tuist."
}
---
# Mejores prácticas {#best-practices}

A lo largo de los años trabajando con diferentes equipos y proyectos, hemos identificado un conjunto de mejores prácticas que recomendamos seguir al trabajar con Tuist y proyectos de Xcode. Estas prácticas no son obligatorias, pero pueden ayudarte a estructurar tus proyectos de una manera que facilite su mantenimiento y escalabilidad.

## Xcode {#xcode}

### Patrones desaconsejados {#discouraged-patterns}

#### Configuraciones para modelar entornos remotos {#configurations-to-model-remote-environments}

Muchas organizaciones utilizan configuraciones de compilación para modelar diferentes entornos remotos (por ejemplo, `Debug-Production` o `Release-Canary`), pero este enfoque tiene algunas desventajas:

- **Inconsistencias:** Si hay inconsistencias de configuración en todo el grafo, el sistema de compilación podría terminar usando la configuración incorrecta para algunos targets.
- **Complejidad:** Los proyectos pueden terminar con una larga lista de configuraciones locales y entornos remotos difíciles de comprender y mantener.

Las configuraciones de compilación se diseñaron para reflejar diferentes ajustes de compilación, y los proyectos rara vez necesitan más que solo `Debug` y `Release`. La necesidad de modelar diferentes entornos se puede lograr de otra manera:

- **En compilaciones Debug:** Puedes incluir todas las configuraciones que deberían ser accesibles durante el desarrollo en la app (por ejemplo, endpoints) y cambiarlas en tiempo de ejecución. El cambio puede realizarse mediante variables de entorno de lanzamiento del scheme o con una interfaz dentro de la app.
- **En compilaciones Release:** En caso de una release, puedes incluir únicamente la configuración a la que está vinculada la compilación de release y no incluir la lógica en tiempo de ejecución para cambiar configuraciones mediante directivas del compilador.

> [!NOTE]
> **Configuraciones no estándar**
>
> Aunque Tuist admite configuraciones no estándar y facilita su gestión en comparación con los proyectos vanilla de Xcode, recibirás advertencias si las configuraciones no son consistentes en todo el grafo de dependencias. Esto ayuda a garantizar la fiabilidad de la compilación y evita problemas relacionados con la configuración.


## Proyectos generados

### Carpetas compilables

Tuist 4.62.0 añadió soporte para **carpetas compilables** (grupos sincronizados de Xcode), una característica introducida en Xcode 16 para reducir conflictos de fusión.

Aunque los patrones comodín de Tuist (por ejemplo, `Sources/**/*.swift`) ya eliminan los conflictos de fusión en proyectos generados, las carpetas compilables ofrecen beneficios adicionales:

- **Sincronización automática**: La estructura de tu proyecto se mantiene sincronizada con el sistema de archivos; no es necesario regenerar al añadir o eliminar archivos
- **Flujos de trabajo compatibles con IA**: Los asistentes y agentes de programación pueden modificar tu base de código sin desencadenar la regeneración del proyecto
- **Configuración más sencilla**: Define rutas de carpeta en lugar de gestionar listas explícitas de archivos

Recomendamos adoptar carpetas compilables en lugar de los atributos tradicionales `Target.sources` y `Target.resources` para una experiencia de desarrollo más ágil.

::: code-group

```swift [With buildable folders]
let target = Target(
  name: "App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target = Target(
  name: "App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
<!-- -->
:::

### Dependencias

#### Forzar versiones resueltas en CI

Al instalar dependencias de Swift Package Manager en CI, recomendamos usar la bandera `--force-resolved-versions` para garantizar compilaciones deterministas:

```bash
tuist install --force-resolved-versions
```

Esta bandera garantiza que las dependencias se resuelvan utilizando las versiones exactas fijadas en `Package.resolved`, eliminando problemas causados por la no determinismo en la resolución de dependencias. Esto es especialmente importante en CI, donde las compilaciones reproducibles son críticas.

#### Instalación de dependencias en caché en GitHub Actions {#dependency-cache-volumes}

Para proyectos generados, usa [tuist/install](https://github.com/tuist/install) para instalar las dependencias fijadas en `Package.resolved` y almacenarlas en caché entre ejecuciones. Utiliza automáticamente <.localized_link href="/guides/features/runners/cache-volumes">volúmenes de caché</.localized_link> en Tuist Runners y la caché de GitHub en otros runners.

```yaml
name: Generate project
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  generate:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v4
      - uses: tuist/install@v1
      - run: tuist generate --no-open
```

Para un proyecto en un subdirectorio, pasa su ruta relativa al checkout:

```yaml
- uses: tuist/install@v1
  with:
    path: apps/ios
```

Consulta la [referencia de la acción](https://github.com/tuist/install#usage) para ver opciones adicionales.

### Programación con agentes y worktrees {#agentic-coding-and-worktrees}

Los agentes de programación y los colaboradores humanos trabajan cada vez más en paralelo: un desarrollador mantiene abierto un worktree para la funcionalidad que está revisando mientras uno o más agentes iteran en sus propias ramas en worktrees hermanos. Algunas decisiones de proyecto facilitan mucho este proceso.

#### Usa carpetas compilables para ediciones impulsadas por agentes {#worktrees-buildable-folders}

Cuando un agente añade o elimina archivos, cualquier cosa que dependa de una lista de archivos en `Project.swift` requiere `tuist generate` antes de que el proyecto vuelva a compilarse. Las [carpetas compilables](#buildable-folders) transfieren esa responsabilidad a los grupos sincronizados de Xcode, por lo que las ediciones en el árbol de archivos ya no desencadenan una regeneración.

Combina esto con la `generated-projects` <.localized_link href="/guides/features/agentic-coding/skills">habilidad</.localized_link>, que enseña a los agentes el flujo de trabajo diario de un proyecto Tuist.

#### No aísles la caché por worktree {#worktrees-shared-cache}

Tuist sigue la <.localized_link href="/cli/directories">especificación de directorios base XDG</.localized_link>, por lo que, de forma predeterminada, todos los worktrees en la misma máquina comparten `~/.cache/tuist` y `~/.local/state/tuist`. Esto es lo que deseas: los helpers compilados en un worktree, los plugins descargados en otro y los binarios del caché de módulos obtenidos por un tercero son todos reutilizables.

Las invocaciones concurrentes de `tuist` entre worktrees son seguras para ejecutar en paralelo. Evita apuntar `TUIST_XDG_CACHE_HOME` a una ruta local del worktree a menos que necesites específicamente aislamiento; hacerlo obliga a cada worktree a recalentar helpers, plugins y binarios.

#### Mantén el directorio temporal de SwiftPM por worktree {#worktrees-swiftpm-scratch}

Swift Package Manager tiene sus propios controles de ruta. `--scratch-path` es un estado de trabajo mutable y por defecto es `.build`, mientras que `--cache-path` es el directorio de caché compartido. Esas dos rutas no deben tratarse igual cuando hay varios worktrees activos.

El comportamiento predeterminado de `tuist install` ya mantiene el directorio temporal de SwiftPM bajo el directorio del paquete, por lo que cada worktree obtiene su propio `.build`. Mantén ese aislamiento. Un único directorio temporal compartido de SwiftPM puede mezclar checkouts, intermedios de compilación, plugins, macros y archivos de bloqueo de ramas no relacionadas.

Si pasas argumentos de SwiftPM a través de `tuist install -- ...` o mediante `installOptions` en `Tuist.swift`, comparte `--cache-path` cuando quieras obtener dependencias más rápido, pero deja `--scratch-path` sin establecer o apúntalo a un directorio local del worktree:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        installOptions: .options(
            passthroughSwiftPackageManagerArguments: [
                "--cache-path",
                "/Users/Shared/swiftpm/cache/xcode-16-macos",
            ]
        )
    )
)
```

Usa una variable de entorno de contenedor o de CI para la ruta de la caché si necesita variar según Xcode, la toolchain de Swift o la plataforma. Evita confirmar un `--scratch-path` compartido en el repositorio.

Si el estado de las dependencias parece corrupto solo en un worktree, elimina el directorio `.build` de ese worktree y ejecuta `tuist install` de nuevo. Si la caché compartida de SwiftPM parece sospechosa entre worktrees, usa `swift package purge-cache` antes de volver a instalar las dependencias.

#### Apóyate en la caché de módulos {#worktrees-module-cache}

El <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> es lo que hace viables los worktrees paralelos. Dado que Tuist calcula un <.localized_link href="/guides/features/projects/hashing">hash</.localized_link> determinista para cada objetivo, dos worktrees que apuntan a ramas que comparten la mayor parte de su historial utilizarán los mismos binarios. Ejecuta `tuist cache` en cada commit a `main` desde CI; localmente, `tuist generate` en cada worktree obtiene todo lo posible desde la caché y solo compila lo que tu rama ha cambiado realmente.

Si un worktree recurre a compilaciones desde el código fuente cuando esperabas un acierto de caché, sigue los <.localized_link href="/guides/features/projects/hashing#debugging">pasos de depuración del hashing</.localized_link>; los hashes no deterministas (causados normalmente por rutas absolutas en el proyecto) son la causa más común y se manifiestan claramente al comparar dos worktrees.

#### Acelera la resolución de paquetes Swift con el registro {#worktrees-registry}

Cada worktree resuelve los paquetes Swift de forma independiente. En un proyecto con un grafo de dependencias grande, esto suma rápidamente. Cambiar al <.localized_link href="/guides/features/package-registries/swift">Registro de Tuist</.localized_link> evita volver a clonar los historiales de git y reduce la resolución de minutos a segundos.

#### Da a los agentes acceso a las métricas del proyecto {#worktrees-mcp}

Una vez que las compilaciones y los tests se ejecutan en muchos worktrees, lo más útil que puede hacer un agente es razonar sobre *cuáles* de esas ejecuciones han regresado, qué tests son inestables o cómo ha cambiado el tamaño del bundle. Tuist expone esos datos a través del <.localized_link href="/guides/features/agentic-coding/mcp">servidor MCP</.localized_link> y del paquete <.localized_link href="/guides/features/agentic-coding/skills">Skills</.localized_link>. Elige uno por flujo de trabajo y mantente con él; mezclar ambos para la misma tarea suele producir un comportamiento inconsistente en los agentes.
