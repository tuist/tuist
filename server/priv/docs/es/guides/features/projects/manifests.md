---
{
  "title": "Manifiestos",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Archivos de manifiesto que definen tus proyectos, espacios de trabajo y configuración de generación en Tuist."
}
---
# Manifiestos {#manifests}

Tuist utiliza archivos Swift como la forma principal de definir proyectos y espacios de trabajo, así como para configurar el proceso de generación. Estos archivos se denominan **archivos de manifiesto** en toda la documentación.

La decisión de usar Swift se inspiró en el [Swift Package Manager](https://www.swift.org/documentation/package-manager/), que también utiliza archivos Swift para definir paquetes. Gracias al uso de Swift, podemos aprovechar el compilador para validar la corrección del contenido y reutilizar código entre diferentes archivos de manifiesto, y Xcode para ofrecer una experiencia de edición de primera categoría gracias al resaltado de sintaxis, el autocompletado y la validación.

> [!NOTE]
> **Caché**
>
> Dado que los archivos de manifiesto son archivos Swift que necesitan compilarse, Tuist almacena en caché los resultados de la compilación para acelerar el proceso de análisis. Por lo tanto, notarás que la primera vez que ejecutes Tuist, la generación del proyecto podría tardar un poco más. Las ejecuciones posteriores serán más rápidas.


## Project.swift {#projectswift}

El manifiesto [`Project.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/project) declara un proyecto de Xcode. El proyecto se genera en el mismo directorio donde se encuentra el archivo de manifiesto con el nombre indicado en la propiedad `name`.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


> [!WARNING]
> **Variables raíz**
>
> La única variable que debería estar en la raíz del manifiesto es `let project = Project(...)`. Si necesitas reutilizar código en varias partes del manifiesto, puedes usar funciones de Swift.


## Workspace.swift {#workspaceswift}

De forma predeterminada, Tuist genera un [espacio de trabajo de Xcode](https://developer.apple.com/documentation/xcode/projects-and-workspaces) que contiene el proyecto que se está generando y los proyectos de sus dependencias. Si por alguna razón deseas personalizar el espacio de trabajo para añadir proyectos adicionales o incluir archivos y grupos, puedes hacerlo definiendo un manifiesto [`Workspace.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/workspace).

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

> [!NOTE]
> Tuist resolverá el grafo de dependencias e incluirá los proyectos de las dependencias en el espacio de trabajo. No necesitas incluirlos manualmente. Esto es necesario para que el sistema de compilación resuelva las dependencias correctamente.


### Proyecto único o múltiple {#multi-or-monoproject}

Una pregunta frecuente es si usar un único proyecto o varios proyectos en un espacio de trabajo. En un entorno sin Tuist, donde una configuración de proyecto único provocaría conflictos frecuentes en Git, se recomienda el uso de espacios de trabajo. Sin embargo, dado que no recomendamos incluir los proyectos de Xcode generados por Tuist en el repositorio de Git, los conflictos de Git no son un problema. Por lo tanto, la decisión de usar un único proyecto o varios proyectos en un espacio de trabajo depende de ti.

En el proyecto Tuist preferimos los proyectos únicos porque el tiempo de generación en frío es más rápido (menos archivos de manifiesto que compilar) y utilizamos <.localized_link href="/guides/features/projects/code-sharing">helpers de descripción de proyecto</.localized_link> como unidad de encapsulación. Sin embargo, podrías querer usar proyectos de Xcode como unidad de encapsulación para representar diferentes dominios de tu aplicación, lo cual se alinea más estrechamente con la estructura de proyecto recomendada por Xcode.

## Tuist.swift {#tuistswift}

Tuist ofrece <.localized_link href="/contributors/principles#default-to-conventions">valores predeterminados razonables</.localized_link> para simplificar la configuración del proyecto. Sin embargo, puedes personalizar la configuración definiendo un [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) en la raíz del proyecto, que Tuist utiliza para determinar la raíz del proyecto.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
