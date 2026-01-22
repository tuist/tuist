---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# Migrar un paquete Swift {#migrate-a-swift-package}

Swift Package Manager surgió como un gestor de dependencias para el código Swift
que, sin pretenderlo, acabó resolviendo el problema de la gestión de proyectos y
la compatibilidad con otros lenguajes de programación como Objective-C. Dado que
la herramienta se diseñó con un propósito diferente, puede resultar complicado
utilizarla para gestionar proyectos a gran escala, ya que carece de la
flexibilidad, el rendimiento y la potencia que ofrece Tuist. Esto queda bien
reflejado en el artículo [Scaling iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2), que
incluye la siguiente tabla en la que se compara el rendimiento de Swift Package
Manager y los proyectos nativos de Xcode:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

A menudo nos encontramos con desarrolladores y organizaciones que cuestionan la
necesidad de Tuist, considerando que Swift Package Manager puede desempeñar una
función similar de gestión de proyectos. Algunos se aventuran a realizar la
migración y luego se dan cuenta de que su experiencia como desarrolladores se ha
degradado significativamente. Por ejemplo, el cambio de nombre de un archivo
puede tardar hasta 15 segundos en reindexarse. ¡15 segundos!

**No está claro si Apple convertirá Swift Package Manager en un gestor de
proyectos diseñado para escalar.** Sin embargo, no vemos indicios de que eso
vaya a suceder. De hecho, vemos todo lo contrario. Están tomando decisiones
inspiradas en Xcode, como lograr la comodidad a través de configuraciones
implícitas, lo que, como sabrás, es la fuente de complicaciones a gran escala.
Creemos que Apple tendría que volver a los principios básicos y revisar algunas
decisiones que tenían sentido como gestor de dependencias, pero no como gestor
de proyectos, por ejemplo, el uso de un lenguaje compilado como interfaz para
definir proyectos.

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
Tuist trata Swift Package Manager como un gestor de dependencias, y es uno muy
bueno. Lo utilizamos para resolver dependencias y para compilarlas. No lo
utilizamos para definir proyectos porque no está diseñado para eso.
<!-- -->
:::

## Migración de Swift Package Manager a Tuist {#migrating-from-swift-package-manager-to-tuist}

Las similitudes entre Swift Package Manager y Tuist hacen que el proceso de
migración sea sencillo. La principal diferencia es que definirás tus proyectos
utilizando el DSL de Tuist en lugar de `Package.swift`.

En primer lugar, cree un archivo `Project.swift` junto a su archivo
`Package.swift`. El archivo `Project.swift` contendrá la definición de su
proyecto. A continuación se muestra un ejemplo de un archivo `Project.swift` que
define un proyecto con un único objetivo:

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

Algunas cosas a tener en cuenta:

- **Descripción del proyecto**: En lugar de utilizar `Descripción del paquete`,
  utilizarás `Descripción del proyecto`.
- **Proyecto:** En lugar de exportar un paquete `` , exportará un proyecto `` .
- **Lenguaje Xcode:** Las primitivas que utilizas para definir tu proyecto
  imitan el lenguaje de Xcode, por lo que encontrarás esquemas, objetivos y
  fases de compilación, entre otros.

A continuación, crea un archivo `Tuist.swift` con el siguiente contenido:

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` contiene la configuración de tu proyecto y su ruta sirve como
referencia para determinar la raíz de tu proyecto. Puedes consultar el documento
<LocalizedLink href="/guides/features/projects/directory-structure">estructura
de directorios</LocalizedLink> para obtener más información sobre la estructura
de los proyectos Tuist.

## Edición del proyecto {#editing-the-project}

Puede utilizar <LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> para editar el proyecto en Xcode. El comando generará un
proyecto Xcode que podrá abrir y empezar a trabajar.

```bash
tuist edit
```

Dependiendo del tamaño del proyecto, puede considerar utilizarlo de una sola vez
o de forma incremental. Recomendamos comenzar con un proyecto pequeño para
familiarizarse con el DSL y el flujo de trabajo. Nuestro consejo es siempre
comenzar por el objetivo más dependiente y trabajar hasta llegar al objetivo de
nivel superior.
