---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# Plugins {#plugins}

Los plugins son una herramienta para compartir y reutilizar artefactos Tuist en
varios proyectos. Los siguientes artefactos son compatibles:

- <LocalizedLink href="/guides/features/projects/code-sharing">Ayudantes de descripción de proyectos</LocalizedLink> en varios proyectos.
- <LocalizedLink href="/guides/features/projects/templates">Plantillas</LocalizedLink>
  en varios proyectos.
- Tareas en varios proyectos.
- <LocalizedLink href="/guides/features/projects/synthesized-files">Plantilla de acceso a recursos</LocalizedLink> en varios proyectos

Ten en cuenta que los plugins están diseñados para ser una forma sencilla de
ampliar la funcionalidad de Tuist. Por lo tanto, hay **algunas limitaciones a
tener en cuenta**:

- Un plugin no puede depender de otro plugin.
- Un plugin no puede depender de paquetes Swift de terceros
- Un plugin no puede utilizar ayudantes de descripción de proyecto del proyecto
  que utiliza el plugin.

Si necesitas más flexibilidad, plantéate sugerir una función para la herramienta
o construir tu propia solución a partir del marco de generación de Tuist,
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## Tipos de plugins {#plugin-types}

### Plugin de ayuda para la descripción de proyectos {#project-description-helper-plugin}

Un plugin de ayuda para la descripción de proyectos está representado por un
directorio que contiene un archivo de manifiesto `Plugin.swift` que declara el
nombre del plugin y un directorio `ProjectDescriptionHelpers` que contiene los
archivos Swift de ayuda.

::: grupo de códigos
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

### Plugin de plantillas de acceso a recursos {#resource-accessor-templates-plugin}

Si necesita compartir
<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">accesores de recursos sintetizados</LocalizedLink> puede utilizar este tipo de plugin. El
plugin está representado por un directorio que contiene un archivo de manifiesto
`Plugin.swift` que declara el nombre del plugin y un directorio
`ResourceSynthesizers` que contiene los archivos de plantilla de accesores de
recursos.


::: grupo de códigos
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

El nombre de la plantilla es la versión [camel
case](https://en.wikipedia.org/wiki/Camel_case) del tipo de recurso:

| Tipo de recurso       | Nombre del archivo de plantilla |
| --------------------- | ------------------------------- |
| Cuerdas               | Strings.stencil                 |
| Activos               | Activos.stencil                 |
| Listas de propiedades | Plists.stencil                  |
| Fuentes               | Fuentes.stencil                 |
| Datos básicos         | CoreData.stencil                |
| Creador de interfaces | InterfaceBuilder.stencil        |
| JSON                  | JSON.stencil                    |
| YAML                  | YAML.stencil                    |

Al definir los sintetizadores de recursos en el proyecto, puedes especificar el
nombre del plugin para utilizar las plantillas del mismo:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Plugin de tareas <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
Los plugins de tareas están obsoletos. Echa un vistazo a [esta entrada del
blog](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects) si estás
buscando una solución de automatización para tu proyecto.
<!-- -->
:::

Las tareas son `$PATH`-ejecutables expuestos que son invocables a través del
comando `tuist` si siguen la convención de nomenclatura `tuist-<task-name>`. En
versiones anteriores, Tuist proporcionaba algunas convenciones y herramientas
débiles bajo `tuist plugin` para `construir`, `ejecutar`, `probar` y `archivar`
tareas representadas por ejecutables en paquetes Swift, pero hemos desaprobado
esta característica ya que aumenta la carga de mantenimiento y la complejidad de
la herramienta.

Si estabas utilizando Tuist para distribuir tareas, te recomendamos que
construyas tu
- Puedes seguir usando el `ProjectAutomation.xcframework` distribuido con cada
  versión de Tuist para tener acceso al grafo del proyecto desde tu lógica con
  `let graph = try Tuist.graph()`. El comando utiliza sytem process para
  ejecutar el comando `tuist`, y devolver la representación en memoria del grafo
  del proyecto.
- Para distribuir tareas, recomendamos incluir el binario fat compatible con
  `arm64` y `x86_64` en las versiones de GitHub, y utilizar
  [Mise](https://mise.jdx.dev) como herramienta de instalación. Para indicarle a
  Mise cómo instalar tu herramienta, necesitarás un repositorio de plugins.
  Puedes usar [Tuist's](https://github.com/asdf-community/asdf-tuist) como
  referencia.
- Si denomina a su herramienta `tuist-{xxx}` y los usuarios pueden instalarla
  ejecutando `mise install`, pueden ejecutarla invocándola directamente o a
  través de `tuist xxx`.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
Planeamos consolidar los modelos de `ProjectAutomation` y `XcodeGraph` en un
único framework compatible con versiones anteriores que exponga la totalidad del
grafo del proyecto al usuario. Además, extraeremos la lógica de generación en
una nueva capa, `XcodeGraph` que también podrás utilizar desde tu propia CLI.
Piensa en ello como construir tu propio Tuist.
<!-- -->
:::

## Uso de plugins {#using-plugins}

Para utilizar un plugin, tendrás que añadirlo al archivo de manifiesto
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
de tu proyecto:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

Si quieres reutilizar un plugin en distintos proyectos que se encuentren en
diferentes repositorios, puedes insertar tu plugin en un repositorio Git y hacer
referencia a él en el archivo `Tuist.swift`:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

Después de añadir los plugins, `tuist install` buscará los plugins en un
directorio de caché global.

::: info NO VERSION RESOLUTION
<!-- -->
Como habrás observado, no ofrecemos resolución de versiones para los plugins.
Recomendamos utilizar etiquetas Git o SHA para garantizar la reproducibilidad.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
Cuando se utiliza un plugin de ayuda para la descripción del proyecto, el nombre
del módulo que contiene la ayuda es el nombre del plugin.
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
