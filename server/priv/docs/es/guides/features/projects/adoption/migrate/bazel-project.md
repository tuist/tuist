---
{
  "title": "Migrar un proyecto de Bazel",
  "titleTemplate": ":title · Migrar · Adopción · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende a migrar tus proyectos de Bazel a Tuist."
}
---
# Migrar un proyecto de Bazel {#migrate-a-bazel-project}

[Bazel](https://bazel.build) es un sistema de compilación que Google liberó como código abierto en 2015. Es una herramienta potente que te permite compilar y probar software de cualquier tamaño de forma rápida y fiable. Algunas grandes organizaciones como [Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/), [Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae) o [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) lo utilizan; sin embargo, requiere una inversión inicial (es decir, aprender la tecnología) y continua (es decir, mantenerse al día con las actualizaciones de Xcode) para introducirlo y mantenerlo. Aunque esto funciona para algunas organizaciones que lo tratan como una preocupación transversal, puede no ser la mejor opción para otras que quieren centrarse en el desarrollo de su producto. Por ejemplo, hemos visto organizaciones cuyo equipo de plataforma iOS introdujo Bazel y tuvo que abandonarlo después de que los ingenieros que lideraron el esfuerzo dejaran la empresa. La postura de Apple sobre el fuerte acoplamiento entre Xcode y el sistema de compilación es otro factor que dificulta el mantenimiento de proyectos de Bazel con el tiempo.

> [!TIP]
> **La singularidad de Tuist radica en su elegancia**
>
> En lugar de luchar contra Xcode y los proyectos de Xcode, Tuist los adopta. Se basa en los mismos conceptos (por ejemplo, targets, schemes, ajustes de compilación), un lenguaje familiar (es decir, Swift) y una experiencia sencilla y agradable que hace que el mantenimiento y la escalabilidad de los proyectos sean responsabilidad de todos, no solo del equipo de plataforma iOS.


## Reglas {#rules}

Bazel utiliza reglas para definir cómo compilar y probar software. Las reglas se escriben en [Starlark](https://github.com/bazelbuild/starlark), un lenguaje similar a Python. Tuist utiliza Swift como lenguaje de configuración, lo que ofrece a los desarrolladores la comodidad de usar las funciones de autocompletado, comprobación de tipos y validación de Xcode. Por ejemplo, la siguiente regla describe cómo compilar una biblioteca Swift en Bazel:

::: code-group
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

Aquí tienes otro ejemplo comparando cómo definir tests unitarios en Bazel y en Tuist:

::: code-group
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


## Dependencias de Swift Package Manager {#swift-package-manager-dependencies}

En Bazel, puedes usar el plugin [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) para utilizar paquetes Swift como dependencias. El plugin requiere un `Package.swift` como fuente única de verdad para las dependencias. La interfaz de Tuist es similar a la de Bazel en ese sentido. Puedes usar el comando `tuist install` para resolver y descargar las dependencias del paquete. Una vez completada la resolución, puedes generar el proyecto con el comando `tuist generate`.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## Generación del proyecto {#project-generation}

La comunidad proporciona un conjunto de reglas, [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj), para generar proyectos de Xcode a partir de proyectos declarados en Bazel. A diferencia de Bazel, donde necesitas añadir cierta configuración a tu archivo `BUILD`, Tuist no requiere ninguna configuración. Puedes ejecutar `tuist generate` en el directorio raíz de tu proyecto y Tuist generará un proyecto de Xcode por ti.
