---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# Complementos {#plugins}

Los complementos son una herramienta para compartir y reutilizar artefactos de
Tuist en múltiples proyectos. Se admiten los siguientes artefactos:

- <LocalizedLink href="/guides/features/projects/code-sharing">Ayudantes de
  descripción del proyecto</LocalizedLink> en varios proyectos.
- <LocalizedLink href="/guides/features/projects/templates">Plantillas</LocalizedLink>
  en varios proyectos.
- Tareas en varios proyectos.
- <LocalizedLink href="/guides/features/projects/synthesized-files">Plantilla de
  acceso a recursos</LocalizedLink> en varios proyectos.

Ten en cuenta que los complementos están diseñados para ser una forma sencilla
de ampliar la funcionalidad de Tuist. Por lo tanto, hay **algunas limitaciones
que debes tener en cuenta**:

- Un complemento no puede depender de otro complemento.
- Un complemento no puede depender de paquetes Swift de terceros.
- Un complemento no puede utilizar los ayudantes de descripción del proyecto del
  proyecto que utiliza el complemento.

Si necesitas más flexibilidad, considera sugerir una función para la herramienta
o crear tu propia solución basándote en el marco de generación de Tuist,
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## Tipos de plugins {#plugin-types}

### Complemento de ayuda para la descripción del proyecto. {#project-description-helper-plugin}

Un complemento de ayuda para la descripción del proyecto se representa mediante
un directorio que contiene un archivo de manifiesto `Plugin.swift` que declara
el nombre del complemento y un directorio `ProjectDescriptionHelpers` que
contiene los archivos Swift de ayuda.

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

### Complemento de plantillas de acceso a recursos {#resource-accessor-templates-plugin}

Si necesitas compartir
<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">accesores
de recursos sintetizados</LocalizedLink>, puedes utilizar este tipo de
complemento. El complemento está representado por un directorio que contiene un
archivo de manifiesto `Plugin.swift` que declara el nombre del complemento y un
directorio `ResourceSynthesizers` que contiene los archivos de plantilla del
accesor de recursos.


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
| Cadenas               | Strings.stencil                 |
| Activos               | Assets.stencil                  |
| Listas de propiedades | Plists.stencil                  |
| Fuentes               | Fonts.stencil                   |
| Datos básicos         | CoreData.stencil                |
| Interface Builder     | InterfaceBuilder.stencil        |
| JSON                  | JSON.stencil                    |
| YAML                  | YAML.stencil                    |

Al definir los sintetizadores de recursos en el proyecto, puede especificar el
nombre del complemento para utilizar las plantillas del complemento:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Plugin de tareas <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
Los complementos de tareas están obsoletos. Consulte [esta entrada del
blog](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects) si busca
una solución de automatización para su proyecto.
<!-- -->
:::

Las tareas son `$PATH` ejecutables expuestos que se pueden invocar a través del
comando `tuist` si siguen la convención de nomenclatura `tuist-`. En versiones
anteriores, Tuist proporcionaba algunas convenciones y herramientas débiles en
`tuist plugin` para `build`, `run`, `test` y `archive` tareas representadas por
ejecutables en paquetes Swift, pero hemos dejado de utilizar esta función, ya
que aumenta la carga de mantenimiento y la complejidad de la herramienta.

Si utilizabas Tuist para distribuir tareas, te recomendamos crear tu
- Puede seguir utilizando el `ProjectAutomation.xcframework` distribuido con
  cada versión de Tuist para tener acceso al gráfico del proyecto desde su
  lógica con `let graph = try Tuist.graph()`. El comando utiliza el proceso del
  sistema para ejecutar el comando `tuist` y devuelve la representación en
  memoria del gráfico del proyecto.
- Para distribuir tareas, recomendamos incluir el binario fat que admite `arm64`
  y `x86_64` en las versiones de GitHub, y utilizar [Mise](https://mise.jdx.dev)
  como herramienta de instalación. Para indicar a Mise cómo instalar tu
  herramienta, necesitarás un repositorio de complementos. Puedes utilizar
  [Tuist's](https://github.com/asdf-community/asdf-tuist) como referencia.
- Si nombras tu herramienta `tuist-{xxx}` y los usuarios pueden instalarla
  ejecutando `mise install`, pueden ejecutarla invocándola directamente o a
  través de `tuist xxx`.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
Tenemos previsto consolidar los modelos de `ProjectAutomation` y `XcodeGraph` en
un único marco compatible con versiones anteriores que muestre al usuario la
totalidad del gráfico del proyecto. Además, extraeremos la lógica de generación
a una nueva capa, `XcodeGraph`, que también podrás utilizar desde tu propia CLI.
Piensa en ello como si estuvieras creando tu propio Tuist.
<!-- -->
:::

## Uso de complementos {#using-plugins}

Para utilizar un complemento, tendrás que añadirlo al archivo
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
manifest de tu proyecto:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

Si quieres reutilizar un complemento en proyectos que se encuentran en
diferentes repositorios, puedes enviar tu complemento a un repositorio Git y
hacer referencia a él en el archivo `Tuist.swift`:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

Después de añadir los complementos, `tuist install` recuperará los complementos
en un directorio de caché global.

::: info NO VERSION RESOLUTION
<!-- -->
Como habrás observado, no proporcionamos resolución de versiones para los
complementos. Recomendamos utilizar etiquetas Git o SHA para garantizar la
reproducibilidad.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
Cuando se utiliza un complemento de ayuda para la descripción del proyecto, el
nombre del módulo que contiene las ayudas es el nombre del complemento.
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
