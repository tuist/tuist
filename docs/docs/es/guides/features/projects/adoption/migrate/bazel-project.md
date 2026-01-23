---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# Migrar un proyecto Bazel {#migrate-a-bazel-project}

[Bazel](https://bazel.build) es un sistema de compilación que Google publicó
como código abierto en 2015. Es una potente herramienta que permite compilar y
probar software de cualquier tamaño de forma rápida y fiable. Algunas grandes
organizaciones como
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/),
[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)
o [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) lo utilizan, sin
embargo, su introducción y mantenimiento requieren una inversión inicial (es
decir, aprender la tecnología) y continua (es decir, mantenerse al día con las
actualizaciones de Xcode). Aunque esto funciona para algunas organizaciones que
lo tratan como una cuestión transversal, puede que no sea la mejor opción para
otras que quieren centrarse en el desarrollo de sus productos. Por ejemplo,
hemos visto organizaciones cuyo equipo de la plataforma iOS introdujo Bazel y
tuvo que abandonarlo después de que los ingenieros que lideraban el proyecto
dejaran la empresa. La postura de Apple sobre el fuerte acoplamiento entre Xcode
y el sistema de compilación es otro factor que dificulta el mantenimiento de los
proyectos Bazel a lo largo del tiempo.

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
En lugar de luchar contra Xcode y los proyectos Xcode, Tuist los acepta. Se
trata de los mismos conceptos (por ejemplo, objetivos, esquemas, ajustes de
compilación), un lenguaje familiar (es decir, Swift) y una experiencia sencilla
y agradable que hace que el mantenimiento y la ampliación de los proyectos sea
tarea de todos y no solo del equipo de la plataforma iOS.
<!-- -->
:::

## Reglas {#rules}

Bazel utiliza reglas para definir cómo compilar y probar el software. Las reglas
están escritas en [Starlark](https://github.com/bazelbuild/starlark), un
lenguaje similar a Python. Tuist utiliza Swift como lenguaje de configuración,
lo que proporciona a los desarrolladores la comodidad de utilizar las funciones
de autocompletado, comprobación de tipos y validación de Xcode. Por ejemplo, la
siguiente regla describe cómo compilar una biblioteca Swift en Bazel:

::: grupo de códigos
```txt [BUILD (Bazel)]
swift_library(
    name = "MyLibrary.library",
    srcs = glob(["**/*.swift"]),
    module_name = "MyLibrary"
)
```

```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(name: "MyLibrary", product: .staticLibrary, sources: ["**/*.swift"])
    ]
)
```
<!-- -->
:::

Aquí hay otro ejemplo, pero comparando cómo definir pruebas unitarias en Bazel y
Tuist:

::: grupo de códigos
```txt [BUILD (Bazel)]
ios_unit_test(
    name = "MyLibraryTests",
    bundle_id = "dev.tuist.MyLibraryTests",
    minimum_os_version = "16.0",
    test_host = "//MyApp:MyLibrary",
    deps = [":MyLibraryTests.library"],
)

```
```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibraryTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyLibraryTests",
            sources: "Tests/MyLibraryTests/**",
            dependencies: [
                .target(name: "MyLibrary"),
            ]
        )
    ]
)
```
<!-- -->
:::


## Dependencias del gestor de paquetes Swift. {#swift-package-manager-dependencies}

En Bazel, puede utilizar el complemento
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
para utilizar paquetes Swift como dependencias. El complemento requiere un
`Package.swift` como fuente de verdad para las dependencias. La interfaz de
Tuist es similar a la de Bazel en ese sentido. Puede utilizar el comando `tuist
install` para resolver y extraer las dependencias del paquete. Una vez
completada la resolución, puede generar el proyecto con el comando `tuist
generate`.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## Generación de proyectos {#project-generation}

La comunidad proporciona un conjunto de reglas,
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj),
para generar proyectos Xcode a partir de proyectos declarados en Bazel. A
diferencia de Bazel, donde es necesario añadir alguna configuración al archivo
BUILD` de `, Tuist no requiere ninguna configuración. Puede ejecutar `tuist
generate` en el directorio raíz de su proyecto, y Tuist generará un proyecto
Xcode para usted.
