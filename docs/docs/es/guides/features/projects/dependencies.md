---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# Dependencias {#dependencies}

Cuando un proyecto crece, es habitual dividirlo en varios objetivos para
compartir código, definir límites y mejorar los tiempos de compilación.
Múltiples objetivos significa definir dependencias entre ellos formando un
gráfico de dependencias **** , que puede incluir también dependencias externas.

## Gráficos codificados con XcodeProj {#xcodeprojcodified-graphs}

Debido al diseño de Xcode y XcodeProj, el mantenimiento de un gráfico de
dependencias puede ser una tarea tediosa y propensa a errores. Aquí tienes
algunos ejemplos de los problemas que te puedes encontrar:

- Dado que el sistema de compilación de Xcode envía todos los productos del
  proyecto al mismo directorio en datos derivados, los objetivos podrían
  importar productos que no deberían. Las compilaciones pueden fallar en CI,
  donde las compilaciones limpias son más comunes, o más tarde cuando se utiliza
  una configuración diferente.
- Las dependencias dinámicas transitivas de un objetivo deben copiarse en
  cualquiera de los directorios que forman parte de la configuración de
  compilación de `LD_RUNPATH_SEARCH_PATHS`. Si no lo están, el objetivo no será
  capaz de encontrarlas en tiempo de ejecución. Esto es fácil de pensar y
  configurar cuando el gráfico es pequeño, pero se convierte en un problema a
  medida que el gráfico crece.
