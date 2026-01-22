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
gráfico de dependencias **** , que también puede incluir dependencias externas.

## Gráficos codificados en XcodeProj. {#xcodeprojcodified-graphs}

Debido al diseño de Xcode y XcodeProj, el mantenimiento de un gráfico de
dependencias puede ser una tarea tediosa y propensa a errores. A continuación se
muestran algunos ejemplos de los problemas que pueden surgir:

- Dado que el sistema de compilación de Xcode genera todos los productos del
  proyecto en el mismo directorio de datos derivados, es posible que los
  objetivos puedan importar productos que no deberían. Las compilaciones pueden
  fallar en CI, donde las compilaciones limpias son más comunes, o más adelante
  cuando se utiliza una configuración diferente.
- Las dependencias dinámicas transitivas de un objetivo deben copiarse en
  cualquiera de los directorios que forman parte de la configuración de
  compilación `LD_RUNPATH_SEARCH_PATHS`. Si no es así, el objetivo no podrá
  encontrarlas en tiempo de ejecución. Esto es fácil de entender y configurar
  cuando el gráfico es pequeño, pero se convierte en un problema a medida que el
  gráfico crece.
- Cuando un destino enlaza un
  [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
  estático, el destino necesita una fase de compilación adicional para que Xcode
  procese el paquete y extraiga el binario adecuado para la plataforma y la
  arquitectura actuales. Esta fase de compilación no se añade automáticamente y
  es fácil olvidarse de añadirla.

Los anteriores son solo algunos ejemplos, pero hay muchos más con los que nos
hemos encontrado a lo largo de los años. Imagina que necesitaras un equipo de
ingenieros para mantener un gráfico de dependencias y garantizar su validez. O
peor aún, que las complejidades se resolvieran en el momento de la compilación
mediante un sistema de compilación de código cerrado que no puedes controlar ni
personalizar. ¿Te suena familiar? Este es el enfoque que adoptó Apple con Xcode
y XcodeProj y que ha heredado Swift Package Manager.

Creemos firmemente que el gráfico de dependencias debe ser **explícito** y
**estático** porque solo así puede ser **validado** y **optimizado**. Con Tuist,
tú te centras en describir qué depende de qué, y nosotros nos encargamos del
resto. Las complejidades y los detalles de implementación quedan ocultos para
ti.

En las siguientes secciones aprenderás a declarar dependencias en tu proyecto.

::: tip GRAPH VALIDATION
<!-- -->
Tuist valida el gráfico al generar el proyecto para garantizar que no haya
ciclos y que todas las dependencias sean válidas. Gracias a esto, cualquier
equipo puede participar en la evolución del gráfico de dependencias sin
preocuparse por romperlo.
<!-- -->
:::

## Dependencias locales {#local-dependencies}

Los objetivos pueden depender de otros objetivos del mismo proyecto o de otros
proyectos, así como de binarios. Al instanciar un objetivo `Target`, puede pasar
el argumento `dependencies` con cualquiera de las siguientes opciones:

- `Destino`: declara una dependencia con un destino dentro del mismo proyecto.
- `Proyecto`: declara una dependencia con un objetivo en un proyecto diferente.
- `Marco`: Declara una dependencia con un marco binario.
- `Biblioteca`: declara una dependencia con una biblioteca binaria.
- `XCFramework`: declara una dependencia con un binario XCFramework.
- `SDK`: declara una dependencia con un SDK del sistema.
- `XCTest`: Declara una dependencia con XCTest.

::: info DEPENDENCY CONDITIONS
<!-- -->
Cada tipo de dependencia acepta una condición `opción` para vincular
condicionalmente la dependencia en función de la plataforma. De forma
predeterminada, vincula la dependencia para todas las plataformas que admite el
destino.
<!-- -->
:::

## Dependencias externas {#external-dependencies}

Tuist también te permite declarar dependencias externas en tu proyecto.

### Paquetes Swift {#swift-packages}

Los paquetes Swift son nuestra forma recomendada de declarar dependencias en tu
proyecto. Puedes integrarlos utilizando el mecanismo de integración
predeterminado de Xcode o utilizando la integración basada en XcodeProj de
Tuist.

#### Integración basada en XcodeProj de Tuist. {#tuists-xcodeprojbased-integration}

La integración predeterminada de Xcode, aunque es la más cómoda, carece de la
flexibilidad y el control que se requieren para proyectos medianos y grandes.
Para solucionar esto, Tuist ofrece una integración basada en XcodeProj que te
permite integrar paquetes Swift en tu proyecto utilizando los objetivos de
XcodeProj. Gracias a ello, no solo podemos ofrecerte un mayor control sobre la
integración, sino también hacerla compatible con flujos de trabajo como
<LocalizedLink href="/guides/features/cache">almacenamiento en
caché</LocalizedLink> y
<LocalizedLink href="/guides/features/test/selective-testing">ejecuciones de
pruebas selectivas</LocalizedLink>.

Es probable que la integración de XcodeProj requiera más tiempo para admitir las
nuevas funciones de Swift Package o gestionar más configuraciones de paquetes.
Sin embargo, la lógica de mapeo entre Swift Packages y los objetivos de
XcodeProj es de código abierto y la comunidad puede contribuir a ella. Esto
contrasta con la integración predeterminada de Xcode, que es de código cerrado y
está mantenida por Apple.

Para añadir dependencias externas, tendrás que crear un `Package.swift`, ya sea
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
El paquete `PackageSettings La instancia` envuelta en una directiva del
compilador le permite configurar cómo se integran los paquetes. Por ejemplo, en
el ejemplo anterior se utiliza para anular el tipo de producto predeterminado
utilizado para los paquetes. Por defecto, no debería necesitarlo.
<!-- -->
:::

> [!IMPORTANTE] CONFIGURACIONES DE COMPILACIÓN PERSONALIZADAS Si su proyecto
> utiliza configuraciones de compilación personalizadas (configuraciones
> distintas de las estándar `Debug` y `Release`), debe especificarlas en
> `PackageSettings` utilizando `baseSettings`. Las dependencias externas
> necesitan conocer las configuraciones de su proyecto para compilarse
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
> Consulte [#8345](https://github.com/tuist/tuist/issues/8345) para obtener más
> detalles.

El paquete `. El archivo Package.swift` es solo una interfaz para declarar
dependencias externas, nada más. Por eso no se definen objetivos ni productos en
el paquete. Una vez definidas las dependencias, puede ejecutar el siguiente
comando para resolverlas e incorporarlas al directorio `Tuist/Dependencies`:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

Como habrás notado, adoptamos un enfoque similar al de
[CocoaPods](https://cocoapods.org), donde la resolución de dependencias es su
propio comando. Esto da control a los usuarios sobre cuándo desean que se
resuelvan y actualicen las dependencias, y permite abrir Xcode en el proyecto y
tenerlo listo para compilar. Esta es un área en la que creemos que la
experiencia del desarrollador que ofrece la integración de Apple con Swift
Package Manager se degrada con el tiempo a medida que el proyecto crece.

Desde los objetivos de su proyecto, puede hacer referencia a esas dependencias
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
Swift con el fin de mantener limpia la lista de esquemas. Puedes crearlos a
través de la interfaz de usuario de Xcode.
<!-- -->
:::

#### Integración predeterminada de Xcode. {#xcodes-default-integration}

Si desea utilizar el mecanismo de integración predeterminado de Xcode, puede
pasar la lista `packages` al instanciar un proyecto:

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

Para las macros Swift y los complementos de herramientas de compilación, deberá
utilizar los tipos `.macro` y `.plugin` respectivamente.

::: warning SPM Build Tool Plugins
<!-- -->
Los complementos de la herramienta de compilación SPM deben declararse
utilizando el mecanismo [integración predeterminada de
Xcode](#xcode-s-default-integration), incluso cuando se utilice la [integración
basada en XcodeProj](#tuist-s-xcodeproj-based-integration) de Tuist para las
dependencias del proyecto.
<!-- -->
:::

Una aplicación práctica de un complemento de herramienta de compilación SPM es
realizar la depuración de código durante la fase de compilación «Ejecutar
complementos de herramienta de compilación» de Xcode. En un manifiesto de
paquete, esto se define de la siguiente manera:

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
dependencia en su destino. Puede incluir esto en un script que puede ejecutar
antes de generar el proyecto.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

::: warning BUILD AND TEST
<!-- -->
Si compila y prueba su proyecto a través de `xcodebuild build` y `tuist test`,
deberá asegurarse de que las dependencias resueltas por Carthage estén presentes
ejecutando el comando `carthage update` antes de compilar o probar.
<!-- -->
:::

### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) espera un proyecto Xcode para integrar las
dependencias. Puede utilizar Tuist para generar el proyecto y, a continuación,
ejecutar `pod install` para integrar las dependencias creando un espacio de
trabajo que contenga su proyecto y las dependencias de Pods. Puede incluir esto
en un script que puede ejecutar antes de generar el proyecto.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

::: advertencia
<!-- -->
Las dependencias de CocoaPods no son compatibles con flujos de trabajo como
`build` o `test` que ejecutan `xcodebuild` justo después de generar el proyecto.
Tampoco son compatibles con el almacenamiento en caché binario y las pruebas
selectivas, ya que la lógica de huellas digitales no tiene en cuenta las
dependencias de Pods.
<!-- -->
:::

## Estático o dinámico. {#static-or-dynamic}

Los marcos y las bibliotecas se pueden vincular de forma estática o dinámica,
**una elección que tiene importantes implicaciones en aspectos como el tamaño de
la aplicación y el tiempo de arranque**. A pesar de su importancia, esta
decisión se toma a menudo sin mucha consideración.

La regla general **** es que se debe vincular estáticamente el mayor número
posible de elementos en las compilaciones de lanzamiento para lograr tiempos de
arranque rápidos, y vincular dinámicamente el mayor número posible de elementos
en las compilaciones de depuración para lograr tiempos de iteración rápidos.

El reto de cambiar entre enlaces estáticos y dinámicos en un gráfico de proyecto
es que no es trivial en Xcode, ya que un cambio tiene un efecto en cadena en
todo el gráfico (por ejemplo, las bibliotecas no pueden contener recursos, los
marcos estáticos no necesitan estar incrustados). Apple intentó resolver el
problema con soluciones en tiempo de compilación, como la decisión automática de
Swift Package Manager entre enlaces estáticos y dinámicos, o [Mergeable
Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries).
Sin embargo, esto añade nuevas variables dinámicas al gráfico de compilación, lo
que añade nuevas fuentes de indeterminismo y puede hacer que algunas funciones,
como Swift Previews, que dependen del gráfico de compilación, dejen de ser
fiables.

Afortunadamente, Tuist comprime conceptualmente la complejidad asociada al
cambio entre estático y dinámico y sintetiza
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">accesores
de paquetes</LocalizedLink> que son estándar en todos los tipos de enlace. En
combinación con
<LocalizedLink href="/guides/features/projects/dynamic-configuration">configuraciones
dinámicas a través de variables de entorno</LocalizedLink>, puede pasar el tipo
de enlace en el momento de la invocación y utilizar el valor de sus manifiestos
para establecer el tipo de producto de sus objetivos.

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

Ten en cuenta que Tuist
<LocalizedLink href="/guides/features/projects/cost-of-convenience"> no utiliza
la configuración implícita por defecto debido a sus costes</LocalizedLink>. Esto
significa que dependemos de que tú establezcas el tipo de enlace y cualquier
configuración de compilación adicional que sea necesaria en ocasiones, como la
bandera del enlazador [`-ObjC`
](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184),
para garantizar que los binarios resultantes sean correctos. Por lo tanto,
nuestra postura es proporcionarte los recursos, normalmente en forma de
documentación, para que puedas tomar las decisiones correctas.

::: tip EXAMPLE: THE COMPOSABLE ARCHITECTURE
<!-- -->
Un paquete Swift que integran muchos proyectos es [The Composable
Architecture](https://github.com/pointfreeco/swift-composable-architecture).
Para más detalles, consulta [esta sección](#the-composable-architecture).
<!-- -->
:::

### Escenarios {#scenarios}

Hay algunos casos en los que establecer el enlace de forma totalmente estática o
dinámica no es factible ni recomendable. A continuación se incluye una lista no
exhaustiva de casos en los que puede ser necesario combinar enlaces estáticos y
dinámicos:

- **Aplicaciones con extensiones:** Dado que las aplicaciones y sus extensiones
  necesitan compartir código, es posible que tengas que hacer que esos objetivos
  sean dinámicos. De lo contrario, acabarás con el mismo código duplicado tanto
  en la aplicación como en la extensión, lo que provocará un aumento del tamaño
  del binario.
- **Dependencias externas precompiladas:** A veces se proporcionan binarios
  precompilados que son estáticos o dinámicos. Los binarios estáticos se pueden
  envolver en marcos o bibliotecas dinámicos para vincularlos dinámicamente.

Al realizar cambios en el gráfico, Tuist lo analizará y mostrará una advertencia
si detecta un «efecto secundario estático». Esta advertencia tiene como objetivo
ayudarte a identificar problemas que podrían surgir al vincular de forma
estática un objetivo que depende transitivamente de un objetivo estático a
través de objetivos dinámicos. Estos efectos secundarios suelen manifestarse en
forma de aumento del tamaño binario o, en el peor de los casos, fallos en el
tiempo de ejecución.

## Solución de problemas {#troubleshooting}

### Dependencias de Objective-C {#objectivec-dependencies}

Al integrar dependencias de Objective-C, puede ser necesario incluir ciertos
indicadores en el objetivo de consumo para evitar fallos en tiempo de ejecución,
tal y como se detalla en [Apple Technical Q&A
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html).

Dado que el sistema de compilación y Tuist no tienen forma de deducir si la
bandera es necesaria o no, y dado que la bandera tiene efectos secundarios
potencialmente indeseables, Tuist no aplicará automáticamente ninguna de estas
banderas, y dado que Swift Package Manager considera que `-ObjC` se incluye a
través de un `.unsafeFlag`, la mayoría de los paquetes no pueden incluirlo como
parte de su configuración de enlace predeterminada cuando es necesario.

Los consumidores de dependencias de Objective-C (o objetivos internos de
Objective-C) deben aplicar las banderas `-ObjC` o `-force_load` cuando sea
necesario, estableciendo `OTHER_LDFLAGS` en los objetivos de consumo.

### Firebase y otras bibliotecas de Google {#firebase-other-google-libraries}

Las bibliotecas de código abierto de Google, aunque potentes, pueden ser
difíciles de integrar en Tuist, ya que a menudo utilizan una arquitectura y
técnicas no estándar en su construcción.

A continuación se ofrecen algunos consejos que pueden ser necesarios seguir para
integrar Firebase y otras bibliotecas de Google para la plataforma Apple:

#### Asegúrate de que se añaden `-ObjC` a `OTHER_LDFLAGS.` {#ensure-objc-is-added-to-other_ldflags}

Muchas de las bibliotecas de Google están escritas en Objective-C. Por este
motivo, cualquier objetivo de consumo deberá incluir la etiqueta `-ObjC` en su
configuración de compilación `OTHER_LDFLAGS`. Esto se puede configurar en un
archivo `.xcconfig` o especificar manualmente en la configuración del objetivo
dentro de los manifiestos de Tuist. Un ejemplo:

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
anterior para obtener más detalles.

#### Establece el tipo de producto para `FBLPromises` en el marco dinámico. {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Ciertas bibliotecas de Google dependen de `FBLPromises`, otra de las bibliotecas
de Google. Es posible que se encuentre con un error que mencione `FBLPromises`,
con un aspecto similar al siguiente:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

Establecer explícitamente el tipo de producto de `FBLPromises` a `.framework` en
tu `Package.swift` debería solucionar el problema:

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

Tal y como se describe
[aquí](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)
y en la [sección de resolución de problemas](#troubleshooting), tendrás que
establecer la configuración de compilación `OTHER_LDFLAGS` en `$(inherited)
-ObjC` al vincular los paquetes de forma estática, que es el tipo de vinculación
predeterminado de Tuist. Como alternativa, puedes anular el tipo de producto
para que el paquete sea dinámico. Al enlazar de forma estática, los objetivos de
prueba y aplicación suelen funcionar sin problemas, pero las vistas previas de
SwiftUI no funcionan. Esto se puede resolver enlazando todo de forma dinámica.
En el ejemplo siguiente, también se añade
[Sharing](https://github.com/pointfreeco/swift-sharing) como dependencia, ya que
se utiliza a menudo junto con The Composable Architecture y tiene sus propios
[configuration
pitfalls](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

La siguiente configuración lo vinculará todo de forma dinámica, por lo que la
aplicación, los objetivos de prueba y las vistas previas de SwiftUI funcionarán.

::: tip STATIC OR DYNAMIC
<!-- -->
No siempre se recomienda el enlace dinámico. Consulte la sección [Estático o
dinámico](#static-or-dynamic) para obtener más detalles. En este ejemplo, todas
las dependencias se enlazan dinámicamente sin condiciones para simplificar.
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
En lugar de `import Sharing`, tendrás que `import SwiftSharing`.
<!-- -->
:::

### Dependencias estáticas transitivas que se filtran a través de `.swiftmodule` {#transitive-static-dependencies-leaking-through-swiftmodule}

Cuando un marco o biblioteca dinámico depende de otros estáticos a través de
`import StaticSwiftModule`, los símbolos se incluyen en el `.swiftmodule` del
marco o biblioteca dinámico, lo que puede
<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">provocar
que la compilación falle</LocalizedLink>. Para evitarlo, tendrás que importar la
dependencia estática utilizando
<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal
import`</LocalizedLink>:

```swift
internal import StaticModule
```

::: info
<!-- -->
El nivel de acceso en las importaciones se incluyó en Swift 6. Si utilizas
versiones anteriores de Swift, debes utilizar
<LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>
en su lugar:
<!-- -->
:::

```swift
@_implementationOnly import StaticModule
```
