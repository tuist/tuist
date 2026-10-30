---
{
  "title": "Migrar un paquete Swift",
  "titleTemplate": ":title · Migración · Adopción · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Migra la gestión de proyectos desde Swift Package Manager a Tuist."
}
---
# Migrar un paquete Swift {#migrate-a-swift-package}

Swift Package Manager surgió como un gestor de dependencias para código Swift que, sin pretenderlo, terminó resolviendo el problema de gestionar proyectos y dar soporte a otros lenguajes de programación como Objective-C. Dado que la herramienta se diseñó con otro propósito en mente, puede resultar difícil utilizarla para gestionar proyectos a escala, ya que carece de la flexibilidad, el rendimiento y la potencia que ofrece Tuist. Esto queda bien reflejado en el artículo [Scaling iOS at Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2), que incluye la siguiente tabla comparativa del rendimiento de Swift Package Manager frente a los proyectos nativos de Xcode:

<img style="max-width: 400px;" alt="Una tabla que compara la regresión de rendimiento al usar SPM en lugar de proyectos nativos de Xcode" src="/images/guides/start/migrate/performance-table.webp">

A menudo nos encontramos con desarrolladores y organizaciones que cuestionan la necesidad de Tuist, dado que Swift Package Manager puede asumir un rol similar en la gestión de proyectos. Algunos emprenden una migración para luego darse cuenta de que su experiencia de desarrollo se ha degradado significativamente. Por ejemplo, renombrar un archivo puede tardar hasta 15 segundos en reindexarse. ¡15 segundos!

**No está claro si Apple convertirá Swift Package Manager en un gestor de proyectos diseñado para escalar.** Sin embargo, no vemos indicios de que eso esté ocurriendo. De hecho, observamos todo lo contrario. Están tomando decisiones inspiradas en Xcode, como lograr comodidad mediante configuraciones implícitas, lo cual <.localized_link href="/guides/features/projects/cost-of-convenience">como sabrás,</.localized_link> es la fuente de complicaciones a escala. Creemos que Apple debería volver a los principios básicos y revisar algunas decisiones que tenían sentido como gestor de dependencias, pero no como gestor de proyectos; por ejemplo, el uso de un lenguaje compilado como interfaz para definir proyectos.

> [!TIP]
> **SPM solo como gestor de dependencias**
>
> Tuist trata Swift Package Manager como un gestor de dependencias, y es excelente en ese rol. Lo usamos para resolver dependencias y compilarlas. No lo utilizamos para definir proyectos porque no está diseñado para ello.


## Migrar de Swift Package Manager a Tuist {#migrating-from-swift-package-manager-to-tuist}

Las similitudes entre Swift Package Manager y Tuist hacen que el proceso de migración sea sencillo. La principal diferencia es que definirás tus proyectos usando el DSL de Tuist en lugar de `Package.swift`.

Primero, crea un archivo `Project.swift` junto a tu archivo `Package.swift`. El archivo `Project.swift` contendrá la definición de tu proyecto. Aquí tienes un ejemplo de un archivo `Project.swift` que define un proyecto con un único target:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["Sources/**/*.swift"]*
        ),
    ]
)
```

Algunos aspectos a tener en cuenta:

- **ProjectDescription**: En lugar de usar `PackageDescription`, usarás `ProjectDescription`.
- **Proyecto:** En lugar de exportar una instancia de `package`, exportarás una instancia de `project`.
- **Lenguaje de Xcode:** Las primitivas que usas para definir tu proyecto imitan el lenguaje de Xcode, por lo que encontrarás esquemas, targets y fases de compilación, entre otros.

Luego crea un archivo `Tuist.swift` con el siguiente contenido:

```swift
import ProjectDescription

let tuist = Tuist()
```

El archivo `Tuist.swift` contiene la configuración de tu proyecto y su ruta sirve como referencia para determinar la raíz del mismo. Puedes consultar el documento sobre la <.localized_link href="/guides/features/projects/directory-structure">estructura de directorios</.localized_link> para obtener más información sobre la estructura de los proyectos de Tuist.

## Editar el proyecto {#editing-the-project}

Puedes usar <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> para editar el proyecto en Xcode. El comando generará un proyecto de Xcode que podrás abrir y comenzar a trabajar en él.

```bash
tuist edit
```

Dependiendo del tamaño del proyecto, podrías considerar usarlo de una sola vez o de forma incremental. Recomendamos comenzar con un proyecto pequeño para familiarizarte con el DSL y el flujo de trabajo. Nuestro consejo es siempre empezar desde el target con más dependencias entrantes y avanzar hasta el target de nivel superior.