- Cuando un objetivo enlaza un
  [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
  estático, el objetivo necesita una fase de compilación adicional para que
  Xcode procese el paquete y extraiga el binario correcto para la plataforma y
  arquitectura actuales. Esta fase de compilación no se añade automáticamente, y
  es fácil olvidarse de añadirla.

Los anteriores son sólo algunos ejemplos, pero hay muchos más que nos hemos
encontrado a lo largo de los años. Imagínese que necesitara un equipo de
ingenieros para mantener un gráfico de dependencias y garantizar su validez. O
peor aún, que las complejidades se resolvieran en el momento de la compilación
mediante un sistema de compilación de código cerrado que no se puede controlar
ni personalizar. ¿Te suena? Este es el enfoque que Apple adoptó con Xcode y
XcodeProj y que el gestor de paquetes de Swift ha heredado.

Creemos firmemente que el grafo de dependencias debe ser **explícito** y
**estático** porque sólo así podrá ser **validado** y **optimizado**. Con Tuist,
tú te centras en describir qué depende de qué, y nosotros nos encargamos del
resto. Las complejidades y los detalles de implementación se abstraen de ti.

En las siguientes secciones aprenderás a declarar dependencias en tu proyecto.

::: tip GRAPH VALIDATION
<!-- -->
Tuist valida el grafo al generar el proyecto para asegurarse de que no hay
ciclos y de que todas las dependencias son válidas. Gracias a ello, cualquier
equipo puede participar en la evolución del grafo de dependencias sin
preocuparse por romperlo.
<!-- -->
:::

## Dependencias locales {#local-dependencies}

Los objetivos pueden depender de otros objetivos del mismo proyecto o de
proyectos diferentes, así como de binarios. Al instanciar un objetivo `` , puede
pasar el argumento `dependencies` con cualquiera de las siguientes opciones:

- `Objetivo`: Declara una dependencia con un objetivo dentro del mismo proyecto.
- `Proyecto`: Declara una dependencia con un objetivo en un proyecto diferente.
- `Framework`: Declara una dependencia con un framework binario.
- `Biblioteca`: Declara una dependencia con una biblioteca binaria.
- `XCFramework`: Declara una dependencia con un binario XCFramework.
- `SDK`: Declara una dependencia con un SDK del sistema.
- `XCTest`: Declara una dependencia con XCTest.

::: info DEPENDENCY CONDITIONS
<!-- -->
Cada tipo de dependencia acepta la opción `condition` para vincular
condicionalmente la dependencia en función de la plataforma. Por defecto,
vincula la dependencia para todas las plataformas que admite el destino.
<!-- -->
:::

## Dependencias externas {#external-dependencies}

Tuist también te permite declarar dependencias externas en tu proyecto.

### Paquetes Swift {#swift-packages}

Los paquetes Swift son nuestra forma recomendada de declarar dependencias en tu
proyecto. Puedes integrarlos usando el mecanismo de integración por defecto de
Xcode o usando la integración basada en XcodeProj de Tuist.

#### Integración de Tuist basada en XcodeProj {#tuists-xcodeprojbased-integration}

La integración por defecto de Xcode, aunque es la más conveniente, carece de la
flexibilidad y el control necesarios para proyectos medianos y grandes. Para
superar esto, Tuist ofrece una integración basada en XcodeProj que te permite
integrar paquetes Swift en tu proyecto utilizando los objetivos de XcodeProj.
Gracias a ello, no sólo podemos darte más control sobre la integración, sino
también hacerla compatible con flujos de trabajo como
<LocalizedLink href="/guides/features/cache">caching</LocalizedLink> y
<LocalizedLink href="/guides/features/test/selective-testing">ejecuciones de prueba selectivas</LocalizedLink>.

Es más probable que la integración de XcodeProj lleve más tiempo para soportar
nuevas características de Swift Package o manejar más configuraciones de
paquetes. Sin embargo, la lógica de mapeo entre paquetes Swift y objetivos
XcodeProj es de código abierto y puede ser contribuido por la comunidad. Esto es
contrario a la integración por defecto de Xcode, que es de código cerrado y
mantenido por Apple.

Para añadir dependencias externas, tendrás que crear un `Package.swift` ya sea
en `Tuist/` o en la raíz del proyecto.

::: grupo de códigos
```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
    ]
)
```
<!-- -->
:::

::: tip PACKAGE SETTINGS
<!-- -->
La instancia `PackageSettings` envuelta en una directiva de compilador permite
configurar cómo se integran los paquetes. Por ejemplo, en el ejemplo anterior se
utiliza para anular el tipo de producto por defecto utilizado para los paquetes.
Por defecto, no debería necesitarla.
<!-- -->
:::

> [IMPORTANTE] CONFIGURACIONES DE CONSTRUCCIÓN PERSONALIZADAS Si su proyecto
> utiliza configuraciones de construcción personalizadas (configuraciones
> distintas de las estándar `Debug` y `Release`), debe especificarlas en
> `PackageSettings` utilizando `baseSettings`. Las dependencias externas
> necesitan conocer las configuraciones de tu proyecto para construirse
> correctamente. Por ejemplo:
> 
> ```swift
> #if TUIST
>     import ProjectDescription
> 
>     let packageSettings = PackageSettings(
>         productTypes: [:],
>         baseSettings: .settings(configurations: [
>             .debug(name: "Base"),
>             .release(name: "Production")
>         ])
>     )
> #endif
> ```
> 
> Véase [#8345](https://github.com/tuist/tuist/issues/8345) para más detalles.

El archivo `Package.swift` es sólo una interfaz para declarar dependencias
externas, nada más. Por eso no defines ningún objetivo o producto en el paquete.
Una vez que tengas las dependencias definidas, puedes ejecutar el siguiente
comando para resolver y extraer las dependencias en el directorio
`Tuist/Dependencies`:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

Como habrás notado, tomamos un enfoque similar al de
[CocoaPods](https://cocoapods.org)', donde la resolución de dependencias es su
propio comando. Esto da el control a los usuarios sobre cuándo les gustaría que
las dependencias se resuelvan y actualicen, y permite abrir el proyecto en Xcode
y tenerlo listo para compilar. Esta es un área donde creemos que la experiencia
del desarrollador proporcionada por la integración de Apple con el gestor de
paquetes Swift se degrada con el tiempo a medida que el proyecto crece.

Desde los objetivos del proyecto se puede hacer referencia a esas dependencias
utilizando el tipo de dependencia `TargetDependency.external`:

::: grupo de códigos
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "Alamofire"), // [!code ++]
            ]
        ),
    ]
)
```
<!-- -->
:::

::: info NO SCHEMES GENERATED FOR EXTERNAL PACKAGES
<!-- -->
Los esquemas **** no se crean automáticamente para los proyectos de paquetes
Swift para mantener limpia la lista de esquemas. Puede crearlos a través de la
interfaz de usuario de Xcode.
<!-- -->
:::

#### Integración por defecto de Xcode {#xcodes-default-integration}

Si desea utilizar el mecanismo de integración por defecto de Xcode, puede pasar
la lista `paquetes` al instanciar un proyecto:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

Y luego haz referencia a ellos desde tus objetivos:

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Para las macros Swift y los plugins de herramientas de compilación, deberá
utilizar los tipos `.macro` y `.plugin` respectivamente.

::: warning SPM Build Tool Plugins
<!-- -->
Los plugins de la herramienta de compilación SPM deben ser declarados usando el
mecanismo de [integración por defecto de Xcode](#xcode-s-default-integration),
incluso cuando se usa [integración basada en
XcodeProj](#tuist-s-xcodeproj-based-integration) de Tuist para las dependencias
de tu proyecto.
<!-- -->
:::

Una aplicación práctica de un plugin de herramientas de compilación SPM es
realizar la limpieza de código durante la fase de compilación de Xcode "Ejecutar
plugins de herramientas de compilación". En un manifiesto de paquete esto se
define de la siguiente manera:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framework",
    products: [
        .library(name: "Framework", targets: ["Framework"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            plugins: [
                .plugin(name: "SwiftLint", package: "SwiftLintPlugin"),
            ]
        ),
    ]
)
```

