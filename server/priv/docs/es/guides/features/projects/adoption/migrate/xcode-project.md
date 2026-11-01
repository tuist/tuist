---
{
  "title": "Migrar un proyecto de Xcode",
  "titleTemplate": ":title · Migración · Adopción · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende a migrar un proyecto de Xcode a un proyecto de Tuist."
}
---
# Migrar un proyecto de Xcode {#migrate-an-xcode-project}

A menos que <.localized_link href="/guides/features/projects/adoption/new-project">crees un nuevo proyecto con Tuist</.localized_link>, en cuyo caso todo se configura automáticamente, tendrás que definir tus proyectos de Xcode usando las primitivas de Tuist. Lo tedioso de este proceso depende de la complejidad de tus proyectos.

Como probablemente sabes, los proyectos de Xcode pueden volverse desordenados y complejos con el tiempo: grupos que no coinciden con la estructura de directorios, archivos compartidos entre targets o referencias a archivos que ya no existen (por mencionar algunos). Toda esa complejidad acumulada dificulta ofrecer un comando que migre proyectos de forma fiable.

Además, la migración manual es un excelente ejercicio para limpiar y simplificar tus proyectos. No solo lo agradecerán los desarrolladores de tu equipo, sino también Xcode, que procesará e indexará los proyectos más rápido. Una vez que hayas adoptado Tuist por completo, se asegurará de que los proyectos estén definidos de manera consistente y sigan siendo sencillos.

Para facilitar ese trabajo, te ofrecemos algunas pautas basadas en el feedback que hemos recibido de los usuarios.

## Crear el andamiaje del proyecto {#create-project-scaffold}

En primer lugar, crea el andamiaje de tu proyecto con los siguientes archivos de Tuist:

::: code-group

```js [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```

```js [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp-Tuist",
    targets: [
        /** Targets will go here **/
    ]
)
```

```js [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
    ]
)
```
<!-- -->
:::

`Project.swift` es el archivo de manifiesto donde definirás tu proyecto, y `Package.swift` es el archivo de manifiesto donde definirás tus dependencias. El archivo `Tuist.swift` es donde puedes definir ajustes de Tuist con alcance de proyecto.

> [!TIP]
> **Nombre del proyecto con sufijo -Tuist**
>
> Para evitar conflictos con el proyecto de Xcode existente, recomendamos añadir el sufijo `-Tuist` al nombre del proyecto. Puedes eliminarlo una vez que hayas migrado completamente tu proyecto a Tuist.


## Compilar y probar el proyecto de Tuist en CI {#build-and-test-the-tuist-project-in-ci}

Para garantizar que la migración de cada cambio sea válida, recomendamos ampliar tu integración continua para compilar y probar el proyecto generado por Tuist a partir de tu archivo de manifiesto:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## Extraer los ajustes de compilación del proyecto en archivos `.xcconfig` {#extract-the-project-build-settings-into-xcconfig-files}

Extrae los ajustes de compilación del proyecto a un archivo `.xcconfig` para que el proyecto sea más ligero y fácil de migrar. Puedes usar el siguiente comando para extraer los ajustes de compilación del proyecto a un archivo `.xcconfig`:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

Luego actualiza tu archivo `Project.swift` para que apunte al archivo `.xcconfig` que acabas de crear:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

Después amplía tu pipeline de integración continua para ejecutar el siguiente comando y asegurar que los cambios en los ajustes de compilación se realicen directamente en los archivos `.xcconfig`:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## Extraer las dependencias de paquetes {#extract-package-dependencies}

Extrae todas las dependencias de tu proyecto al archivo `Tuist/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0")) // [!code ++]
    ]
)
```

> [!TIP]
> **Tipos de producto**
>
> Puedes sobrescribir el tipo de producto de un paquete específico añadiéndolo al diccionario `productTypes` dentro de la estructura `PackageSettings`. Por defecto, Tuist asume que todos los paquetes son frameworks estáticos.


## Determinar el orden de migración {#determine-the-migration-order}

Recomendamos migrar los targets desde el que tiene más dependencias hacia el que tiene menos. Puedes usar el siguiente comando para listar los targets de un proyecto, ordenados por el número de dependencias:

```bash
tuist migration list-targets -p Project.xcodeproj
```

Comienza a migrar los targets desde la parte superior de la lista, ya que son los que más dependen de otros.


## Migrar targets {#migrate-targets}

Migra los targets uno a uno. Recomendamos crear una pull request por cada target para garantizar que los cambios se revisen y prueben antes de fusionarlos.

### Extraer los ajustes de compilación del target en archivos `.xcconfig` {#extract-the-target-build-settings-into-xcconfig-files}

Al igual que hiciste con los ajustes de compilación del proyecto, extrae los ajustes de compilación del target a un archivo `.xcconfig` para que el target sea más ligero y fácil de migrar. Puedes usar el siguiente comando para extraer los ajustes de compilación del target a un archivo `.xcconfig`:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### Definir el target en el archivo `Project.swift` {#define-the-target-in-the-projectswift-file}

Define el target en `Project.targets`:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target( // [!code ++]
            name: "TargetX", // [!code ++]
            destinations: .iOS, // [!code ++]
            product: .framework, // [!code ++] // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX", // [!code ++]
            sources: ["Sources/TargetX/**"], // [!code ++]
            dependencies: [ // [!code ++]
                /** Dependencies go here **/ // [!code ++]
                /** .external(name: "Kingfisher") **/ // [!code ++]
                /** .target(name: "OtherProjectTarget") **/ // [!code ++]
            ], // [!code ++]
            settings: .settings(configurations: [ // [!code ++]
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
                .debug(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
            ]) // [!code ++]
        ), // [!code ++]
    ]
)
```

> [!NOTE]
> **Targets de tests**
>
> Si el target tiene un target de tests asociado, deberías definirlo también en el archivo `Project.swift` repitiendo los mismos pasos.


### Validar la migración del target {#validate-the-target-migration}

Ejecuta `tuist generate` seguido de `xcodebuild build` para asegurar que el proyecto compila, y `tuist test` para asegurar que los tests pasan. Además, puedes usar [xcdiff](https://github.com/bloomberg/xcdiff) para comparar el proyecto de Xcode generado con el existente y verificar que los cambios sean correctos.

### Repetir {#repeat}

Repite hasta que todos los targets estén completamente migrados. Cuando termines, recomendamos actualizar tus pipelines de CI y CD para compilar y probar el proyecto usando `tuist generate` seguido de `xcodebuild build` y `tuist test`.

## Solución de problemas {#troubleshooting}

### Errores de compilación por archivos faltantes. {#compilation-errors-due-to-missing-files}

Si los archivos asociados a los targets de tu proyecto de Xcode no estaban todos contenidos en un directorio del sistema de archivos que representara el target, podrías terminar con un proyecto que no compila. Asegúrate de que la lista de archivos tras generar el proyecto con Tuist coincida con la lista de archivos del proyecto de Xcode y aprovecha para alinear la estructura de archivos con la estructura de targets.
