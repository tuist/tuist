---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Migrar un proyecto Xcode {#migrate-an-xcode-project}

A menos que
<LocalizedLink href="/guides/features/projects/adoption/new-project">crees un nuevo proyecto usando Tuist</LocalizedLink>, en cuyo caso se te configura todo
automáticamente, tendrás que definir tus proyectos de Xcode usando las
primitivas de Tuist. Lo tedioso de este proceso depende de la complejidad de tus
proyectos.

Como probablemente sepas, los proyectos de Xcode pueden volverse desordenados y
complejos con el tiempo: grupos que no coinciden con la estructura de
directorios, archivos que se comparten entre objetivos o referencias a archivos
que apuntan a archivos inexistentes (por mencionar algunos). Toda esa
complejidad acumulada hace que nos resulte difícil proporcionar un comando que
migre los proyectos de forma fiable.

Además, la migración manual es un excelente ejercicio para limpiar y simplificar
tus proyectos. No sólo lo agradecerán los desarrolladores de tu proyecto, sino
también Xcode, que los procesará e indexará más rápidamente. Una vez que hayas
adoptado por completo Tuist, te asegurarás de que los proyectos se definan de
forma coherente y de que sigan siendo sencillos.

Con el objetivo de facilitarle esa labor, le damos algunas pautas basadas en los
comentarios que hemos recibido de los usuarios.

## Crear un andamiaje de proyectos {#create-project-scaffold}

En primer lugar, crea un andamio para tu proyecto con los siguientes archivos
Tuist:

::: grupo de códigos

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

`Project.swift` es el archivo de manifiesto donde definirás tu proyecto, y
`Package.swift` es el archivo de manifiesto donde definirás tus dependencias. El
archivo `Tuist.swift` es donde puedes definir la configuración de Tuist para tu
proyecto.

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
Para evitar conflictos con el proyecto Xcode existente, recomendamos añadir el
sufijo `-Tuist` al nombre del proyecto. Puedes eliminarlo una vez que hayas
migrado completamente tu proyecto a Tuist.
<!-- -->
:::

## Construir y probar el proyecto Tuist en CI {#build-and-test-the-tuist-project-in-ci}

Para asegurarte de que la migración de cada cambio es válida, te recomendamos
que amplíes tu integración continua para construir y probar el proyecto generado
por Tuist a partir de tu archivo de manifiesto:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## Extraiga la configuración de compilación del proyecto en `.xcconfig` archivos {#extract-the-project-build-settings-into-xcconfig-files}

Extraiga la configuración de compilación del proyecto en un archivo `.xcconfig`
para que el proyecto sea más sencillo y fácil de migrar. Puede utilizar el
siguiente comando para extraer la configuración de compilación del proyecto en
un archivo `.xcconfig`:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

A continuación, actualice su archivo `Project.swift` para que apunte al archivo
`.xcconfig` que acaba de crear:

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

A continuación, amplíe su canal de integración continua para ejecutar el
siguiente comando y asegurarse de que los cambios en la configuración de
compilación se realizan directamente en los archivos .xcconfig` de `:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## Extraer dependencias de paquetes {#extract-package-dependencies}

Extrae todas las dependencias de tu proyecto en el archivo
`Tuist/Package.swift`:

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

::: tip PRODUCT TYPES
<!-- -->
Puedes anular el tipo de producto para un paquete específico añadiéndolo al
diccionario `productTypes` en la estructura `PackageSettings`. Por defecto,
Tuist asume que todos los paquetes son frameworks estáticos.
<!-- -->
:::


## Determinar el orden de migración {#determine-the-migration-order}

Recomendamos migrar los objetivos del más dependiente al menos dependiente.
Puede utilizar el siguiente comando para listar los objetivos de un proyecto,
ordenados por el número de dependencias:

```bash
tuist migration list-targets -p Project.xcodeproj
```

Empiece a migrar los objetivos de la parte superior de la lista, ya que son de
los que más se depende.


## Migrar objetivos {#migrate-targets}

Migre los objetivos uno a uno. Recomendamos hacer un pull request por cada
objetivo para asegurarse de que los cambios se revisan y prueban antes de
fusionarlos.

### Extraiga la configuración de compilación de destino en `.xcconfig` files {#extract-the-target-build-settings-into-xcconfig-files}

Al igual que hizo con la configuración de compilación del proyecto, extraiga la
configuración de compilación del destino en un archivo `.xcconfig` para que el
destino sea más sencillo y fácil de migrar. Puede utilizar el siguiente comando
para extraer la configuración de compilación del destino en un archivo
`.xcconfig`:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### Defina el objetivo en el archivo `Project.swift` {#define-the-target-in-the-projectswift-file}

Defina el objetivo en `Project.targets`:

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

::: info TEST TARGETS
<!-- -->
Si el objetivo tiene un objetivo de prueba asociado, deberá definirlo también en
el archivo `Project.swift` repitiendo los mismos pasos.
<!-- -->
:::

### Validar la migración de destino {#validate-the-target-migration}

Ejecute `tuist generate` seguido de `xcodebuild build` para asegurarse de que el
proyecto se construye, y `tuist test` para asegurarse de que las pruebas pasan.
Además, puede utilizar [xcdiff](https://github.com/bloomberg/xcdiff) para
comparar el proyecto Xcode generado con el existente y asegurarse de que los
cambios son correctos.

### Repita {#repeat}

Repita hasta que todos los objetivos estén completamente migrados. Una vez que
haya terminado, le recomendamos que actualice sus pipelines CI y CD para
construir y probar el proyecto utilizando `tuist generate` seguido de
`xcodebuild build` y `tuist test`.

## Solución de problemas {#troubleshooting}

### Errores de compilación por falta de archivos. {#compilation-errors-due-to-missing-files}

Si los archivos asociados a los objetivos de tu proyecto Xcode no estuvieran
todos contenidos en un directorio del sistema de archivos que representara al
objetivo, podrías acabar con un proyecto que no compilara. Asegúrese de que la
lista de archivos después de generar el proyecto con Tuist coincide con la lista
de archivos en el proyecto de Xcode, y aprovechar la oportunidad para alinear la
estructura de archivos con la estructura de destino.