Para generar un proyecto Xcode con el complemento de la herramienta de
compilación intacto, debe declarar el paquete en la matriz `packages` del
manifiesto del proyecto y, a continuación, incluir un paquete con el tipo
`.plugin` en las dependencias de un objetivo.

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .remote(url: "https://github.com/SimplyDanny/SwiftLintPlugins", requirement: .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Cartago {#carthage}

Dado que [Carthage](https://github.com/carthage/carthage) genera `frameworks` o
`xcframeworks`, puede ejecutar `carthage update` para generar las dependencias
en el directorio `Carthage/Build` y, a continuación, utilizar el tipo de
dependencia de destino `.framework` o `.xcframework` para declarar la
dependencia en su destino. Puede envolver esto en un script que puede ejecutar
antes de generar el proyecto.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

::: warning BUILD AND TEST
<!-- -->
Si construyes y pruebas tu proyecto a través de `xcodebuild build` y `tuist
test`, necesitarás igualmente asegurarte de que las dependencias resueltas por
Carthage están presentes ejecutando el comando `carthage update` antes de
construir o probar.
<!-- -->
:::

### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) espera un proyecto Xcode para integrar las
dependencias. Puedes usar Tuist para generar el proyecto, y luego ejecutar `pod
install` para integrar las dependencias creando un espacio de trabajo que
contenga tu proyecto y las dependencias de Pods. Puedes envolver esto en un
script que puedes ejecutar antes de generar el proyecto.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

::: advertencia
<!-- -->
Las dependencias de CocoaPods no son compatibles con flujos de trabajo como
`build` o `test` que ejecutan `xcodebuild` justo después de generar el proyecto.
También son incompatibles con el almacenamiento en caché de binarios y las
pruebas selectivas, ya que la lógica de huella digital no tiene en cuenta las
dependencias de Pods.
<!-- -->
:::

## Estática o dinámica {#static-or-dynamic}

Los frameworks y las librerías pueden enlazarse de forma estática o dinámica,
**una elección que tiene implicaciones significativas en aspectos como el tamaño
de la aplicación y el tiempo de arranque**. A pesar de su importancia, esta
decisión suele tomarse sin mucha consideración.

La regla general de **** es que se deben enlazar estáticamente tantas cosas como
sea posible en las versiones de lanzamiento para conseguir tiempos de arranque
rápidos, y enlazar dinámicamente tantas cosas como sea posible en las versiones
de depuración para conseguir tiempos de iteración rápidos.

El reto con el cambio entre la vinculación estática y dinámica en un gráfico de
proyecto es que no es trivial en Xcode porque un cambio tiene efecto en cascada
en todo el gráfico (por ejemplo, las bibliotecas no pueden contener recursos,
los frameworks estáticos no necesitan ser incrustados). Apple trató de resolver
el problema con soluciones en tiempo de compilación como la decisión automática
de Swift Package Manager entre vinculación estática y dinámica, o [Mergeable
Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries).
Sin embargo, esto añade nuevas variables dinámicas al grafo de compilación,
añadiendo nuevas fuentes de no-determinismo, y potencialmente causando que
algunas características como Swift Previews que dependen del grafo de
compilación se vuelvan poco fiables.

Por suerte, Tuist comprime conceptualmente la complejidad asociada al cambio
entre estático y dinámico y sintetiza
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">accesores de paquete</LocalizedLink> que son estándar en todos los tipos de vinculación.
En combinación con
<LocalizedLink href="/guides/features/projects/dynamic-configuration">configuraciones dinámicas a través de variables de entorno</LocalizedLink>, puedes pasar el tipo
de enlace en el momento de la invocación, y utilizar el valor en tus manifiestos
para establecer el tipo de producto de tus objetivos.

```swift
// Use the value returned by this function to set the product type of your targets.
func productType() -> Product {
    if case let .string(linking) = Environment.linking {
        return linking == "static" ? .staticFramework : .framework
    } else {
        return .framework
    }
}
```

Tenga en cuenta que Tuist
<LocalizedLink href="/guides/features/projects/cost-of-convenience">no es conveniente por defecto a través de la configuración implícita debido a sus costes</LocalizedLink>. Lo que esto significa es que dependemos de que
establezcas el tipo de enlazado y cualquier otra configuración de compilación
adicional que a veces se requiera, como [`-ObjC` linker
flag](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184),
para asegurarnos de que los binarios resultantes son correctos. Por lo tanto, la
postura que adoptamos es proporcionarle los recursos, normalmente en forma de
documentación, para que tome las decisiones correctas.

::: tip EXAMPLE: THE COMPOSABLE ARCHITECTURE
<!-- -->
Un paquete Swift que muchos proyectos integran es [The Composable
Architecture](https://github.com/pointfreeco/swift-composable-architecture). Ver
más detalles en [esta sección](#the-composable-architecture).
<!-- -->
:::

### Escenarios {#scenarios}

Hay algunos escenarios en los que no es factible o una buena idea establecer el
enlazado completamente en estático o dinámico. A continuación se ofrece una
lista no exhaustiva de situaciones en las que puede ser necesario combinar la
vinculación estática y dinámica:

- **Aplicaciones con extensiones:** Dado que las aplicaciones y sus extensiones
  necesitan compartir código, es posible que tengas que hacer que esos objetivos
  sean dinámicos. De lo contrario, acabarás con el mismo código duplicado tanto
  en la app como en la extensión, lo que hará que aumente el tamaño del binario.
- **Dependencias externas precompiladas:** A veces se proporcionan binarios
  precompilados que pueden ser estáticos o dinámicos. Los binarios estáticos
  pueden envolverse en frameworks dinámicos o bibliotecas para enlazarse
  dinámicamente.

Al realizar cambios en el gráfico, Tuist lo analizará y mostrará una advertencia
si detecta un "efecto secundario estático". Esta advertencia pretende ayudarte a
identificar los problemas que pueden surgir al enlazar estáticamente un objetivo
que depende transitivamente de un objetivo estático a través de objetivos
dinámicos. Estos efectos secundarios suelen manifestarse como un aumento del
tamaño del binario o, en el peor de los casos, fallos en tiempo de ejecución.

## Solución de problemas {#troubleshooting}

### Dependencias de Objective-C {#objectivec-dependencies}

Al integrar dependencias de Objective-C, puede ser necesaria la inclusión de
determinados indicadores en el destino de consumo para evitar bloqueos en tiempo
de ejecución, tal y como se detalla en [Apple Technical Q&A
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html).

Dado que el sistema de compilación y Tuist no tienen forma de inferir si la
bandera es necesaria o no, y dado que la bandera viene con efectos secundarios
potencialmente indeseables, Tuist no aplicará automáticamente ninguna de estas
banderas, y dado que el gestor de paquetes Swift considera `-ObjC` para ser
incluido a través de un `.unsafeFlag` la mayoría de los paquetes no pueden
incluirlo como parte de su configuración de enlace por defecto cuando sea
necesario.

Los consumidores de dependencias de Objective-C (u objetivos internos de
Objective-C) deben aplicar los indicadores `-ObjC` o `-force_load` cuando sea
necesario mediante la configuración de `OTHER_LDFLAGS` en los objetivos
consumidores.

### Firebase y otras bibliotecas de Google {#firebase-other-google-libraries}

Las bibliotecas de código abierto de Google, aunque potentes, pueden ser
difíciles de integrar en Tuist, ya que a menudo utilizan arquitecturas y
técnicas no estándar en su construcción.

Estos son algunos consejos que puede ser necesario seguir para integrar Firebase
y otras librerías de Google para la plataforma de Apple:

#### Asegúrese de que `-ObjC` se añade a `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Muchas de las bibliotecas de Google están escritas en Objective-C. Debido a
esto, cualquier objetivo de consumo tendrá que incluir la etiqueta `-ObjC` en su
`OTHER_LDFLAGS` configuración de construcción. Esto puede establecerse en un
archivo `.xcconfig` o especificarse manualmente en la configuración del objetivo
dentro de sus manifiestos Tuist. Un ejemplo:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

Consulte la sección [Dependencias de Objective-C](#objective-c-dependencies)
anterior para obtener más información.

#### Establezca el tipo de producto para `FBLPromises` en marco dinámico {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Ciertas bibliotecas de Google dependen de `FBLPromises`, otra de las bibliotecas
de Google. Es posible que te encuentres con un fallo que menciona `FBLPromises`,
con un aspecto similar a este:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

Establecer explícitamente el tipo de producto de `FBLPromises` a `.framework` en
su archivo `Package.swift` debería solucionar el problema:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FBLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### La arquitectura componible {#the-composable-architecture}

Como se describe
[aquí](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)
y en la [sección de solución de problemas](#troubleshooting), tendrás que
establecer el parámetro de compilación `OTHER_LDFLAGS` a `$(inherited) -ObjC` al
enlazar los paquetes estáticamente, que es el tipo de enlace por defecto de
Tuist. Alternativamente, puedes anular el tipo de producto para que el paquete
sea dinámico. Cuando se vincula estáticamente, los objetivos de prueba y de
aplicación suelen funcionar sin problemas, pero las vistas previas de SwiftUI
están rotas. Esto se puede resolver vinculando todo dinámicamente. En el ejemplo
de abajo [Sharing](https://github.com/pointfreeco/swift-sharing) también se
añade como una dependencia, ya que se utiliza a menudo junto con la arquitectura
componible y tiene su propia [configuración
pitfalls](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

La siguiente configuración enlazará todo dinámicamente - por lo que la
aplicación + los objetivos de prueba y las vistas previas de SwiftUI están
funcionando.

::: tip STATIC OR DYNAMIC
<!-- -->
No siempre se recomienda la vinculación dinámica. Véase la sección [Estático o
dinámico](#static-or-dynamic) para más detalles. En este ejemplo, todas las
dependencias se enlazan dinámicamente sin condiciones por simplicidad.
<!-- -->
:::

```swift [Tuist/Package.swift]
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import enum ProjectDescription.Environment
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "CasePaths": .framework,
        "CasePathsCore": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ComposableArchitecture": .framework,
        "ConcurrencyExtras": .framework,
        "CustomDump": .framework,
        "Dependencies": .framework,
        "DependenciesTestSupport": .framework,
        "IdentifiedCollections": .framework,
        "InternalCollectionsUtilities": .framework,
        "IssueReporting": .framework,
        "IssueReportingPackageSupport": .framework,
        "IssueReportingTestSupport": .framework,
        "OrderedCollections": .framework,
        "Perception": .framework,
        "PerceptionCore": .framework,
        "Sharing": .framework,
        "SnapshotTesting": .framework,
        "SwiftNavigation": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "XCTestDynamicOverlay": .framework
    ],
    targetSettings: [
        "ComposableArchitecture": .settings(base: [
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]),
        "Sharing": .settings(base: [
            "PRODUCT_NAME": "SwiftSharing",
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ])
    ]
)
#endif
```

::: advertencia
<!-- -->
En lugar de `import Sharing` tendrás que `import SwiftSharing`.
<!-- -->
:::

### Fugas de dependencias estáticas transitivas a través de `.swiftmodule` {#transitive-static-dependencies-leaking-through-swiftmodule}

Cuando un framework o librería dinámicos dependen de otros estáticos a través de
`import StaticSwiftModule`, los símbolos se incluyen en el `.swiftmodule` del
framework o librería dinámicos, pudiendo
<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">causar el fallo de compilación</LocalizedLink>. Para evitarlo, tendrá que importar la
dependencia estática utilizando
<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</LocalizedLink>:

```swift
internal import StaticModule
```

::: info
<!-- -->
El nivel de acceso en las importaciones se incluyó en Swift 6. Si utiliza
versiones anteriores de Swift, deberá utilizar
<LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>
en su lugar:
<!-- -->
:::

```swift
@_implementationOnly import StaticModule
```
