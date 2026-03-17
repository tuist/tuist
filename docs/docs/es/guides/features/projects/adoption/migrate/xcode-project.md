---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Migrar un proyecto de Xcode {#migrate-an-xcode-project}

A menos que
<LocalizedLink href="/guides/features/projects/adoption/new-project">crees un
nuevo proyecto con Tuist</LocalizedLink>, en cuyo caso todo se configura
automáticamente, tendrás que definir tus proyectos de Xcode utilizando los
primitivos de Tuist. Lo tedioso que resulte este proceso dependerá de la
complejidad de tus proyectos.

Como probablemente ya sabes, los proyectos de Xcode pueden volverse desordenados
y complejos con el tiempo: grupos que no coinciden con la estructura de
directorios, archivos compartidos entre distintos objetivos o referencias a
archivos que apuntan a archivos inexistentes (por mencionar algunos ejemplos).
Toda esa complejidad acumulada nos dificulta ofrecer un comando que migre el
proyecto de forma fiable.

Además, la migración manual es un ejercicio excelente para limpiar y simplificar
tus proyectos. No solo los desarrolladores de tu proyecto te lo agradecerán,
sino también Xcode, que los procesará e indexará más rápidamente. Una vez que
hayas adoptado Tuist por completo, este se asegurará de que los proyectos estén
definidos de forma coherente y de que sigan siendo sencillos.

Con el fin de facilitarte el trabajo, te ofrecemos algunas pautas basadas en los
comentarios que hemos recibido de los usuarios.

## Crear estructura del proyecto {#create-project-scaffold}

En primer lugar, crea una estructura para tu proyecto con los siguientes
archivos Tuist:

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

## Compila y prueba el proyecto Tuist en CI {#build-and-test-the-tuist-project-in-ci}

Para garantizar que la migración de cada cambio sea válida, recomendamos ampliar
tu integración continua para compilar y probar el proyecto generado por Tuist a
partir de tu archivo de manifiesto:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## `Extrae la configuración de compilación del proyecto en archivos .xcconfig` {#extract-the-project-build-settings-into-xcconfig-files}

Extrae la configuración de compilación del proyecto a un archivo .xcconfig` de `
para que el proyecto sea más ligero y fácil de migrar. Puedes utilizar el
siguiente comando para extraer la configuración de compilación del proyecto a un
archivo .xcconfig` de `:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

A continuación, actualiza el archivo `Project.swift` para que apunte al archivo
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

A continuación, amplíe su canalización de integración continua para ejecutar el
siguiente comando y asegurarse de que los cambios en la configuración de
compilación se realizan directamente en los archivos .xcconfig` de `:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## Extraer dependencias del paquete {#extract-package-dependencies}

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

::: tip PRODUCT TYPES
<!-- -->
Puedes anular el tipo de producto para un paquete específico añadiéndolo al
diccionario ` `productTypes`` de la estructura ` `PackageSettings``. Por
defecto, Tuist asume que todos los paquetes son marcos estáticos.
<!-- -->
:::


## Determina el orden de migración {#determine-the-migration-order}

Recomendamos migrar los objetivos empezando por el que más dependencias tiene y
terminando por el que menos. Puedes utilizar el siguiente comando para listar
los objetivos de un proyecto, ordenados por número de dependencias:

```bash
tuist migration list-targets -p Project.xcodeproj
```

Empieza a migrar los objetivos desde la parte superior de la lista, ya que son
los que más se utilizan.


## Migrar destinos {#migrate-targets}

Migrar los destinos uno por uno. Recomendamos realizar una solicitud de
incorporación de cambios (pull request) para cada destino, a fin de garantizar
que los cambios se revisen y se prueben antes de fusionarlos.

### `Extrae la configuración de compilación de destino a los archivos .xcconfig` {#extract-the-target-build-settings-into-xcconfig-files}

` Al igual que hiciste con la configuración de compilación del proyecto, extrae
la configuración de compilación del destino a un archivo .xcconfig ` para que el
destino sea más ligero y fácil de migrar. Puedes utilizar el siguiente comando
para extraer la configuración de compilación del destino a un archivo .xcconfig
`` :

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### Define el destino en el archivo ` `Project.swift`` {#define-the-target-in-the-projectswift-file}

Define el destino en `Project.targets`:

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
Si el objetivo tiene un objetivo de prueba asociado, debes definirlo también en
el archivo` del proyecto `.swift, repitiendo los mismos pasos.
<!-- -->
:::

### Valida la migración de destino {#validate-the-target-migration}

Ejecuta `tuist generate` seguido de `xcodebuild build` para asegurarte de que el
proyecto se compila, y `tuist test` para asegurarte de que las pruebas se
superan. Además, puedes usar [xcdiff](https://github.com/bloomberg/xcdiff) para
comparar el proyecto Xcode generado con el existente y asegurarte de que los
cambios son correctos.

### Repetir {#repeat}

Repite el proceso hasta que todos los objetivos se hayan migrado por completo.
Una vez que hayas terminado, te recomendamos actualizar tus pipelines de CI y CD
para compilar y probar el proyecto utilizando `tuist generate` seguido de
`xcodebuild build` y `tuist test`.

## Solución de problemas {#troubleshooting}

### Errores de compilación debidos a archivos que faltan. {#compilation-errors-due-to-missing-files}

Si los archivos asociados a los objetivos de tu proyecto de Xcode no estaban
todos contenidos en un directorio del sistema de archivos que representara el
objetivo, es posible que el proyecto no se compile. Asegúrate de que la lista de
archivos tras generar el proyecto con Tuist coincida con la lista de archivos
del proyecto de Xcode, y aprovecha para alinear la estructura de archivos con la
estructura del objetivo.
