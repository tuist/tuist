---
{
  "title": "Plugins",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende a crear y usar plugins en Tuist para ampliar sus funcionalidades."
}
---
# Plugins {#plugins}

Los plugins son una herramienta para compartir y reutilizar artefactos de Tuist en varios proyectos. Se admiten los siguientes artefactos:

- <.localized_link href="/guides/features/projects/code-sharing">Project description helpers</.localized_link> en varios proyectos.
- <.localized_link href="/guides/features/projects/templates">Plantillas</.localized_link> en varios proyectos.
- Tareas en varios proyectos.
- Plantilla de <.localized_link href="/guides/features/projects/synthesized-files">Resource accessor</.localized_link> en varios proyectos

Ten en cuenta que los plugins están diseñados para ser una forma sencilla de ampliar la funcionalidad de Tuist. Por lo tanto, hay **algunas limitaciones a tener en cuenta**:

- Un plugin no puede depender de otro plugin.
- Un plugin no puede depender de paquetes Swift de terceros.
- Un plugin no puede usar project description helpers del proyecto que utiliza el plugin.

Si necesitas más flexibilidad, considera sugerir una funcionalidad para la herramienta o construir tu propia solución sobre el framework de generación de Tuist, [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator).

## Tipos de plugin {#plugin-types}

### Plugin de project description helper {#project-description-helper-plugin}

Un plugin de project description helper se representa mediante un directorio que contiene un archivo de manifiesto `Plugin.swift` que declara el nombre del plugin y un directorio `ProjectDescriptionHelpers` que contiene los archivos Swift de ayuda.

::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ProjectDescriptionHelpers
└── ...
```
<!-- -->
:::

### Plugin de plantillas de resource accessor {#resource-accessor-templates-plugin}

Si necesitas compartir <.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">sintetizadores de recursos generados automáticamente</.localized_link>, puedes usar este tipo de plugin. El plugin se representa mediante un directorio que contiene un archivo de manifiesto `Plugin.swift` que declara el nombre del plugin y un directorio `ResourceSynthesizers` que contiene los archivos de plantilla de resource accessor.


::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ResourceSynthesizers
├───── Strings.stencil
├───── Plists.stencil
├───── CustomTemplate.stencil
└── ...
```
<!-- -->
:::

El nombre de la plantilla es la versión en [camel case](https://en.wikipedia.org/wiki/Camel_case) del tipo de recurso:

| Tipo de recurso | Nombre del archivo de plantilla |
| ------------- | ------------------ |
| Strings | Strings.stencil |
| Assets | Assets.stencil |
| Property Lists | Plists.stencil |
| Fonts | Fonts.stencil |
| Core Data | CoreData.stencil |
| Interface Builder | InterfaceBuilder.stencil |
| JSON | JSON.stencil |
| YAML | YAML.stencil |

Al definir los sintetizadores de recursos en el proyecto, puedes especificar el nombre del plugin para usar las plantillas del plugin:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Plugin de tareas <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **Obsoleto**
>
> Los plugins de tareas están obsoletos. Consulta [esta publicación del blog](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects) si buscas una solución de automatización para tu proyecto.


Las tareas son ejecutables expuestos en `$PATH` que se pueden invocar mediante el comando `tuist` si siguen la convención de nomenclatura `tuist-<task-name>`. En versiones anteriores, Tuist ofrecía algunas convenciones y herramientas poco estrictas bajo `tuist plugin` para `build`, `run`, `test` y `archive` tareas representadas por ejecutables en paquetes Swift, pero hemos dejado obsoleta esta funcionalidad porque aumenta la carga de mantenimiento y la complejidad de la herramienta.

Si distribuías tareas como plugins, constrúyelas como ejecutables independientes en su lugar:

- Puedes seguir usando el `ProjectAutomation.xcframework` distribuido con cada versión de Tuist para acceder al grafo del proyecto desde tu lógica con `let graph = try Tuist.graph()`. Ejecuta `tuist` como un subproceso y devuelve la representación en memoria del grafo del proyecto.
- Para distribuir tareas, recomendamos publicar un binario universal compatible con `arm64` y `x86_64` en las versiones de GitHub, y usar [Mise](https://mise.jdx.dev) como herramienta de instalación. Para indicar a Mise cómo instalar tu herramienta, necesitarás un repositorio de plugin. Puedes usar el de [Tuist](https://github.com/asdf-community/asdf-tuist) como referencia.
- Si nombras tu herramienta `tuist-{xxx}` y los usuarios pueden instalarla ejecutando `mise install`, podrán ejecutarla invocándola directamente o mediante `tuist xxx`.

> [!NOTE]
> **El futuro de ProjectAutomation**
>
> Planeamos consolidar los modelos de `ProjectAutomation` y `XcodeGraph` en un único framework compatible con versiones anteriores que exponga la totalidad del grafo del proyecto al usuario. Además, extraeremos la lógica de generación en una nueva capa, `XcodeGraph`, que también podrás usar desde tu propia CLI. Piénsalo como construir tu propio Tuist.


## Uso de plugins {#using-plugins}

Para usar un plugin, tendrás que añadirlo al archivo de manifiesto [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) de tu proyecto:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

Si quieres reutilizar un plugin en proyectos que residen en distintos repositorios, puedes subir tu plugin a un repositorio Git y hacer referencia a él en el archivo `Tuist.swift`:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

Después de añadir los plugins, `tuist install` los obtendrá en un directorio de caché global.

> [!NOTE]
> **Sin resolución de versiones**
>
> Como habrás observado, no ofrecemos resolución de versiones para plugins. Recomendamos usar etiquetas de Git o SHAs para garantizar la reproducibilidad.


> [!TIP]
> **Plugins de project description helpers**
>
> Al usar un plugin de project description helpers, el nombre del módulo que contiene los helpers es el nombre del plugin
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
