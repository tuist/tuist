---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Migrar un proyecto Xcode {#migrate-an-xcode-project}

A menos que
<LocalizedLink href="/guides/features/projects/adoption/new-project">crees un
nuevo proyecto con Tuist</LocalizedLink>, en cuyo caso todo se configura
automáticamente, tendrás que definir tus proyectos Xcode utilizando los
primitivos de Tuist. La complejidad de este proceso depende de la complejidad de
tus proyectos.

Como probablemente ya sabrá, los proyectos de Xcode pueden volverse desordenados
y complejos con el tiempo: grupos que no coinciden con la estructura de
directorios, archivos que se comparten entre objetivos o referencias a archivos
que no existen (por mencionar algunos). Toda esa complejidad acumulada nos
dificulta proporcionar un comando que migre el proyecto de forma fiable.

Además, la migración manual es un excelente ejercicio para limpiar y simplificar
tus proyectos. No solo los desarrolladores de tu proyecto te lo agradecerán,
sino también Xcode, que los procesará e indexará más rápidamente. Una vez que
hayas adoptado Tuist por completo, te asegurarás de que los proyectos estén
definidos de forma coherente y sigan siendo sencillos.

Con el fin de facilitar ese trabajo, le ofrecemos algunas pautas basadas en los
comentarios que hemos recibido de los usuarios.

## Crear estructura del proyecto {#create-project-scaffold}

En primer lugar, crea un andamiaje para tu proyecto con los siguientes archivos
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

`Project.swift` es el archivo manifiesto donde definirás tu proyecto, y
`Package.swift` es el archivo manifiesto donde definirás tus dependencias. El
archivo `Tuist.swift` es donde puedes definir la configuración de Tuist para tu
proyecto.

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
Para evitar conflictos con el proyecto Xcode existente, recomendamos añadir el
sufijo `-Tuist` al nombre del proyecto. Puedes eliminarlo una vez que hayas
migrado completamente tu proyecto a Tuist.
<!-- -->
:::

## Compila y prueba el proyecto Tuist en CI. {#build-and-test-the-tuist-project-in-ci}

Para garantizar que la migración de cada cambio sea válida, recomendamos ampliar
la integración continua para compilar y probar el proyecto generado por Tuist a
partir del archivo de manifiesto:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## Extraiga la configuración de compilación del proyecto en `.xcconfig` files {#extract-the-project-build-settings-into-xcconfig-files}

Extraiga la configuración de compilación del proyecto a un archivo `.xcconfig`
para que el proyecto sea más ligero y fácil de migrar. Puede utilizar el
siguiente comando para extraer la configuración de compilación del proyecto a un
archivo `.xcconfig`:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

A continuación, actualiza tu archivo `Project.swift` para que apunte al archivo
`.xcconfig` que acabas de crear:

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
compilación se realizan directamente en los archivos `.xcconfig`:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## Extraer dependencias del paquete {#extract-package-dependencies}

Extraiga todas las dependencias de su proyecto al archivo `Tuist/Package.swift`:

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
Puede anular el tipo de producto para un paquete específico añadiéndolo al
diccionario `productTypes` en la estructura `PackageSettings`. De forma
predeterminada, Tuist asume que todos los paquetes son marcos estáticos.
<!-- -->
:::


## Determina el orden de migración. {#determine-the-migration-order}

Recomendamos migrar los objetivos desde el que más depende hasta el que menos.
Puede utilizar el siguiente comando para enumerar los objetivos de un proyecto,
ordenados por número de dependencias:

```bash
tuist migration list-targets -p Project.xcodeproj
```

Comience a migrar los objetivos desde la parte superior de la lista, ya que son
los que más se utilizan.


## Migrar destinos {#migrate-targets}

Migra los objetivos uno por uno. Recomendamos realizar una solicitud de
extracción para cada objetivo con el fin de garantizar que los cambios se
revisen y prueben antes de fusionarlos.

### Extraiga la configuración de compilación de destino en `.xcconfig` files {#extract-the-target-build-settings-into-xcconfig-files}

Al igual que hiciste con la configuración de compilación del proyecto, extrae la
configuración de compilación del objetivo en un archivo `.xcconfig` para que el
objetivo sea más ligero y fácil de migrar. Puedes utilizar el siguiente comando
para extraer la configuración de compilación del objetivo en un archivo
`.xcconfig`:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### Defina el objetivo en el archivo `Project.swift`. {#define-the-target-in-the-projectswift-file}

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
Si el destino tiene un destino de prueba asociado, debes definirlo en el archivo
`Project.swift` repitiendo los mismos pasos.
<!-- -->
:::

### Valida la migración de destino. {#validate-the-target-migration}

Ejecute `tuist generate` seguido de `xcodebuild build` para asegurarse de que el
proyecto se compila, y `tuist test` para asegurarse de que las pruebas se
superan. Además, puede utilizar [xcdiff](https://github.com/bloomberg/xcdiff)
para comparar el proyecto Xcode generado con el existente y asegurarse de que
los cambios son correctos.

### Repite. {#repeat}

Repita hasta que todos los objetivos estén completamente migrados. Una vez que
haya terminado, le recomendamos que actualice sus canalizaciones de CI y CD para
compilar y probar el proyecto utilizando `tuist generate` seguido de `xcodebuild
build` y `tuist test`.

## Solución de problemas {#troubleshooting}

### Errores de compilación debido a archivos que faltan. {#compilation-errors-due-to-missing-files}

Si los archivos asociados a los objetivos de tu proyecto Xcode no estaban todos
contenidos en un directorio del sistema de archivos que representara el
objetivo, es posible que el proyecto no se compile. Asegúrate de que la lista de
archivos tras generar el proyecto con Tuist coincida con la lista de archivos
del proyecto Xcode y aprovecha la oportunidad para alinear la estructura de
archivos con la estructura del objetivo.
