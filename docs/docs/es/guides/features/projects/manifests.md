---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# Manifiestos {#manifests}

Tuist utiliza por defecto archivos Swift para definir proyectos y espacios de
trabajo y configurar el proceso de generación. Estos archivos se denominan
archivos de manifiesto **** en toda la documentación.

La decisión de utilizar Swift se inspiró en el [Swift Package
Manager](https://www.swift.org/documentation/package-manager/), que también
utiliza archivos Swift para definir paquetes. Gracias al uso de Swift, podemos
aprovechar el compilador para validar la corrección del contenido y reutilizar
el código en distintos archivos de manifiesto, y Xcode para ofrecer una
experiencia de edición de primera clase gracias al resaltado de sintaxis, el
autocompletado y la validación.

::: info CACHING
<!-- -->
Dado que los archivos de manifiesto son archivos Swift que necesitan ser
compilados, Tuist almacena en caché los resultados de la compilación para
acelerar el proceso de análisis. Por lo tanto, notarás que la primera vez que
ejecutes Tuist, puede tardar un poco más en generar el proyecto. Las siguientes
ejecuciones serán más rápidas.
<!-- -->
:::

## Proyecto.swift {#projectswift}

El
<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
manifiesto declara un proyecto Xcode. El proyecto se genera en el mismo
directorio donde se encuentra el archivo de manifiesto con el nombre indicado en
la propiedad `name`.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


::: warning ROOT VARIABLES
<!-- -->
La única variable que debe estar en la raíz del manifiesto es `let project =
Project(...)`. Si necesitas reutilizar código en varias partes del manifiesto,
puedes utilizar funciones Swift.
<!-- -->
:::

## Espacio de trabajo.swift {#workspaceswift}

Por defecto, Tuist genera un [Xcode
Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)
que contiene el proyecto que se está generando y los proyectos de sus
dependencias. Si por alguna razón deseas personalizar el espacio de trabajo para
añadir proyectos adicionales o incluir archivos y grupos, puedes hacerlo
definiendo un manifiesto
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>.

```swift
// Workspace.swift
import ProjectDescription

let workspace = Workspace(
    name: "App-Workspace",
    projects: [
        "./App", // Path to directory containing the Project.swift file
    ]
)
```

::: info
<!-- -->
Tuist resolverá el gráfico de dependencias e incluirá los proyectos de las
dependencias en el espacio de trabajo. No necesitas incluirlos manualmente. Esto
es necesario para que el sistema de compilación resuelva las dependencias
correctamente.
<!-- -->
:::

### Multi o monoproyecto {#multi-or-monoproject}

Una pregunta que surge a menudo es si utilizar un único proyecto o varios
proyectos en un espacio de trabajo. En un mundo sin Tuist, donde una
configuración monoproyecto provocaría frecuentes conflictos Git, se recomienda
el uso de espacios de trabajo. Sin embargo, dado que no recomendamos incluir los
proyectos Xcode generados por Tuist en el repositorio Git, los conflictos Git no
son un problema. Por lo tanto, la decisión de utilizar un único proyecto o
varios proyectos en un espacio de trabajo depende de ti.

En el proyecto Tuist nos apoyamos en mono-proyectos porque el tiempo de
generación en frío es más rápido (menos archivos de manifiesto para compilar) y
aprovechamos
<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink> como unidad de encapsulación. Sin embargo, es posible
que desee utilizar los proyectos de Xcode como una unidad de encapsulación para
representar diferentes dominios de su aplicación, que se alinea más
estrechamente con la estructura de proyecto recomendada por Xcode.

## Tuist.swift {#tuistswift}

Tuist proporciona
<LocalizedLink href="/contributors/principles.html#default-to-conventions">sensibles valores por defecto</LocalizedLink> para simplificar la configuración del
proyecto. Sin embargo, puedes personalizar la configuración definiendo un
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
en la raíz del proyecto, que es utilizado por Tuist para determinar la raíz del
proyecto.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
