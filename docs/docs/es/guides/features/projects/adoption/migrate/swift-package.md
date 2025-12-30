---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# Migrar un paquete Swift {#migrate-a-swift-package}

Swift Package Manager surgió como un gestor de dependencias para código Swift
que, sin quererlo, se encontró resolviendo el problema de gestionar proyectos y
dar soporte a otros lenguajes de programación como Objective-C. Debido a que la
herramienta fue diseñada con un propósito diferente en mente, puede ser un reto
utilizarla para gestionar proyectos a escala porque carece de la flexibilidad,
el rendimiento y la potencia que proporciona Tuist. Esto queda bien reflejado en
el artículo [Scaling iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2), que
incluye la siguiente tabla en la que se compara el rendimiento de Swift Package
Manager y los proyectos nativos de Xcode:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

A menudo nos encontramos con desarrolladores y organizaciones que cuestionan la
necesidad de Tuist considerando que Swift Package Manager puede desempeñar un
papel similar de gestión de proyectos. Algunos se aventuran en una migración
para darse cuenta más tarde de que su experiencia como desarrollador se ha
degradado significativamente. Por ejemplo, el cambio de nombre de un archivo
puede tardar hasta 15 segundos en volver a indexarse. ¡15 segundos!

**Si Apple hará de Swift Package Manager un gestor de proyectos construido a
escala es incierto.** Sin embargo, no estamos viendo ninguna señal de que eso
vaya a suceder. De hecho, estamos viendo todo lo contrario. Están tomando
decisiones inspiradas en Xcode, como lograr la conveniencia a través de
configuraciones implícitas, que
<LocalizedLink href="/guides/features/projects/cost-of-convenience">como sabrás,</LocalizedLink> es la fuente de complicaciones a escala. Creemos que
Apple tendría que ir a los primeros principios y revisar algunas decisiones que
tenían sentido como gestor de dependencias pero no como gestor de proyectos, por
ejemplo el uso de un lenguaje compilado como interfaz para definir proyectos.

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
Tuist trata a Swift Package Manager como un gestor de dependencias, y es un gran
gestor. Lo usamos para resolver dependencias y construirlas. No lo usamos para
definir proyectos porque no está diseñado para eso.
<!-- -->
:::

## Migración de Swift Package Manager a Tuist {#migrating-from-swift-package-manager-to-tuist}

Las similitudes entre Swift Package Manager y Tuist hacen que el proceso de
migración sea sencillo. La principal diferencia es que definirás tus proyectos
utilizando el DSL de Tuist en lugar de `Package.swift`.

En primer lugar, cree un archivo `Project.swift` junto a su archivo
`Package.swift`. El archivo `Project.swift` contendrá la definición de su
proyecto. Este es un ejemplo de un archivo `Project.swift` que define un
proyecto con un único objetivo:

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

- **ProjectDescription**: En lugar de utilizar `PackageDescription`, utilizará
  `ProjectDescription`.
- **Proyecto:** En lugar de exportar un paquete `instancia`, exportará un
  proyecto `instancia`.
- **Lenguaje de Xcode:** Las primitivas que utilizas para definir tu proyecto
  imitan el lenguaje de Xcode, por lo que encontrarás esquemas, objetivos y
  fases de compilación entre otros.

A continuación, cree un archivo `Tuist.swift` con el siguiente contenido:

```swift
import ProjectDescription

let tuist = Tuist()
```

El `Tuist.swift` contiene la configuración para tu proyecto y su ruta sirve como
referencia para determinar la raíz de tu proyecto. Puedes consultar el documento
<LocalizedLink href="/guides/features/projects/directory-structure">estructura de directorios</LocalizedLink> para saber más sobre la estructura de los
proyectos Tuist.

## Editar el proyecto {#editing-the-project}

Puede utilizar <LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink> para editar el proyecto en Xcode. El comando generará un
proyecto Xcode que puede abrir y empezar a trabajar en él.

```bash
tuist edit
```

Dependiendo del tamaño del proyecto, puedes plantearte utilizarlo de una sola
vez o de forma incremental. Recomendamos empezar con un proyecto pequeño para
familiarizarse con el DSL y el flujo de trabajo. Nuestro consejo es empezar
siempre por el objetivo del que más se dependa y llegar hasta el objetivo de
nivel superior.
